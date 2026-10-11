import 'package:flutter/material.dart';
import '../services/app_unlock_controller.dart';

/// Child navigation is not mounted until authorized: no offstage sensitive tree.
class AppUnlockGate extends StatelessWidget {
  const AppUnlockGate({
    super.key,
    required this.controller,
    required this.protectedNavigation,
    required this.loginBuilder,
  });
  final AppUnlockController controller;
  final Widget protectedNavigation;
  final WidgetBuilder loginBuilder;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (controller.permitsProtected) {
        return KeyedSubtree(
          key: ValueKey((
            controller.session.currentUid(),
            controller.session.generation,
          )),
          child: protectedNavigation,
        );
      }
      if (controller.permitsLogin) {
        // A separate public navigator ignores protected initial/deep/restored routes.
        return Navigator(
          onGenerateRoute: (_) => MaterialPageRoute<void>(
            builder: loginBuilder,
            settings: const RouteSettings(name: '/login'),
          ),
        );
      }
      return PopScope(
        canPop: false,
        child: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 48),
                    const SizedBox(height: 16),
                    const Text('App 已鎖定', style: TextStyle(fontSize: 24)),
                    const SizedBox(height: 12),
                    Text(controller.message ?? '請驗證以存取資料。'),
                    const SizedBox(height: 16),
                    if (controller.access == AppAccess.checking ||
                        controller.busy)
                      const CircularProgressIndicator()
                    else ...[
                      ElevatedButton(
                        onPressed: () {
                          if (controller.access == AppAccess.failed) {
                            controller.reload();
                          } else {
                            controller.unlock();
                          }
                        },
                        child: Text(
                          controller.access == AppAccess.failed
                              ? '重試讀取設定'
                              : '使用 Face ID／生物辨識解鎖',
                        ),
                      ),
                      TextButton(
                        onPressed: () => controller.loginAgain(),
                        child: const Text('使用 Email／Google 重新登入'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class AppUnlockLifecycle extends StatefulWidget {
  const AppUnlockLifecycle({
    super.key,
    required this.controller,
    required this.child,
  });
  final AppUnlockController controller;
  final Widget child;
  @override
  State<AppUnlockLifecycle> createState() => _AppUnlockLifecycleState();
}

class _AppUnlockLifecycleState extends State<AppUnlockLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      widget.controller.lifecycle(state);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
