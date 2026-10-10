package com.example.health_management_app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// 使用 FlutterFragmentActivity 以支援 local_auth 生物辨識認證
class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.example.health_management_app/screenshot_protection"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setProtectionEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    setScreenshotProtection(enabled)
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 預設啟用截圖保護
        setScreenshotProtection(true)
    }

    private fun setScreenshotProtection(enabled: Boolean) {
        if (enabled) {
            // 防止截圖和螢幕錄影
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        } else {
            // 移除保護
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
