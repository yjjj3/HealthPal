import 'dart:async';
import 'package:flutter/foundation.dart';

/// A page belongs to one login session. Switching away and back does not revive
/// pending work or a draft from the earlier session.
class AccountPageSession extends ChangeNotifier {
  AccountPageSession(this.currentUid, Stream<String?> changes)
    : ownerUid = currentUid() {
    _subscription = changes.listen((uid) {
      if (_valid && uid != ownerUid) {
        _valid = false;
        notifyListeners();
      }
    });
  }
  final String? Function() currentUid;
  final String? ownerUid;
  bool _valid = true;
  late final StreamSubscription<String?> _subscription;
  bool get active => _valid && ownerUid != null && currentUid() == ownerUid;
  @override
  void dispose() {
    _valid = false;
    _subscription.cancel();
    super.dispose();
  }
}
