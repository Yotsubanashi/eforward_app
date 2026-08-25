import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Native privacy cover. A Flutter-drawn overlay can't win the race against the
  // app-switcher snapshot: iOS captures that snapshot on the platform thread as
  // the app resigns active, before Flutter's next frame is rasterized, so the
  // session content leaks into the preview and into the first frame on reopen.
  // Covering here — driven by the real UIKit lifecycle — is the only reliable
  // fix. See `_MyAppState` in lib/app.dart for the Dart side of the handshake.
  private static let privacyChannelName = "eforward/privacy"
  private var privacyCover: UIView?
  // Flutter tells us whether covering is warranted (session active + unlock
  // enabled + device can authenticate). Off by default so we never trap a
  // logged-out user or one who opted out of the lock behind a cover.
  private var shouldCover = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: AppDelegate.privacyChannelName,
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, reply in
      guard let self = self else { reply(nil); return }
      switch call.method {
      case "setSecure":
        // Cache eligibility for the next resign-active. When the caller turns
        // covering off, drop any cover we're currently showing too.
        self.shouldCover = (call.arguments as? Bool) ?? false
        if !self.shouldCover { self.hidePrivacyCover() }
        reply(nil)
      case "hideCover":
        // Flutter's own lock overlay is on screen now, so the native cover can
        // come down with no content showing in between.
        self.hidePrivacyCover()
        reply(nil)
      default:
        reply(FlutterMethodNotImplemented)
      }
    }
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    // Fires before the snapshot is taken and before the biometric prompt shows,
    // so this cover hides content in the app switcher and behind Face ID alike.
    if shouldCover { showPrivacyCover() }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    // When covering isn't warranted, take the cover straight down. When it is,
    // leave it up: Flutter removes it via `hideCover` once its lock overlay has
    // painted, so there's never a frame of exposed content during the handoff.
    if !shouldCover { hidePrivacyCover() }
  }

  private func showPrivacyCover() {
    guard privacyCover == nil, let window = window else { return }

    let cover = UIView(frame: window.bounds)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.backgroundColor = .white

    // A single lock glyph, matching the Flutter lock screen's mark and color so
    // the native cover and the Dart overlay read as the same screen.
    let config = UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)
    let icon = UIImageView(image: UIImage(systemName: "lock.fill", withConfiguration: config))
    icon.tintColor = UIColor(red: 0xCC / 255.0, green: 0, blue: 0, alpha: 1)
    icon.translatesAutoresizingMaskIntoConstraints = false
    cover.addSubview(icon)
    NSLayoutConstraint.activate([
      icon.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
      icon.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
    ])

    window.addSubview(cover)
    privacyCover = cover
  }

  private func hidePrivacyCover() {
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
