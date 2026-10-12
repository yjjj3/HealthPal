import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:health_management_app/services/ai/ai_client.dart';
import 'package:health_management_app/services/prescription_scan_service.dart';
import 'package:health_management_app/services/prescription_medication_mapper.dart';
import 'package:health_management_app/models/prescription_model.dart';
import 'package:health_management_app/models/ai/prescription_recognition.dart';
import '../tool/prescription_eval/evaluator.dart';

/// Flutter host is necessary for the actual production service's plugin imports.
/// MockClient cannot reach any network, even when input is malformed.
Future<Map<String, dynamic>> evaluateOffline(
  dynamic golden,
  dynamic predictions,
) async {
  final cases = validateGolden(golden);
  final index = predictionIndex(predictions);
  final ids = cases.map((c) => c['caseId']).toSet();
  final extraCases = index.keys.where((id) => !ids.contains(id)).toList();
  final reports = <Map<String, dynamic>>[];
  Map<String, dynamic>? contract;
  for (final c in cases) {
    final p = index[c['caseId']] as Map<String, dynamic>?;
    dynamic raw;
    var jsonValid = false;
    if (p != null) {
      try {
        raw = jsonDecode(p['raw']);
        jsonValid = true;
      } catch (_) {}
    }
    final issues = jsonValid
        ? schemaIssues(
            raw,
            PrescriptionRecognition.responseFormat['json_schema']['schema']
                as Map<String, dynamic>,
          )
        : ['invalid_json'];
    Map<String, dynamic>? normalized;
    String? failure, mappingFailure;
    List<Map<String, dynamic>>? converted;
    Map<String, dynamic>? request;
    if (p != null) {
      final client = AIClient(
        apiKey: () => 'synthetic-placeholder',
        clientFactory: () => MockClient((r) async {
          request = jsonDecode(r.body) as Map<String, dynamic>;
          // Optional envelope exists solely to inject refusal/truncation/malformed
          // responses through the same production AIClient boundary.
          return http.Response(
            jsonEncode(
              p['envelope'] ??
                  {
                    'choices': [
                      {
                        'finish_reason': 'stop',
                        'message': {'content': p['raw']},
                      },
                    ],
                  },
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final service = PrescriptionScanService(
        firestore: FakeFirebaseFirestore(),
        currentUid: () => 'synthetic-eval',
        client: client,
      );
      try {
        normalized = await service.recognizePrescriptionFromBytes(
          Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
        );
        final models = (normalized['medicines'] as List)
            .map(
              (m) => PrescriptionMedicine.fromJson(m as Map<String, dynamic>),
            )
            .toList();
        // Production conversion uses DateTime.now when no start date exists.
        // Keep that behavior exercised, but exclude operational time from the
        // evaluation artifact; it is neither OCR truth nor an accuracy field.
        converted = models.map((m) => m.toJson()..remove('startDate')).toList();
        try {
          PrescriptionMedicationMapper.convert(models, MealTimeSettings());
        } catch (e) {
          mappingFailure = e.runtimeType.toString();
        }
      } catch (e) {
        failure = e is AIException ? e.code : e.runtimeType.toString();
      }
    }
    if (request != null) {
      contract ??= {
        'model': request!['model'],
        'max_tokens': request!['max_tokens'],
        'temperature': request!['temperature'],
        'response_format': request!['response_format'],
      };
    }
    final rawScore = scoreFields(c, raw);
    final normalizedScore = scoreFields(c, normalized);
    reports.add({
      'caseId': c['caseId'],
      'synthetic': true,
      'missingPrediction': p == null,
      'jsonParseable': jsonValid,
      'schemaIssues': issues,
      'serviceAccepted': normalized != null,
      'serviceFailure': failure,
      'raw': rawScore,
      'postNormalization': normalizedScore,
      'wholeExactRaw':
          rawScore['exactFields'] == true &&
          issues.isEmpty &&
          normalized != null,
      'wholeExactNormalized':
          normalizedScore['exactFields'] == true &&
          issues.isEmpty &&
          normalized != null,
      'modelConversion': converted,
      'modelConversionExcludedTimeFields': ['startDate'],
      'mapperAccepted': normalized != null && mappingFailure == null,
      'mapperFailure': mappingFailure,
      'humanConfirmationRequired': c['humanConfirmation']['required'],
    });
  }
  Map<String, dynamic> aggregate(String stage) {
    final totals = {
      'correct': 0,
      'incorrect': 0,
      'missing': 0,
      'hallucinated': 0,
    };
    var expected = 0, known = 0, unknown = 0, extra = 0;
    final perField = <String, dynamic>{};
    for (final report in reports) {
      final score = report[stage] as Map<String, dynamic>;
      for (final k in totals.keys) {
        totals[k] = totals[k]! + (score['counts'][k] as int);
      }
      expected += score['expectedFieldDenominator'] as int;
      known += score['knownDenominator'] as int;
      unknown += score['unknownDenominator'] as int;
      extra += score['extraFieldPenalty'] as int;
      for (final d in score['details']) {
        final path = d['path'] as String;
        final key =
            '${path.startsWith('hospitalInfo') ? 'hospitalInfo' : 'medicine'}.${path.split('.').last}';
        final f = perField.putIfAbsent(
          key,
          () => {
            'expected': 0,
            'known': 0,
            'unknown': 0,
            'knownCorrect': 0,
            'unknownCorrect': 0,
            'correct': 0,
            'incorrect': 0,
            'missing': 0,
            'hallucinated': 0,
          },
        );
        f[d['category']]++;
        if (!path.startsWith('extraMedicine')) {
          f['expected']++;
          f[d['truthUnknown'] == true ? 'unknown' : 'known']++;
          if (d['category'] == 'correct') {
            f[d['truthUnknown'] == true ? 'unknownCorrect' : 'knownCorrect']++;
          }
        }
      }
    }
    return {
      'counts': totals,
      'expectedFieldDenominator': expected,
      'knownDenominator': known,
      'unknownDenominator': unknown,
      'extraFieldPenalty': extra,
      'perField': perField,
    };
  }

  final count = reports.length;
  return {
    'version': 1,
    'requestContract': contract,
    'fieldSummary': {
      'raw': aggregate('raw'),
      'postNormalization': aggregate('postNormalization'),
    },
    'origin': predictions['origin'],
    'disclaimer':
        'Synthetic scorer/contract validation ONLY. No OCR, model, clinical or device accuracy measured.',
    'casesDenominator': count,
    'missingCases': reports
        .where((r) => r['missingPrediction'] == true)
        .map((r) => r['caseId'])
        .toList(),
    'extraCases': extraCases,
    'completeCaseSet':
        extraCases.isEmpty &&
        reports.every((r) => r['missingPrediction'] == false),
    'jsonParseableCount': reports
        .where((r) => r['jsonParseable'] == true)
        .length,
    'jsonParseableRate': count == 0
        ? 0
        : reports.where((r) => r['jsonParseable'] == true).length / count,
    'schemaValidCount': reports
        .where((r) => (r['schemaIssues'] as List).isEmpty)
        .length,
    'serviceAcceptedCount': reports
        .where((r) => r['serviceAccepted'] == true)
        .length,
    'wholeExactRawCount': reports
        .where((r) => r['wholeExactRaw'] == true)
        .length,
    'wholeExactNormalizedCount': reports
        .where((r) => r['wholeExactNormalized'] == true)
        .length,
    'reports': reports,
  };
}

void main() {
  test(
    'offline CLI production service driver',
    () async {
      final env = Platform.environment;
      final result = await evaluateOffline(
        jsonDecode(File(env['HEALTHPAL_EVAL_GOLDEN']!).readAsStringSync()),
        jsonDecode(File(env['HEALTHPAL_EVAL_PREDICTIONS']!).readAsStringSync()),
      );
      File(env['HEALTHPAL_EVAL_OUTPUT']!).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
      final schemaPath = env['HEALTHPAL_EVAL_SCHEMA'];
      if (schemaPath != null) {
        File(schemaPath).writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(PrescriptionRecognition.responseFormat['json_schema']['schema'])}\n',
        );
      }
    },
    skip: Platform.environment['HEALTHPAL_EVAL_OUTPUT'] == null,
  );
}
