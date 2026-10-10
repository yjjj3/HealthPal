import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_management_app/widgets/account_boundary.dart';

void main() {
  testWidgets(
    'account change disposes old routes; same account preserves state',
    (tester) async {
      final ids = StreamController<String?>.broadcast();
      var created = 0;
      var disposed = 0;
      await tester.pumpWidget(
        AccountBoundary(
          userIds: ids.stream,
          initialUid: 'alice',
          child: MaterialApp(
            home: _Probe(
              onCreate: () => created++,
              onDispose: () => disposed++,
            ),
          ),
        ),
      );
      expect(created, 1);
      ids.add('alice');
      await tester.pump();
      expect(created, 1);
      final context = tester.element(find.byType(_Probe));
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('old account route')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('old account route'), findsOneWidget);
      ids.add('bob');
      await tester.pumpAndSettle();
      expect(find.text('old account route'), findsNothing);
      expect(created, 2);
      expect(disposed, 1);
      ids.add(null);
      await tester.pumpAndSettle();
      expect(created, 3);
      expect(disposed, 2);
      await tester.pumpWidget(const SizedBox());
      await ids.close();
    },
  );
}

class _Probe extends StatefulWidget {
  const _Probe({required this.onCreate, required this.onDispose});
  final VoidCallback onCreate;
  final VoidCallback onDispose;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.onCreate();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('home'));
}
