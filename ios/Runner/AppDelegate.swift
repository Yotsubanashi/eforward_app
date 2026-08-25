import Flutter
import QuartzCore
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Native privacy cover. A Flutter-drawn overlay can't win the race against the
  // OS snapshot: iOS captures it on the platform thread as the scene resigns
  // active (app switcher) or when the device is locked, before Flutter's next
  // frame is rasterized — so session content leaks into the preview and into the
  // first frame after unlock. Covering here, on the real UIKit lifecycle, is the
  // only reliable fix. See `_MyAppState` in lib/app.dart for the Dart handshake.
  //
  // IMPORTANT: this app uses the UIScene lifecycle (FlutterSceneDelegate is
  // declared in Info.plist). With a scene delegate present, UIKit does NOT call
  // the UIApplicationDelegate active/background callbacks, and AppDelegate.window
  // is nil. So the cover must be driven by the *scene* notifications and attached
  // to the window found from the scene — not from the app delegate.
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
    registerSceneLifecycleObservers()
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
        // Flutter's own lock overlay is on screen now (or the user has
        // authenticated), so the native cover can come down with no content
        // showing in between.
        self.hidePrivacyCover()
        reply(nil)
      default:
        reply(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Scene lifecycle

  private func registerSceneLifecycleObservers() {
    let nc = NotificationCenter.default
    // willDeactivate fires before the OS snapshots the scene (app switcher and
    // device lock alike) and before a biometric prompt shows — cover here.
    nc.addObserver(
      self, selector: #selector(coverForSceneNotification(_:)),
      name: UIScene.willDeactivateNotification, object: nil)
    // Belt-and-suspenders: a power-button lock can reach background without a
    // clean deactivate first, and the app-switcher snapshot is taken here too.
    nc.addObserver(
      self, selector: #selector(coverForSceneNotification(_:)),
      name: UIScene.didEnterBackgroundNotification, object: nil)
    // On return to the foreground, only drop the cover when covering isn't
    // warranted; otherwise Flutter removes it via `hideCover` once its lock
    // overlay has painted or the user has authenticated.
    nc.addObserver(
      self, selector: #selector(sceneDidActivate(_:)),
      name: UIScene.didActivateNotification, object: nil)
  }

  @objc private func coverForSceneNotification(_ note: Notification) {
    if shouldCover { showPrivacyCover(on: note.object as? UIWindowScene) }
  }

  @objc private func sceneDidActivate(_ note: Notification) {
    if !shouldCover { hidePrivacyCover() }
  }

  /// Resolve the window to cover: prefer the scene from the notification, then
  /// fall back to any connected foreground window scene.
  private func coverWindow(preferring scene: UIWindowScene?) -> UIWindow? {
    if let window = window(in: scene) { return window }
    for connected in UIApplication.shared.connectedScenes {
      if let window = window(in: connected as? UIWindowScene) { return window }
    }
    return nil
  }

  private func window(in scene: UIWindowScene?) -> UIWindow? {
    guard let scene = scene else { return nil }
    return scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
  }

  private func showPrivacyCover(on scene: UIWindowScene?) {
    guard privacyCover == nil, let window = coverWindow(preferring: scene) else { return }

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
    window.bringSubviewToFront(cover)
    privacyCover = cover

    // Critical for the device power-off/on case. On a power-button lock, iOS
    // captures the scene snapshot right at deactivate — before the render server
    // would normally composite this freshly-added view — and restores that
    // snapshot when the app returns after the phone is unlocked. Without a
    // forced, synchronous commit the snapshot still holds the old content, which
    // flashes for a frame before the live cover paints. Committing the layer
    // tree now guarantees the cover is what gets snapshotted.
    cover.layoutIfNeeded()
    CATransaction.flush()
  }

  private func hidePrivacyCover() {
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
