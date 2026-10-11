import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/medication_model.dart';

const regimenFields = [
  'frequency',
  'times_of_day_list',
  'start_date',
  'duration_days',
];
Map<String, dynamic> regimenVersion(Map<String, dynamic> data, DateTime at) => {
  'effective_from': Timestamp.fromDate(at),
  for (final key in regimenFields) key: data[key],
};
Map<String, dynamic> medicationCreationData(medicine med, DateTime at) {
  final data = med.toFirestore();
  return {
    ...data,
    'regimen_history': [regimenVersion(data, at)],
  };
}

/// Keep at most 32 versions in the existing document. The oldest retained
/// effective_from is the coverage boundary; earlier dates remain unknown.
List<Map<String, dynamic>> appendRegimenHistory(
  Map<String, dynamic> live,
  Map<String, dynamic> next,
  DateTime at,
) {
  final history = (live['regimen_history'] as List? ?? [])
      .map((v) => Map<String, dynamic>.from(v as Map))
      .toList();
  history.add(regimenVersion(next, at));
  return history.length > 32 ? history.sublist(history.length - 32) : history;
}
