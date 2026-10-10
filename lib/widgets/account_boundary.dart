import 'dart:async';
import 'package:flutter/material.dart';

/// Wrap MaterialApp so its navigator keys and all old-account pages are reset.
class AccountBoundary extends StatefulWidget {
  const AccountBoundary({
    super.key,
    required this.userIds,
    required this.child,
    this.initialUid,
  });
  final Stream<String?> userIds;
  final String? initialUid;
  final Widget child;
  @override
  State<AccountBoundary> createState() => _AccountBoundaryState();
}

class _AccountBoundaryState extends State<AccountBoundary> {
  StreamSubscription<String?>? _subscription;
  String? _uid;
  @override
  void initState() {
    super.initState();
    _uid = widget.initialUid;
    _subscription = widget.userIds.distinct().listen((uid) {
      if (mounted && uid != _uid) setState(() => _uid = uid);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: ValueKey(_uid), child: widget.child);
}
