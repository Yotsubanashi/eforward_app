import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:eforward_app/config/app_env.dart';
import 'package:eforward_app/constants/api_endpoints.dart';
import 'package:eforward_app/models/app_version_info.dart';
import 'package:eforward_app/services/privacy_cover_service.dart';

export 'package:eforward_app/models/app_version_info.dart';

class AppVersionService {
  AppVersionService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static Uri get _defaultVersionEndpoint =>
      Uri.parse('${AppEnv.apiBaseUrl}${ApiEndpoints.appVersion}');

  /// Returns true when [installed] is older than [latest] from the backend.
  static bool isUpdateRequired(
    AppComparableVersion installed,
    AppComparableVersion latest,
  ) {
    return installed < latest;
  }

  /// Classifies the installed version against the backend's min + latest.
  /// Below [AppVersionInfo.minSupportedVersion] → forced (blocking wall).
  /// Below [AppVersionInfo.latestVersion] (but at/above min) → soft (prompt).
  /// Otherwise → none.
  static AppUpdateAction decideUpdate(
    AppComparableVersion installed,
    AppVersionInfo remote,
  ) {
    final min = remote.minSupportedVersion;
    if (min != null && installed < min) return AppUpdateAction.forced;
    if (installed < remote.latestVersion) return AppUpdateAction.soft;
    return AppUpdateAction.none;
  }

  Future<AppVersionInfo?> fetchLatestVersion({
    Uri? endpoint,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = endpoint ?? _defaultVersionEndpoint;

    try {
      final res = await _client.get(uri).timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;

      final dynamic decoded = res.body.isNotEmpty ? jsonDecode(res.body) : null;
      if (decoded is! Map) return null;
      final payload = decoded['data'] is Map ? decoded['data'] : decoded;

      final latestStr =
          (payload['latest_version'] ??
                  payload['latestVersion'] ??
                  payload['mobile_version'] ??
                  payload['mobileVersion'])
              ?.toString()
              .trim();
      final urlStr =
          (payload['download_url'] ??
                  payload['downloadUrl'] ??
                  payload['mobile_url'] ??
                  payload['mobileUrl'])
              ?.toString()
              .trim();
      // Optional floor — null means "no forced update, soft prompt only".
      final minStr =
          (payload['min_supported_version'] ??
                  payload['minSupportedVersion'] ??
                  payload['min_version'] ??
                  payload['minVersion'])
              ?.toString()
              .trim();

      if (latestStr == null || latestStr.isEmpty) return null;
      if (urlStr == null || urlStr.isEmpty) return null;

      final latest = AppComparableVersion.tryParse(latestStr);
      if (latest == null) return null;

      final url = Uri.tryParse(urlStr);
      if (url == null) return null;

      return AppVersionInfo(
        latestVersion: latest,
        downloadUrl: url,
        minSupportedVersion: (minStr == null || minStr.isEmpty)
            ? null
            : AppComparableVersion.tryParse(minStr),
      );
    } catch (e) {
      debugPrint('fetchLatestVersion failed: $e');
      return null;
    }
  }

  Future<AppComparableVersion?> getInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      if (v.isEmpty) return null;

      return AppComparableVersion.fromVersionName(v);
    } catch (e) {
      debugPrint('getInstalledVersion failed: $e');
      return null;
    }
  }

  Future<String?> getPackageName() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final pkg = info.packageName.trim();
      return pkg.isEmpty ? null : pkg;
    } catch (e) {
      debugPrint('getPackageName failed: $e');
      return null;
    }
  }

  Future<void> launchUninstallFlow({required String packageName}) async {
    if (!Platform.isAndroid) return;
    final intent = AndroidIntent(
      action: 'android.intent.action.DELETE',
      data: 'package:$packageName',
    );
    await intent.launch();
  }

  /// Opens the store/download URL. On iOS, always prefer the `https://`
  /// App Store page form — the user has confirmed that
  /// `https://apps.apple.com/app/id6790258984` reliably opens the App Store
  /// app from inside Safari, and iOS auto-handles that domain via
  /// Universal Links from within apps too. On Android, launches the APK URL.
  ///
  /// Side-steps the native privacy-cover race by disabling the cover first:
  /// the cover hooks into scene resign-active notifications, which fire
  /// exactly when launchUrl tries to hand off to the App Store.
  Future<bool> launchDownload(Uri url) async {
    // iOS: always launch the https form. Android: launch the raw APK URL.
    final target =
        Platform.isIOS ? (_httpsForm(url) ?? url) : url;
    debugPrint('[launchDownload] original=$url  target=$target');

    // Drop the native privacy cover so it doesn't block the scene transition.
    // The cover re-syncs on next app resume via existing lifecycle hooks.
    try {
      await PrivacyCoverService.setSecure(false);
      await PrivacyCoverService.hideCover();
    } catch (_) {/* best-effort */}

    try {
      // Fire-and-forget — don't trust `launchUrl`'s return value on iOS
      // (it reports false unreliably during scene transitions).
      // ignore: unawaited_futures
      launchUrl(target, mode: LaunchMode.externalApplication);
      return true;
    } catch (e) {
      debugPrint('[launchDownload] launchUrl threw: $e');
      return false;
    }
  }

  /// Converts `itms-apps://apps.apple.com/...` or `itms-appss://.../` to the
  /// `https://apps.apple.com/...` equivalent. Returns null for unrelated URLs.
  static Uri? _httpsForm(Uri url) {
    final s = url.toString();
    for (final prefix in const ['itms-apps://', 'itms-appss://', 'itms://']) {
      if (s.startsWith(prefix)) {
        final rest = s.substring(prefix.length);
        final slash = rest.indexOf('/');
        final path = slash >= 0 ? rest.substring(slash) : '/';
        return Uri.parse('https://apps.apple.com$path');
      }
    }
    return null;
  }

  /// Downloads the APK at [url] and hands it to the Android package installer.
  ///
  /// This is what actually replaces the app on Android. The previous behaviour
  /// only opened the URL in a browser, which downloaded the file but never
  /// installed it — so the update never happened and the force-update gate kept
  /// re-appearing in an endless loop.
  ///
  /// Returns [AppInstallResult.installLaunched] when the system installer was
  /// opened. Callers should fall back to [launchDownload] on any other result.
  Future<AppInstallResult> downloadAndInstallApk(
    Uri url, {
    void Function(double progress)? onProgress,
  }) async {
    if (!Platform.isAndroid) return AppInstallResult.unsupported;

    // Android 8+ requires the user to allow "install unknown apps" for this app
    // before the installer can run. Ask for it up front; without it the install
    // intent silently fails and the loop would continue.
    try {
      final status = await Permission.requestInstallPackages.request();
      if (!status.isGranted) return AppInstallResult.permissionDenied;
    } catch (e) {
      debugPrint('requestInstallPackages failed: $e');
      // Older devices may not gate this permission — continue and let the
      // installer surface any problem.
    }

    File? apkFile;
    try {
      final dir =
          await getExternalStorageDirectory() ?? await getTemporaryDirectory();
      apkFile = File('${dir.path}/eforward-update.apk');

      final request = http.Request('GET', url);
      final response = await _client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return AppInstallResult.downloadFailed;
      }

      final total = response.contentLength ?? 0;
      var received = 0;
      final sink = apkFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0 && onProgress != null) {
            onProgress(received / total);
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (!await apkFile.exists() || await apkFile.length() == 0) {
        return AppInstallResult.downloadFailed;
      }

      // open_file bundles a FileProvider and launches the system package
      // installer for APK files.
      final result = await OpenFile.open(
        apkFile.path,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type == ResultType.done) {
        return AppInstallResult.installLaunched;
      }
      debugPrint('OpenFile install result: ${result.type} ${result.message}');
      return AppInstallResult.installFailed;
    } catch (e) {
      debugPrint('downloadAndInstallApk failed: $e');
      return AppInstallResult.downloadFailed;
    }
  }

  void dispose() {
    _client.close();
  }
}

/// Outcome of [AppVersionService.downloadAndInstallApk].
enum AppInstallResult {
  /// The system package installer was launched with the downloaded APK.
  installLaunched,

  /// Not Android — caller should open the download URL instead.
  unsupported,

  /// The user did not grant "install unknown apps".
  permissionDenied,

  /// The APK could not be downloaded.
  downloadFailed,

  /// The installer could not be opened for the downloaded file.
  installFailed,
}

/// Brand accent used across the update dialog.
const Color _kBrandRed = Color(0xFFCC0000);
const Color _kMuted = Color(0xFF6B7280);

/// Dismissible "a newer version is available" prompt. Returns `true` if the
/// user tapped "Update Now" (download/install launched); `false` if they tapped
/// "Later" or dismissed it.
Future<bool> showSoftUpdateDialog({
  required BuildContext context,
  required AppVersionInfo remote,
  required AppComparableVersion current,
}) async {
  var updateInitiated = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (dialogContext) => _SoftUpdateCard(
      remote: remote,
      current: current,
      onUpdate: () async {
        final svc = AppVersionService();
        try {
          if (Platform.isAndroid) {
            final result = await svc.downloadAndInstallApk(remote.downloadUrl);
            if (result == AppInstallResult.installLaunched) {
              updateInitiated = true;
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              return;
            }
            if (result == AppInstallResult.permissionDenied) {
              if (dialogContext.mounted) {
                ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Please allow installing apps from this source, '
                      'then tap Update again.',
                    ),
                  ),
                );
              }
              return;
            }
          }
          final ok = await svc.launchDownload(remote.downloadUrl);
          if (!dialogContext.mounted) return;
          if (ok) {
            updateInitiated = true;
            Navigator.of(dialogContext).pop();
          }
        } catch (e) {
          debugPrint('Soft update launch failed: $e');
        } finally {
          svc.dispose();
        }
      },
      onLater: () => Navigator.of(dialogContext).pop(),
    ),
  );

  return updateInitiated;
}

/// Shows the force-update dialog. Returns `true` if the user tapped "Update Now".
/// Full-screen, non-dismissible mandatory-update wall. Pushed as a route (not
/// a dialog) so it occupies the entire display — no back button, no barrier
/// tap-through, no way past it except updating. Returns `true` once the user
/// taps "Update Now" and the install/App Store link was launched.
Future<bool> showForceUpdateDialog({
  required BuildContext context,
  required AppVersionInfo remote,
  required AppComparableVersion current,
  required String? packageName,
}) async {
  final result = await Navigator.of(context, rootNavigator: true).push<bool>(
    PageRouteBuilder<bool>(
      opaque: true,
      fullscreenDialog: true,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => _ForceUpdateScreen(
        remote: remote,
        current: current,
      ),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ),
  );
  return result ?? false;
}

/// Full-screen force-update wall. Blocking (PopScope canPop:false),
/// brand-gradient background, large icon + title + version chips, bottom
/// primary action. Pops with `true` once the install/App Store link is
/// successfully launched.
class _ForceUpdateScreen extends StatefulWidget {
  const _ForceUpdateScreen({
    required this.remote,
    required this.current,
  });

  final AppVersionInfo remote;
  final AppComparableVersion current;

  @override
  State<_ForceUpdateScreen> createState() => _ForceUpdateScreenState();
}

class _ForceUpdateScreenState extends State<_ForceUpdateScreen> {
  bool _busy = false;

  Future<void> _handleUpdate() async {
    if (_busy) return;
    setState(() => _busy = true);
    final svc = AppVersionService();
    try {
      // Android → try the in-app installer first. Whether the installer
      // actually completes is decided by the user outside our app, so we
      // never dismiss the wall from here either (cancel-install must land
      // back on the wall, not on the obsolete content).
      if (Platform.isAndroid) {
        final result = await svc.downloadAndInstallApk(widget.remote.downloadUrl);
        if (result == AppInstallResult.installLaunched) return;
        if (result == AppInstallResult.permissionDenied) {
          if (mounted) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              const SnackBar(
                content: Text(
                  'Please allow installing apps from this source, '
                  'then tap Update again.',
                ),
              ),
            );
          }
          return;
        }
      }
      // Fire the store launch. DO NOT dismiss the force wall — this is a
      // mandatory update: the user must leave the app, install the new
      // version, and relaunch. Keeping the wall ensures they can't get back
      // to the app's content while still on the obsolete build.
      await svc.launchDownload(widget.remote.downloadUrl);
    } catch (e) {
      debugPrint('Update launch failed: $e');
    } finally {
      svc.dispose();
      // Always re-enable the button so the user can tap again if the App
      // Store didn't open (e.g. offline). The wall itself remains until the
      // app is replaced by a store install.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE11414), _kBrandRed],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(),
                  // Icon badge
                  Container(
                    height: 112,
                    width: 112,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.28),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: Colors.white,
                      size: 56,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Time to update',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'We’ve made important improvements to keep '
                    'E-Forward running smoothly. Install the latest version '
                    'to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      height: 1.5,
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _handleUpdate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: _kBrandRed,
                        disabledBackgroundColor: Colors.white.withOpacity(0.7),
                        disabledForegroundColor: _kBrandRed,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.6,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(_kBrandRed),
                              ),
                            )
                          : const Text('Update Now'),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SoftUpdateCard extends StatefulWidget {
  const _SoftUpdateCard({
    required this.remote,
    required this.current,
    required this.onUpdate,
    required this.onLater,
  });

  final AppVersionInfo remote;
  final AppComparableVersion current;
  final Future<void> Function() onUpdate;
  final VoidCallback onLater;

  @override
  State<_SoftUpdateCard> createState() => _SoftUpdateCardState();
}

class _SoftUpdateCardState extends State<_SoftUpdateCard> {
  bool _busy = false;

  Future<void> _handleUpdate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onUpdate();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 40,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Softer header (same brand tone, lighter copy than the force wall).
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE11414), _kBrandRed],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    height: 72,
                    width: 72,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.28),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.cloud_download_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'A fresh update is here',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                children: [
                  const Text(
                    'Enjoy a smoother experience with the latest '
                    'improvements and fixes. Update when you’re ready.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _kMuted,
                      fontSize: 14.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: TextButton(
                            onPressed: _busy ? null : widget.onLater,
                            style: TextButton.styleFrom(
                              foregroundColor: _kMuted,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: const BorderSide(
                                    color: Color(0xFFE5E7EB), width: 1.2),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            child: const Text('Later'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _busy ? null : _handleUpdate,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kBrandRed,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  _kBrandRed.withOpacity(0.6),
                              disabledForegroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            child: _busy
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(
                                              Colors.white),
                                    ),
                                  )
                                : const Text('Update'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

