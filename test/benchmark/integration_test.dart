import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:health_management_app/screens/ai_benchmark_screen.dart';
import 'package:health_management_app/services/ai/benchmark/frozen_images.dart';
import 'package:health_management_app/services/ai/benchmark/runtime.dart';
import 'package:health_management_app/services/ai/benchmark/single_attempt.dart';

void main() {
  test(
    'all 16 bundled image bytes and hashes match reviewed manifest',
    () async {
      final manifest =
          jsonDecode(
                await File(
                  'test/fixtures/prescription_images/manifest.json',
                ).readAsString(),
              )
              as Map;
      expect(frozenImages.length, 16);
      for (final row in manifest['cases']) {
        final image = frozenImages[row['caseId']]!;
        final bytes = base64Decode(image.base64);
        expect(sha256.convert(bytes).toString(), row['sha256']);
        expect(
          bytes,
          await File(
            'test/fixtures/prescription_images/${row['image']}',
          ).readAsBytes(),
        );
        final body = benchmarkBody(row['caseId']);
        expect(body['max_tokens'], 4096);
        expect(body['response_format']['type'], 'json_schema');
        expect(
          body['messages'][0]['content'][1]['image_url']['detail'],
          'high',
        );
      }
      expect(benchmarkPlan.skip(16), ['S03', 'S11', 'S12', 'S16']);
    },
  );
  test('single HTTP transport disables redirects and implicit retry', () async {
    var calls = 0;
    final transport = GatewayBenchmarkTransport(
      Uri.parse(benchmarkEndpoint),
      factory: () => MockClient((request) async {
        calls++;
        expect(request.followRedirects, false);
        expect(request.maxRedirects, 0);
        expect(request.headers['Authorization'], 'Bearer fake-test-token');
        return http.Response('{}', 429);
      }),
    );
    final result = await transport.send(
      benchmarkBody('S01'),
      'fake-test-token',
    );
    expect(result.status, 429);
    expect(calls, 1);
  });
  testWidgets('default disabled debug page builds without auth/network', (
    tester,
  ) async {
    expect(benchmarkEnabled, false);
    await tester.pumpWidget(const MaterialApp(home: AIBenchmarkScreen()));
    expect(find.text('離線準備入口未啟用'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  test('runtime rejects default-off without reading Firebase session', () {
    expect(
      () => BenchmarkRuntime.create(costReady: () => true),
      throwsStateError,
    );
  });
}
