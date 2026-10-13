import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:eforward_app/config/app_env.dart';
import 'package:eforward_app/constants/api_endpoints.dart';
import 'package:eforward_app/models/app_version_info.dart';
import 'package:eforward_app/services/privacy_cover_service.dart';

export 'package:eforward_app/models/app_version_info.dart';

class AppVersionService {
  AppVersionService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  // The backend defaults to android when `platform` is missing, which hands
  // iPhones a market:// (Play Store) link that iOS can't open.
  // Android stays on the original /app/version endpoint.
  static Uri get _defaultVersionEndpoint => Platform.isIOS
      ? Uri.parse('${AppEnv.apiBaseUrl}${ApiEndpoints.appVersion}?platform=ios')
      : Uri.parse('${AppEnv.apiBaseUrl}${ApiEndpoints.appVersionAndroid}');

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

  /// Opens the store/download URL. Matches HRIS's working pattern:
  /// `url_launcher` with the raw backend URL as the primary path, fire-and-
  /// forget (no bool trust — iOS reports false unreliably). Falls back to
  /// the https form, then a native `UIApplication.open` MethodChannel as a
  /// last resort.
  Future<bool> launchDownload(Uri url) async {
    debugPrint('[launchDownload] input=$url');

    // CRITICAL: suppress the native privacy cover BEFORE launching. The
    // cover observer in AppDelegate fires on UIScene.willDeactivateNotification
    // — which is exactly when iOS begins the transition to App Store. If it
    // adds the cover UIView to the window during that transition, iOS cancels
    // the transition and the App Store never opens. Awaiting both calls
    // guarantees the native flag is cleared BEFORE the launch request fires.
    try {
      debugPrint('[launchDownload] disabling privacy cover …');
      await PrivacyCoverService.setSecure(false);
      await PrivacyCoverService.hideCover();
      debugPrint('[launchDownload] privacy cover disabled');
    } catch (e) {
      debugPrint('[launchDownload] cover-disable failed (continuing): $e');
    }

    final candidates = <Uri>[url];
    final https = _httpsForm(url);
    if (https != null) candidates.add(https);

    // Primary path on all platforms — matches HRIS exactly.
    for (final candidate in candidates) {
      try {
        debugPrint('[launchDownload] url_launcher → $candidate');
        // Fire-and-forget — don't await the Future's bool; iOS lies about it.
        // ignore: unawaited_futures
        launchUrl(candidate, mode: LaunchMode.externalApplication);
        return true;
      } catch (e) {
        debugPrint('[launchDownload] url_launcher threw for $candidate: $e');
      }
    }

    // Last-resort iOS fallback — native UIApplication.open via MethodChannel.
    if (Platform.isIOS) {
      const channel = MethodChannel('eforward/launcher');
      for (final candidate in candidates) {
        try {
          debugPrint('[launchDownload] native openUrl → $candidate');
          final ok = await channel.invokeMethod<bool>(
              'openUrl', candidate.toString());
          if (ok == true) return true;
        } catch (e) {
          debugPrint('[launchDownload] native threw for $candidate: $e');
        }
      }
    }

    return false;
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

  /// Opens this app's Google Play listing so the user updates through Play.
  /// Play policy forbids apps from updating themselves outside Google Play,
  /// so Android never downloads or installs APKs in-app.
  Future<bool> openPlayStoreListing() async {
    final pkg = await getPackageName() ?? 'com.ardentnetworks.eforward';
    final candidates = [
      Uri.parse('market://details?id=$pkg'),
      Uri.parse('https://play.google.com/store/apps/details?id=$pkg'),
    ];
    for (final candidate in candidates) {
      try {
        if (await launchUrl(candidate, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (e) {
        debugPrint('[openPlayStoreListing] launch failed for $candidate: $e');
      }
    }
    return false;
  }

  void dispose() {
    _client.close();
  }
}

/// Brand accent used across the update dialog.
const Color _kBrandRed = Color(0xFFCC0000);
const Color _kMuted = Color(0xFF6B7280);

/// Dismissible "a newer version is available" prompt. Returns `true` if the
/// user tapped "Update Now" (store page launched); `false` if they tapped
/// "Later" or dismissed it.
Future<bool> showSoftUpdateDialog({
  required BuildContext context,
  required AppVersionInfo remote,
  required AppComparableVersion current,
}) async {
  // The dialog only collects the choice; the update runs after it has closed
  // so the caller's await covers the store hand-off.
  final wantsUpdate = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withOpacity(0.45),
    builder: (dialogContext) => _SoftUpdateCard(
      remote: remote,
      current: current,
      onUpdate: () async => Navigator.of(dialogContext).pop(true),
      onLater: () => Navigator.of(dialogContext).pop(false),
    ),
  );
  if (wantsUpdate != true || !context.mounted) return false;

  final svc = AppVersionService();
  try {
    if (Platform.isAndroid) {
      await svc.openPlayStoreListing();
    } else {
      await svc.launchDownload(remote.downloadUrl);
    }
  } catch (e) {
    debugPrint('Soft update launch failed: $e');
  } finally {
    svc.dispose();
  }
  return true;
}

/// Shows the force-update dialog. Returns `true` if the user tapped "Update Now".
/// Full-screen, non-dismissible mandatory-update wall. Pushed as a route (not
/// a dialog) so it occupies the entire display — no back button, no barrier
/// tap-through, no way past it except updating. Returns `true` once the user
/// taps "Update Now" and the Play Store/App Store link was launched.
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
/// primary action. Pops with `true` once the Play Store/App Store link is
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
    try {
      // The wall is never dismissed from here: whether the store update
      // finishes is up to the user, and returning must land back on the wall.
      final svc = AppVersionService();
      try {
        if (Platform.isAndroid) {
          await svc.openPlayStoreListing();
        } else {
          await svc.launchDownload(widget.remote.downloadUrl);
        }
      } finally {
        svc.dispose();
      }
    } catch (e) {
      debugPrint('Update launch failed: $e');
    } finally {
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

