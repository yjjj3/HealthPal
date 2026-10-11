import 'package:flutter/material.dart';
import '../services/app_unlock_controller.dart';

class AppUnlockSettings extends StatelessWidget {
  const AppUnlockSettings({super.key, required this.controller});
  final AppUnlockController controller;
  Future<void> _change(BuildContext context, bool value) async {
    final uid = controller.session.currentUid();
    final epoch = controller.session.generation;
    final success = await controller.setEnabled(
      value,
      confirm: () async {
        if (!context.mounted) return false;
        return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('啟用 App 解鎖？'),
                content: const Text(
                  '此帳號在本裝置冷啟動或離開 App 滿 1 分鐘後，需 Face ID／生物辨識解鎖。'
                  '\n不儲存密碼，不使用 App PIN；驗證失敗可重試，或登出後用 Email／Google 重新登入。'
                  '\n原有閒置自動登出仍生效。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('確認啟用'),
                  ),
                ],
              ),
            ) ??
            false;
      },
    );
    if (!context.mounted ||
        uid != controller.session.currentUid() ||
        epoch != controller.session.generation) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (value ? 'App 解鎖已啟用' : 'App 解鎖已關閉')
              : controller.message ?? '未變更 App 解鎖設定。',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => SwitchListTile(
      secondary: const Icon(Icons.face),
      title: const Text('App 解鎖（Face ID／生物辨識）'),
      subtitle: Text(
        controller.enabled == true ? '此帳號已啟用；離開滿 1 分鐘需解鎖' : '預設關閉；不儲存登入密碼',
      ),
      value: controller.enabled == true,
      onChanged: controller.busy || !controller.permitsProtected
          ? null
          : (value) => _change(context, value),
    ),
  );
}
