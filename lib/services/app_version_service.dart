import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:eforward_app/config/app_env.dart';

class AppVersionInfo {
  const AppVersionInfo({
    required this.latestVersion,
    required this.downloadUrl,
  });

  final AppComparableVersion latestVersion;
  final Uri downloadUrl;
}

/// Compares semver only (e.g. `3.1.2`). Build numbers are ignored.
class AppComparableVersion implements Comparable<AppComparableVersion> {
  const AppComparableVersion({
    required this.major,
    required this.minor,
    required this.patch,
  });

  final int major;
  final int minor;
  final int patch;

  static AppComparableVersion? tryParse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // Only semver-style strings are supported (e.g. 3.1.2, v3.1.2, 3.1.2+17).
    if (RegExp(r'^\d+$').hasMatch(trimmed)) return null;

    final normalized =
        trimmed.startsWith('v') || trimmed.startsWith('V') ? trimmed.substring(1) : trimmed;

    // Drop any +build suffix — comparison uses major.minor.patch only.
    final core = normalized.split('+').first;
    final parts = core.split('.');

    if (parts.isEmpty || parts.length < 2) return null;

    return AppComparableVersion(
      major: _extractLeadingInt(parts[0]),
      minor: parts.length > 1 ? _extractLeadingInt(parts[1]) : 0,
      patch: parts.length > 2 ? _extractLeadingInt(parts[2]) : 0,
    );
  }

  static int _extractLeadingInt(String s) {
    final match = RegExp(r'^\d+').firstMatch(s.trim());
    if (match == null) return 0;
    return int.tryParse(match.group(0)!) ?? 0;
  }

  static AppComparableVersion? fromVersionName(String versionName) {
    return tryParse(versionName);
  }

  @override
  int compareTo(AppComparableVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return 0;
  }

  bool operator <(AppComparableVersion other) => compareTo(other) < 0;
  bool operator <=(AppComparableVersion other) => compareTo(other) <= 0;
  bool operator >(AppComparableVersion other) => compareTo(other) > 0;
  bool operator >=(AppComparableVersion other) => compareTo(other) >= 0;
  @override
  bool operator ==(Object other) =>
      other is AppComparableVersion && compareTo(other) == 0;
  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

class AppVersionService {
  AppVersionService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static Uri get _defaultVersionEndpoint =>
      Uri.parse('${AppEnv.apiBaseUrl}/app/version');

  /// Returns true when [installed] is older than [latest] from the backend.
  static bool isUpdateRequired(
    AppComparableVersion installed,
    AppComparableVersion latest,
  ) {
    return installed < latest;
  }

  Future<AppVersionInfo?> fetchLatestVersion({
    Uri? endpoint,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = endpoint ?? _defaultVersionEndpoint;

    try {
      final res = await _client.get(uri).timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 300) return null;

      final dynamic decoded =
          res.body.isNotEmpty ? jsonDecode(res.body) : null;
      if (decoded is! Map) return null;
      final payload = decoded['data'] is Map ? decoded['data'] : decoded;

      final latestStr = (payload['latest_version'] ??
              payload['latestVersion'] ??
              payload['mobile_version'] ??
              payload['mobileVersion'])
          ?.toString()
          .trim();
      final urlStr = (payload['download_url'] ??
              payload['downloadUrl'] ??
              payload['mobile_url'] ??
              payload['mobileUrl'])
          ?.toString()
          .trim();

      if (latestStr == null || latestStr.isEmpty) return null;
      if (urlStr == null || urlStr.isEmpty) return null;

      final latest = AppComparableVersion.tryParse(latestStr);
      if (latest == null) return null;

      final url = Uri.tryParse(urlStr);
      if (url == null) return null;

      return AppVersionInfo(latestVersion: latest, downloadUrl: url);
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

  Future<bool> launchDownload(Uri url) async {
    return launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void dispose() {
    _client.close();
  }
}

/// Shows the force-update dialog. Returns `true` if the user tapped "Update Now".
Future<bool> showForceUpdateDialog({
  required BuildContext context,
  required AppVersionInfo remote,
  required AppComparableVersion current,
  required String? packageName,
}) async {
  var updateInitiated = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Update Required'),
          content: Text(
            'Your app version is outdated.\n\n'
            'Current: $current\n'
            'Latest: ${remote.latestVersion}\n\n'
            'Tap "Update Now" to download and install the latest version.',
          ),
          actions: [
            TextButton(
              onPressed: () async {
                try {
                  final svc = AppVersionService();
                  final ok = await svc.launchDownload(remote.downloadUrl);
                  svc.dispose();
                  if (!dialogContext.mounted) return;

                  if (!ok) {
                    final messenger = ScaffoldMessenger.maybeOf(dialogContext);
                    messenger?.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Unable to open update link. Check the APK URL.',
                        ),
                      ),
                    );
                    return;
                  }

                  updateInitiated = true;
                  Navigator.of(dialogContext).pop();
                } catch (e) {
                  debugPrint('Update launch failed: $e');
                }
              },
              child: const Text('Update Now'),
            ),
          ],
        ),
      );
    },
  );

  return updateInitiated;
}
