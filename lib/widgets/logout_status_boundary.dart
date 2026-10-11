import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/logout_coordinator.dart';

/// Remains visible when auth-driven navigation disposes the initiating page.
class LogoutStatusBoundary extends StatelessWidget {
  const LogoutStatusBoundary({
    super.key,
    required this.child,
    this.coordinator,
  });
  final Widget child;
  final LogoutCoordinator? coordinator;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<LogoutPhase>(
    valueListenable: (coordinator ?? AuthService.logout).phase,
    builder: (context, phase, _) {
      final busy = phase == LogoutPhase.working;
      final failed =
          phase == LogoutPhase.authFailed || phase == LogoutPhase.cleanupFailed;
      return Column(
        children: [
          if (busy ||
              failed ||
              phase == LogoutPhase.signedOut ||
              phase == LogoutPhase.accountChanged)
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          busy
                              ? '正在登出並清除通知…'
                              : phase == LogoutPhase.authFailed
                              ? '登出失敗，帳號仍登入，請重試。'
                              : phase == LogoutPhase.cleanupFailed
                              ? '帳號已登出，但通知清理未完成，請重試清理。'
                              : phase == LogoutPhase.accountChanged
                              ? '帳號已變更，舊登出清理已停止；請核對通知。'
                              : '已登出，通知已清除。',
                        ),
                      ),
                      if (failed)
                        TextButton(
                          onPressed: () {
                            (coordinator ?? AuthService.logout).signOut();
                          },
                          child: const Text('重試'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          Expanded(
            child: AbsorbPointer(
              absorbing: busy || phase == LogoutPhase.cleanupFailed,
              child: child,
            ),
          ),
        ],
      );
    },
  );
}
