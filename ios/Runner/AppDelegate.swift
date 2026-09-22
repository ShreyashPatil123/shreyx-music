import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var vibeBackgroundTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "com.shreyx.player/native_stream",
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        guard let self = self else {
          result(FlutterMethodNotImplemented)
          return
        }

        switch call.method {
        case "acquireVibeWakeLock":
          if self.vibeBackgroundTask == .invalid {
            self.vibeBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ShreyXVibe") {
              if self.vibeBackgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(self.vibeBackgroundTask)
                self.vibeBackgroundTask = .invalid
              }
            }
          }
          result(true)

        case "releaseVibeWakeLock":
          if self.vibeBackgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(self.vibeBackgroundTask)
            self.vibeBackgroundTask = .invalid
          }
          result(true)

        case "minimizeApp":
          // iOS does not allow programmatic minimize, safely return true
          result(true)

        case "resolveYouTubeStream":
          // NewPipe is Android-only; on iOS, Dart handles extraction via YoutubeExplode
          result(["ok": false, "message": "Native NewPipe extractor is Android-only. Fallback to Dart extraction."])

        default:
          result(FlutterMethodNotImplemented)
        }
      })
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

