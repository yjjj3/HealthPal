// Local cross-process lock test worker; no network or credentials.
import 'dart:io';
import 'package:health_management_app/services/ai/benchmark/journal.dart';

Future<void> main(List<String> args) async {
  try {
    await BenchmarkJournal(File(args[0])).reserve('race', 'S01', 0);
    exitCode = 0;
  } catch (_) {
    exitCode = 2;
  }
}
