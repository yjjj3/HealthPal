import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../tool/prescription_eval/evaluator.dart';
import 'package:health_management_app/models/ai/prescription_recognition.dart';
import 'prescription_eval_driver_test.dart' show evaluateOffline;

Map<String, dynamic> load(String name) =>
    jsonDecode(
          File('test/fixtures/prescription_eval/$name.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
Map<String, dynamic> clone(Map<String, dynamic> v) =>
    jsonDecode(jsonEncode(v)) as Map<String, dynamic>;
void main() {
  test('JSON Schema integer accepts mathematical integers only', () {
    for (final value in [2, 2.0, 0.0, -2.0, 9007199254740993]) {
      expect(schemaIssues(value, {'type': 'integer'}), isEmpty);
    }
    for (final value in [
      2.5,
      true,
      false,
      '2',
      null,
      double.infinity,
      double.nan,
    ]) {
      expect(schemaIssues(value, {'type': 'integer'}), isNotEmpty);
    }
    expect(schemaIssues(2.0, {'type': 'number'}), isEmpty);
  });
  test('name-only matching uses name rules and retains English priority', () {
    final c = validateGolden(load('golden')).first;
    c['normalization'] = {
      'name': ['trim', 'casefold'],
      'englishName': [],
    };
    c['truth']['medicines'][0]['englishName'] = null;
    final raw = clone(c['truth']);
    raw['medicines'][0]['name'] = '  synth-01  ';
    expect(scoreFields(c, raw)['exactFields'], true);
    raw['medicines'].add(clone(raw['medicines'][0]));
    expect(scoreFields(c, raw)['extraRows'], 1);
    raw['medicines'] = [];
    expect(scoreFields(c, raw)['missingRows'], 1);
    expect(
      identity({
        'name': ' normalize ',
        'englishName': ' EN ',
      }, c['normalization']),
      ' EN ',
    );
    c['normalization'] = {
      'name': [],
      'englishName': ['trim', 'casefold'],
    };
    expect(
      identity({
        'name': ' Keep Case ',
        'englishName': null,
      }, c['normalization']),
      ' Keep Case ',
    );
  });
  test(
    'conversion time excluded; unchanged evaluation semantics stable',
    () async {
      final first = await evaluateOffline(load('golden'), load('oracle'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final second = await evaluateOffline(load('golden'), load('oracle'));
      expect(second['fieldSummary'], first['fieldSummary']);
      for (var i = 0; i < 16; i++) {
        expect(
          second['reports'][i]['modelConversion'],
          first['reports'][i]['modelConversion'],
        );
        for (final row in first['reports'][i]['modelConversion']) {
          expect(row.containsKey('startDate'), false);
        }
      }
    },
  );

  test('checked-in schema equals production requested response schema', () {
    final schema = jsonDecode(
      File(
        'test/fixtures/prescription_eval/production-response-schema.json',
      ).readAsStringSync(),
    );
    expect(
      schema,
      PrescriptionRecognition.responseFormat['json_schema']['schema'],
    );
  });

  test(
    'oracle only validates scorer, production parser reveals English name fallback',
    () async {
      final result = await evaluateOffline(load('golden'), load('oracle'));
      expect(result['casesDenominator'], 16);
      expect(result['schemaValidCount'], 16);
      expect(result['serviceAcceptedCount'], 16);
      expect(result['wholeExactRawCount'], 16);
      expect(result['wholeExactNormalizedCount'], 15);
      final english = (result['reports'] as List)[2];
      expect(english['postNormalization']['counts']['hallucinated'], 1);
      expect(result['requestContract']['model'], 'gpt-4o');
      expect(result['requestContract']['max_tokens'], 4096);
      expect(result['requestContract']['temperature'], 0.1);
    },
  );
  test(
    'deliberately wrong synthetic outputs are classified, not model results',
    () async {
      final result = await evaluateOffline(
        load('golden'),
        load('synthetic_errors'),
      );
      final reports = result['reports'] as List;
      expect(reports[0]['raw']['counts']['incorrect'], 1); // warning omission
      expect(reports[1]['wholeExactRaw'], true); // reordered distinct rows
      expect(
        reports[3]['raw']['counts']['hallucinated'],
        1,
      ); // unknown invented dose
      expect(reports[11]['raw']['extraRows'], 1);
      expect(reports[12]['raw']['missingRows'], 1);
      expect(reports[15]['raw']['missingRows'], 1);
      expect(result['jsonParseableCount'], 15);
    },
  );
  test(
    'one-to-one same-name matching permits reorder but counts duplicate row',
    () {
      final c = validateGolden(load('golden')).last;
      final raw = clone(c['truth']);
      raw['medicines'] = (raw['medicines'] as List).reversed.toList();
      expect(scoreFields(c, raw)['exactFields'], true);
      raw['medicines'].add(raw['medicines'][0]);
      final score = scoreFields(c, raw);
      expect(score['extraRows'], 1);
      expect(score['counts']['hallucinated'], medicineFields.length);
      expect(
        score['expectedFieldDenominator'],
        medicineFields.length * 2 + hospitalFields.length,
      );
    },
  );
  test(
    'unknown/null, missing keys, empty, invented and wrong type stay distinct',
    () {
      final c = validateGolden(load('golden'))[3];
      final raw = clone(c['truth']);
      expect(scoreFields(c, raw)['exactFields'], true);
      raw['medicines'][0].remove('dosage');
      expect(scoreFields(c, raw)['counts']['missing'], 1);
      raw['medicines'][0]['dosage'] = '';
      expect(scoreFields(c, raw)['counts']['hallucinated'], 1);
      raw['medicines'][0]['dosage'] = false;
      expect(scoreFields(c, raw)['counts']['hallucinated'], 1);
      raw['medicines'][0]['unit'] = '';
      expect(scoreFields(c, raw)['counts']['missing'], 1);
    },
  );
  test(
    'name only allowed normalization, warning punctuation never normalized',
    () {
      final c = validateGolden(load('golden')).first;
      final raw = clone(c['truth']);
      raw['medicines'][0]['name'] = '  synth-01  ';
      raw['medicines'][0]['englishName'] = '  synth-01  ';
      expect(scoreFields(c, raw)['exactFields'], true);
      raw['medicines'][0]['precautions'] += ' ';
      expect(scoreFields(c, raw)['counts']['incorrect'], 1);
    },
  );
  test(
    'duplicate golden IDs, missing truth key, wrong header and unknown metadata rejected',
    () {
      var g = load('golden');
      g['cases'][1]['caseId'] = 'S01';
      expect(() => validateGolden(g), throwsFormatException);
      g = load('golden');
      g['cases'][0]['truth']['medicines'][0].remove('unit');
      expect(() => validateGolden(g), throwsFormatException);
      g = load('golden');
      g['cases'][0]['unknownPaths'] = [];
      expect(() => validateGolden(g), throwsFormatException);
      g = load('golden');
      g['cases'][0]['unexpected'] = true;
      expect(() => validateGolden(g), throwsFormatException);
      expect(() => validateGolden([]), throwsFormatException);
    },
  );
  test(
    'duplicate/invalid prediction IDs, wrong raw type fail instead of overwriting',
    () {
      final p = load('oracle');
      p['predictions'].add(p['predictions'][0]);
      expect(() => predictionIndex(p), throwsFormatException);
      p['predictions'].removeLast();
      p['predictions'][0]['raw'] = {};
      expect(() => predictionIndex(p), throwsFormatException);
      expect(() => predictionIndex(null), throwsFormatException);
    },
  );
  test(
    'missing and extra case IDs never silently change denominators',
    () async {
      final p = load('oracle');
      p['predictions'].removeAt(0);
      p['predictions'].add({'caseId': 'EXTRA', 'raw': '{}'});
      final result = await evaluateOffline(load('golden'), p);
      expect(result['completeCaseSet'], false);
      expect(result['casesDenominator'], 16);
      expect(result['missingCases'], ['S01']);
      expect(result['extraCases'], ['EXTRA']);
      expect(result['jsonParseableCount'], 15);
    },
  );
  for (final mutation in [
    'envelope',
    'refusal',
    'length',
    'json',
    'empty',
    'date',
    'numeric',
    'negative',
    'fractional',
    'name',
  ]) {
    test('real transport/parser rejects $mutation', () async {
      final p = load('oracle');
      final first = p['predictions'][0];
      final raw = jsonDecode(first['raw']);
      switch (mutation) {
        case 'envelope':
          first['envelope'] = {'choices': []};
        case 'refusal':
          first['envelope'] = {
            'choices': [
              {
                'message': {'refusal': 'synthetic refusal'},
              },
            ],
          };
        case 'length':
          first['envelope'] = {
            'choices': [
              {
                'finish_reason': 'length',
                'message': {'content': first['raw']},
              },
            ],
          };
        case 'json':
          first['raw'] = '```json\nnot json\n```';
        case 'empty':
          raw['medicines'] = [];
        case 'date':
          raw['hospitalInfo']['prescriptionDate'] = '2026-02-30';
        case 'numeric':
          raw['medicines'][0]['totalQuantity'] = '2';
        case 'negative':
          raw['medicines'][0]['durationDays'] = -1;
        case 'fractional':
          raw['medicines'][0]['durationDays'] = 1.5;
        case 'name':
          raw['medicines'][0]['name'] = null;
          raw['medicines'][0]['englishName'] = null;
      }
      if (!['envelope', 'refusal', 'length', 'json'].contains(mutation)) {
        first['raw'] = jsonEncode(raw);
      }
      final result = await evaluateOffline(load('golden'), p);
      expect(result['reports'][0]['serviceAccepted'], false);
    });
  }
  test(
    'schema/parser divergence remains visible: missing nullable and extra keys accepted',
    () async {
      final p = load('oracle');
      final raw = jsonDecode(p['predictions'][0]['raw']);
      raw['medicines'][0].remove('unit');
      raw['medicines'][0]['syntheticUnexpected'] = 'extra';
      raw['hospitalInfo'].remove('doctorName');
      p['predictions'][0]['raw'] = jsonEncode(raw);
      final result = await evaluateOffline(load('golden'), p);
      final first = result['reports'][0];
      expect(first['serviceAccepted'], true);
      expect(
        first['schemaIssues'],
        contains(r'$.medicines[0].unit:missing_key'),
      );
      expect(
        first['schemaIssues'],
        contains(r'$.medicines[0].syntheticUnexpected:extra_key'),
      );
      expect(first['mapperAccepted'], false);
    },
  );
  test(
    'fenced JSON accepted by production is not raw JSON parseable',
    () async {
      final p = load('oracle');
      p['predictions'][0]['raw'] =
          '```json\n${p['predictions'][0]['raw']}\n```';
      final result = await evaluateOffline(load('golden'), p);
      expect(result['reports'][0]['jsonParseable'], false);
      expect(result['reports'][0]['serviceAccepted'], true);
      expect(result['reports'][0]['postNormalization']['exactFields'], true);
      expect(result['reports'][0]['wholeExactRaw'], false);
    },
  );
  test(
    'null and wrong-root JSON are parseable but rejected by production',
    () async {
      for (final value in ['null', '[]', 'false', '""']) {
        final p = load('oracle');
        p['predictions'][0]['raw'] = value;
        final result = await evaluateOffline(load('golden'), p);
        expect(result['reports'][0]['jsonParseable'], true);
        expect(result['reports'][0]['serviceAccepted'], false);
        expect(result['reports'][0]['raw']['missingRows'], 1);
      }
    },
  );
  test(
    'non-null error and zero confidence are different acceptance criteria',
    () async {
      final p = load('oracle');
      final raw = jsonDecode(p['predictions'][1]['raw']);
      raw['confidence'] = 0;
      p['predictions'][1]['raw'] = jsonEncode(raw);
      var result = await evaluateOffline(load('golden'), p);
      expect(result['reports'][1]['serviceAccepted'], true);
      for (final m in result['reports'][1]['modelConversion']) {
        expect(m['confidence'], 0);
      }
      raw['error'] = 'SYNTH error';
      p['predictions'][1]['raw'] = jsonEncode(raw);
      result = await evaluateOffline(load('golden'), p);
      expect(result['reports'][1]['serviceAccepted'], false);
    },
  );
  test(
    'model zero defaults do not become raw evidence or measured confidence',
    () async {
      final result = await evaluateOffline(load('golden'), load('oracle'));
      final reports = result['reports'] as List;
      expect(reports[8]['modelConversion'][0]['durationDays'], 0);
      expect(reports[9]['modelConversion'][0]['totalQuantity'], 0);
      expect(reports[8]['mapperAccepted'], true);
      expect(reports[9]['mapperAccepted'], true);
      for (final i in [3, 4, 5, 6, 7, 10]) {
        expect(reports[i]['mapperAccepted'], false);
      }
      expect(
        reports[8]['raw']['details'],
        contains(
          equals({
            'path': 'medicines.0.durationDays',
            'category': 'correct',
            'truthUnknown': true,
          }),
        ),
      );
    },
  );
}
