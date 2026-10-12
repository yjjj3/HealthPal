import 'dart:convert';
import 'package:health_management_app/models/ai/prescription_recognition.dart';

const medicineFields = [
  ...PrescriptionRecognition.textFields,
  'durationDays',
  'totalQuantity',
];
const hospitalFields = PrescriptionRecognition.hospitalFields;

/// Diagnostics against the requested production schema, not a replacement
/// parser. Acceptance/normalization is always exercised by the real service.
List<String> schemaIssues(
  dynamic value,
  Map<String, dynamic> schema, [
  String path = r'$',
]) {
  final issues = <String>[];
  final types = schema['type'] is List
      ? schema['type'] as List
      : [schema['type']];
  final type = value == null
      ? 'null'
      : value is Map
      ? 'object'
      : value is List
      ? 'array'
      : value is String
      ? 'string'
      : value is bool
      ? 'boolean'
      : value is int ||
            (value is double &&
                value.isFinite &&
                value == value.truncateToDouble())
      ? 'integer'
      : value is num && value.isFinite
      ? 'number'
      : 'invalid';
  if (!types.contains(type) &&
      !(type == 'integer' && types.contains('number'))) {
    return ['$path:type'];
  }
  if (value is Map) {
    final properties = schema['properties'] as Map<String, dynamic>;
    for (final key in schema['required'] as List) {
      if (!value.containsKey(key)) issues.add('$path.$key:missing_key');
    }
    for (final key in value.keys) {
      if (!properties.containsKey(key)) {
        if (schema['additionalProperties'] == false) {
          issues.add('$path.$key:extra_key');
        }
      } else {
        issues.addAll(
          schemaIssues(
            value[key],
            properties[key] as Map<String, dynamic>,
            '$path.$key',
          ),
        );
      }
    }
  }
  if (value is List) {
    for (var i = 0; i < value.length; i++) {
      issues.addAll(
        schemaIssues(
          value[i],
          schema['items'] as Map<String, dynamic>,
          '$path[$i]',
        ),
      );
    }
  }
  return issues;
}

Map<String, dynamic> object(dynamic value, String label) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$label must be object');
  }
  return value;
}

List<Map<String, dynamic>> validateGolden(dynamic input) {
  final root = object(input, 'golden');
  if (root['version'] != 1 ||
      root['disclaimer'] is! String ||
      root['cases'] is! List) {
    throw const FormatException('invalid golden header');
  }
  if (root.keys.any((k) => !['version', 'disclaimer', 'cases'].contains(k))) {
    throw const FormatException('unknown golden metadata');
  }
  final cases = <Map<String, dynamic>>[];
  final ids = <String>{};
  for (final item in root['cases']) {
    final c = object(item, 'case');
    if (c['caseId'] is! String ||
        !RegExp(r'^S[0-9]{2}$').hasMatch(c['caseId']) ||
        !ids.add(c['caseId']) ||
        c['synthetic'] != true ||
        c['sourceText'] is! String ||
        c['scenario'] is! String) {
      throw const FormatException('invalid/duplicate golden case');
    }
    if (c.keys.any(
      (k) => ![
        'caseId',
        'scenario',
        'synthetic',
        'sourceText',
        'truth',
        'unknownPaths',
        'normalization',
        'humanConfirmation',
      ].contains(k),
    )) {
      throw const FormatException('unknown case metadata');
    }
    final truth = object(c['truth'], 'truth');
    final schema =
        PrescriptionRecognition.responseFormat['json_schema']['schema']
            as Map<String, dynamic>;
    if (schemaIssues(truth, schema).isNotEmpty ||
        (truth['medicines'] as List).isEmpty ||
        (truth['medicines'] as List).length > 5 ||
        truth['error'] != null) {
      throw const FormatException('golden truth violates contract');
    }
    // Production parser must also accept truth; expected name remains RAW.
    PrescriptionRecognition.parse(jsonEncode(truth));
    final actualUnknown = <String>[];
    for (var i = 0; i < truth['medicines'].length; i++) {
      for (final key in medicineFields) {
        if (truth['medicines'][i][key] == null) {
          actualUnknown.add('medicines.$i.$key');
        }
      }
    }
    for (final key in hospitalFields) {
      if (truth['hospitalInfo'][key] == null) {
        actualUnknown.add('hospitalInfo.$key');
      }
    }
    if (c['unknownPaths'] is! List ||
        jsonEncode(c['unknownPaths']) != jsonEncode(actualUnknown)) {
      throw const FormatException(
        'unknownPaths must exactly enumerate null truth',
      );
    }
    final normalization = object(c['normalization'], 'normalization');
    for (final entry in normalization.entries) {
      if (!['name', 'englishName'].contains(entry.key) ||
          entry.value is! List ||
          (entry.value as List).any((v) => !['trim', 'casefold'].contains(v))) {
        throw const FormatException('warnings/numbers cannot be normalized');
      }
    }
    final confirmation = object(c['humanConfirmation'], 'humanConfirmation');
    if (confirmation['required'] != true ||
        confirmation['reasons'] is! List ||
        (confirmation['reasons'] as List).isEmpty) {
      throw const FormatException('human confirmation required');
    }
    cases.add(c);
  }
  if (cases.length < 12 || cases.length > 20) {
    throw const FormatException('golden needs 12–20 cases');
  }
  return cases;
}

dynamic normalize(dynamic value, String key, Map<String, dynamic> rules) {
  if (value is! String) return value;
  var text = value;
  for (final rule in rules[key] as List? ?? []) {
    if (rule == 'trim') text = text.trim();
    if (rule == 'casefold') text = text.toLowerCase();
  }
  return text;
}

String classification(
  Map row,
  String key,
  dynamic expected,
  Map<String, dynamic> rules,
) {
  if (!row.containsKey(key)) return 'missing';
  final value = row[key];
  if (expected == null) return value == null ? 'correct' : 'hallucinated';
  if (value == null || (value is String && value.trim().isEmpty)) {
    return 'missing';
  }
  return normalize(value, key, rules) == normalize(expected, key, rules)
      ? 'correct'
      : 'incorrect';
}

String identity(Map row, Map<String, dynamic> rules) {
  final key =
      row['englishName'] is String &&
          (row['englishName'] as String).trim().isNotEmpty
      ? 'englishName'
      : 'name';
  final value = row[key];
  return value is String ? normalize(value, key, rules).toString() : '';
}

Map<String, dynamic> scoreFields(Map<String, dynamic> c, dynamic prediction) {
  final truth = c['truth'] as Map<String, dynamic>;
  final rules = c['normalization'] as Map<String, dynamic>;
  final expected = (truth['medicines'] as List).cast<Map<String, dynamic>>();
  final data = prediction is Map ? prediction : <String, dynamic>{};
  final rawRows = data['medicines'] is List ? data['medicines'] as List : [];
  final rows = [for (final r in rawRows) r is Map ? r : <String, dynamic>{}];
  // Exact minimum-cost one-to-one matching within synthetic name identity.
  // Distinct rows with the same name are matched by fields, not order. Duplicates
  // consume one row each; unmatched rows are never silently discarded.
  List<int>? best;
  var bestCost = 1 << 30;
  void search(int index, List<int> assignment, Set<int> used, int cost) {
    if (cost >= bestCost) return;
    if (index == expected.length) {
      final total = cost + (rows.length - used.length) * medicineFields.length;
      if (total < bestCost) {
        bestCost = total;
        best = List.of(assignment);
      }
      return;
    }
    search(index + 1, [...assignment, -1], used, cost + medicineFields.length);
    for (var j = 0; j < rows.length; j++) {
      if (used.contains(j) ||
          identity(expected[index], rules) != identity(rows[j], rules)) {
        continue;
      }
      final mismatch = medicineFields
          .where(
            (k) =>
                classification(rows[j], k, expected[index][k], rules) !=
                'correct',
          )
          .length;
      search(index + 1, [...assignment, j], {...used, j}, cost + mismatch);
    }
  }

  // Bounded CLI: reject oversized prediction rows, rather than truncate them.
  if (rows.length > 20) {
    throw const FormatException('prediction exceeds 20-row offline bound');
  }
  search(0, [], {}, 0);
  final matches = best!;
  final details = <Map<String, dynamic>>[];
  final counts = {
    'correct': 0,
    'incorrect': 0,
    'missing': 0,
    'hallucinated': 0,
  };
  var known = 0, unknown = 0;
  void field(String path, String key, dynamic value, Map row) {
    if (value == null) {
      unknown++;
    } else {
      known++;
    }
    final category = classification(row, key, value, rules);
    counts[category] = counts[category]! + 1;
    details.add({
      'path': path,
      'category': category,
      'truthUnknown': value == null,
    });
  }

  for (var i = 0; i < expected.length; i++) {
    for (final key in medicineFields) {
      field(
        'medicines.$i.$key',
        key,
        expected[i][key],
        matches[i] == -1 ? {} : rows[matches[i]],
      );
    }
  }
  final hospital = data['hospitalInfo'] is Map
      ? data['hospitalInfo'] as Map
      : {};
  for (final key in hospitalFields) {
    field('hospitalInfo.$key', key, truth['hospitalInfo'][key], hospital);
  }
  final used = matches.where((i) => i >= 0).toSet();
  final extraRows = rows.length - used.length;
  for (var j = 0; j < rows.length; j++) {
    if (used.contains(j)) continue;
    // Extra entity is hallucinated even when its supplied fields are null.
    for (final key in medicineFields) {
      counts['hallucinated'] = counts['hallucinated']! + 1;
      details.add({
        'path': 'extraMedicine.$j.$key',
        'category': 'hallucinated',
        'truthUnknown': false,
      });
    }
  }
  return {
    'counts': counts,
    'expectedFieldDenominator': known + unknown,
    'knownDenominator': known,
    'unknownDenominator': unknown,
    'extraFieldPenalty': extraRows * medicineFields.length,
    'missingRows': matches.where((i) => i == -1).length,
    'extraRows': extraRows,
    'exactFields':
        counts['incorrect'] == 0 &&
        counts['missing'] == 0 &&
        counts['hallucinated'] == 0,
    'details': details,
  };
}

Map<String, dynamic> predictionIndex(dynamic input) {
  final root = object(input, 'predictions');
  if (root['origin'] is! String || root['predictions'] is! List) {
    throw const FormatException('prediction header');
  }
  final indexed = <String, dynamic>{};
  for (final p in root['predictions']) {
    final record = object(p, 'prediction record');
    if (record['caseId'] is! String ||
        indexed.containsKey(record['caseId']) ||
        record['raw'] is! String) {
      throw const FormatException('duplicate/invalid prediction case');
    }
    indexed[record['caseId']] = record;
  }
  return indexed;
}
