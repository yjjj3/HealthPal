/// Coalesces concurrent initialization and permits retry after failure.
class InitializationGate {
  Future<void>? _pending;
  bool _ready = false;
  Future<void> run(Future<void> Function() initialize) {
    if (_ready) return Future.value();
    return _pending ??= Future<void>.sync(initialize)
        .then((_) {
          _ready = true;
        })
        .whenComplete(() {
          _pending = null;
        });
  }
}
