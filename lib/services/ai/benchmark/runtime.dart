import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../../models/ai/prescription_recognition.dart';
import '../../ai_service.dart';
import '../../app_unlock_runtime.dart';
import '../../auth_service.dart';
import '../../prescription_scan_service.dart';
import '../ai_config.dart';
import 'frozen_images.dart';
import 'journal.dart';
import 'single_attempt.dart';

const benchmarkEnabled =
    kDebugMode && bool.fromEnvironment('ENABLE_AI_BENCHMARK');
const benchmarkEndpoint =
    'https://asia-east1-health-management-f046a.cloudfunctions.net/healthAI';
const benchmarkPlan = BenchmarkJournal.samples;

/// Builds only frozen synthetic requests, never arbitrary photo/patient input.
Map<String, dynamic> benchmarkBody(String sample) {
  final image = frozenImages[sample];
  if (image == null) throw StateError('Unknown synthetic sample');
  final bytes = base64Decode(image.base64);
  if (sha256.convert(bytes).toString() != image.sha256) {
    throw StateError('Frozen image hash mismatch');
  }
  return {
    'model': 'gpt-4o',
    'max_tokens': 4096,
    'temperature': 0.1,
    'messages': [
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': PrescriptionScanService.benchmarkPrompt},
          validatedImage(bytes, detail: 'high'),
        ],
      },
    ],
    'response_format': PrescriptionRecognition.responseFormat,
  };
}

class BenchmarkRuntime extends BenchmarkHandle {
  BenchmarkRuntime._(super.runner, super.ownerHash);
  static BenchmarkRuntime create({required bool Function() costReady}) {
    if (!benchmarkEnabled ||
        !Platform.isIOS ||
        AIConfig.gateway != benchmarkEndpoint) {
      throw StateError('Benchmark disabled or endpoint unsupported');
    }
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('Local journal unavailable');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('Normal App login required');
    }
    final journal = BenchmarkJournal(
      File(
        '$home/Library/Application Support/HealthPalBenchmark/${BenchmarkJournal.experiment}.json',
      ),
    );
    BenchmarkSession? session() {
      final current = FirebaseAuth.instance.currentUser;
      final auth = AuthService.logout;
      if (current == null ||
          current.isAnonymous ||
          !auth.isCurrent(auth.generation)) {
        return null;
      }
      return BenchmarkSession(current.uid, auth.generation);
    }

    return BenchmarkRuntime._(
      SingleAttemptBenchmark(
        journal: journal,
        transport: GatewayBenchmarkTransport(Uri.parse(benchmarkEndpoint)),
        session: session,
        token: () async {
          final captured = FirebaseAuth.instance.currentUser;
          final epoch = AuthService.logout.generation;
          if (captured == null || captured.isAnonymous) {
            throw StateError('Login required');
          }
          final token = await captured.getIdToken(); // Memory/header only.
          if (FirebaseAuth.instance.currentUser?.uid != captured.uid ||
              !AuthService.logout.isCurrent(epoch) ||
              token == null) {
            throw StateError('Session changed');
          }
          return token;
        },
        canAccess: () =>
            benchmarkEnabled &&
            AppUnlockRuntime.instance.controller.permitsProtected,
        costReady: costReady,
        nowMs: () => DateTime.now().millisecondsSinceEpoch,
        validateRequest: (sample, body) =>
            jsonEncode(body) == jsonEncode(benchmarkBody(sample)),
      ),
      sha256.convert(utf8.encode(user.uid)).toString(),
    );
  }
}
