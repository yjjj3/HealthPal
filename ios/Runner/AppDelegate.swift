import Flutter
import UIKit
import UserNotifications
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var methodChannel: FlutterMethodChannel?
    private var securityOverlay: UIView?
    private var isProtectionEnabled = true

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 註冊本地通知
        if #available(iOS 10.0, *) {
            UNUserNotificationCenter.current().delegate = self
        }

        // 設定截圖保護 MethodChannel
        if let controller = window?.rootViewController as? FlutterViewController {
            methodChannel = FlutterMethodChannel(
                name: "com.example.health_management_app/screenshot_protection",
                binaryMessenger: controller.binaryMessenger
            )

            methodChannel?.setMethodCallHandler { [weak self] (call, result) in
                guard let self = self else { return }

                switch call.method {
                case "setProtectionEnabled":
                    if let args = call.arguments as? [String: Any],
                       let enabled = args["enabled"] as? Bool {
                        self.isProtectionEnabled = enabled
                        result(nil)
                    } else {
                        result(FlutterError(code: "INVALID_ARGUMENT", message: "Missing 'enabled' argument", details: nil))
                    }
                default:
                    result(FlutterMethodNotImplemented)
                }
            }
        }

        // 監聽截圖事件
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(userDidTakeScreenshot),
            name: UIApplication.userDidTakeScreenshotNotification,
            object: nil
        )

        // 監聽螢幕錄影事件
        if #available(iOS 11.0, *) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(screenCaptureDidChange),
                name: UIScreen.capturedDidChangeNotification,
                object: nil
            )
        }

        // 監聯應用程式生命週期（用於在多工介面隱藏內容）
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    @objc private func userDidTakeScreenshot() {
        if isProtectionEnabled {
            // 通知 Flutter 偵測到截圖
            methodChannel?.invokeMethod("onScreenshotDetected", arguments: nil)
        }
    }

    @available(iOS 11.0, *)
    @objc private func screenCaptureDidChange() {
        if UIScreen.main.isCaptured && isProtectionEnabled {
            // 螢幕正在被錄影，顯示保護畫面
            showSecurityOverlay()
        } else {
            hideSecurityOverlay()
        }
    }

    @objc private func handleAppWillResignActive() {
        // 當應用程式即將進入背景時，顯示保護畫面（隱藏多工介面中的敏感資料）
        if isProtectionEnabled {
            showSecurityOverlay()
        }
    }

    @objc private func handleAppDidBecomeActive() {
        // 當應用程式變為活躍時，移除保護畫面
        hideSecurityOverlay()
    }

    private func showSecurityOverlay() {
        guard securityOverlay == nil else { return }

        let overlay = UIView(frame: window?.bounds ?? UIScreen.main.bounds)
        overlay.backgroundColor = UIColor.systemBackground
        overlay.tag = 999

        // 添加 App 圖標和提示文字
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let iconImageView = UIImageView(image: UIImage(named: "AppIcon"))
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.widthAnchor.constraint(equalToConstant: 80).isActive = true
        iconImageView.heightAnchor.constraint(equalToConstant: 80).isActive = true
        iconImageView.layer.cornerRadius = 16
        iconImageView.clipsToBounds = true

        let label = UILabel()
        label.text = "健康資料受到保護"
        label.textColor = .secondaryLabel
        label.font = UIFont.systemFont(ofSize: 16, weight: .medium)

        stackView.addArrangedSubview(iconImageView)
        stackView.addArrangedSubview(label)

        overlay.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: overlay.centerYAnchor)
        ])

        window?.addSubview(overlay)
        securityOverlay = overlay
    }

    private func hideSecurityOverlay() {
        securityOverlay?.removeFromSuperview()
        securityOverlay = nil
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
