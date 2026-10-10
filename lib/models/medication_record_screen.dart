// lib/models/medication_record.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class MedicationRecord {
  final String? id;
  final String medicationName;
  final String dosage;
  final String frequency;
  final DateTime medicationTime;
  final DateTime createdAt;

  MedicationRecord({
    this.id,
    required this.medicationName,
    required this.dosage,
    required this.frequency,
    required this.medicationTime,
    required this.createdAt,
  });

  // 從 Firestore 轉換為 MedicationRecord
  factory MedicationRecord.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MedicationRecord(
      id: doc.id,
      medicationName: data['medication_name'] ?? '',
      dosage: data['dosage'] ?? '',
      frequency: data['frequency'] ?? '',
      medicationTime: (data['medication_time'] as Timestamp).toDate(),
      createdAt: (data['created_at'] as Timestamp).toDate(),
    );
  }

  // 轉換為 Firestore 格式
  Map<String, dynamic> toFirestore() {
    return {
      'medication_name': medicationName,
      'dosage': dosage,
      'frequency': frequency,
      'medication_time': Timestamp.fromDate(medicationTime),
      'created_at': Timestamp.fromDate(createdAt),
    };
  }
}