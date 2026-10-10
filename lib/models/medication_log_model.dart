// lib/models/medication_log_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class MedicationLog {
  final String? logId;
  final String medicineId; 
  final String medicineName; 
  final double dosageTaken; 
  final DateTime intakeTime; 
  final int timeSlotIndex; 
  final bool isTaken; 

  MedicationLog({
    this.logId,
    required this.medicineId,
    required this.medicineName,
    required this.dosageTaken,
    required this.intakeTime,
    required this.timeSlotIndex,
    this.isTaken = true, 
  });

  Map<String, dynamic> toFirestore() {
    return {
      'medicine_id': medicineId,
      'medicine_name': medicineName,
      'dosage_taken': dosageTaken,
      'intake_time': Timestamp.fromDate(intakeTime),
      'time_slot_index': timeSlotIndex,
      'is_taken': isTaken, 
    };
  }

  factory MedicationLog.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MedicationLog(
      logId: doc.id,
      medicineId: data['medicine_id'] as String? ?? '',
      medicineName: data['medicine_name'] as String? ?? '未知藥物',
      dosageTaken: (data['dosage_taken'] as num?)?.toDouble() ?? 0.0,
      intakeTime: (data['intake_time'] as Timestamp?)?.toDate() ?? DateTime.now(),
      timeSlotIndex: (data['time_slot_index'] as num?)?.toInt() ?? 0,
      isTaken: data['is_taken'] as bool? ?? true, 
    );
  }
}