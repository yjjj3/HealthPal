import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Expands only on request; the whole loaded window remains live, including deletes.
/// Unlike fixed cursor pages, moving page boundaries cannot skip documents.
class LiveQueryWindow {
  LiveQueryWindow(this.query, {this.pageSize = 50, this.onChanged}) {
    _limit = pageSize;
    _controller =
        StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast(
          onListen: () {
            if (!_started) {
              _started = true;
              refresh();
            }
          },
        );
    stream = Stream<QuerySnapshot<Map<String, dynamic>>>.multi((listener) {
      if (_disposed) {
        listener.close();
        return;
      }
      if (_lastError != null) {
        listener.addError(_lastError!, _lastStack);
      } else if (_latest != null) {
        listener.add(_latest!);
      }
      final subscription = _controller.stream.listen(
        listener.add,
        onError: listener.addError,
        onDone: listener.close,
      );
      listener.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }
  final Query<Map<String, dynamic>> query;
  final int pageSize;
  final void Function()? onChanged;
  late final StreamController<QuerySnapshot<Map<String, dynamic>>> _controller;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  late int _limit;
  int _generation = 0;
  bool _started = false;
  bool _disposed = false;
  bool _loading = false;
  bool hasMore = true;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> stream;
  QuerySnapshot<Map<String, dynamic>>? _latest;
  Object? _lastError;
  StackTrace? _lastStack;

  Future<void> loadMore() async {
    if (_disposed || _loading || !hasMore) return;
    _limit += pageSize;
    await refresh();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    _loading = true;
    final old = _subscription;
    _subscription = null;
    await old?.cancel();
    if (_disposed || generation != _generation) return;
    _subscription = query
        .limit(_limit)
        .snapshots()
        .listen(
          (snapshot) {
            if (_disposed || generation != _generation) return;
            _loading = false;
            hasMore = snapshot.docs.length == _limit;
            _latest = snapshot;
            _lastError = null;
            _lastStack = null;
            _controller.add(snapshot);
            onChanged?.call();
          },
          onError: (Object error, StackTrace stack) {
            if (_disposed || generation != _generation) return;
            _loading = false;
            _lastError = error;
            _lastStack = stack;
            _controller.addError(error, stack);
            onChanged?.call();
          },
        );
  }

  Future<void> dispose() async {
    _disposed = true;
    _generation++;
    await _subscription?.cancel();
    await _controller.close();
  }
}
