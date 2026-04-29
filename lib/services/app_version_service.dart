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

/// Compares `versionName` + `buildNumber` (the `+build` in pubspec).
/// NOTE: For your current requirement we ignore `+build` and compare ONLY
/// `major.minor.patch` (versionName).
class AppComparableVersion implements Comparable<AppComparableVersion> {
  const AppComparableVersion({
    required this.major,
    required this.minor,
    required this.patch,
    required this.build,
  });

  final int major;
  final int minor;
  final int patch;
  final int build;

  static AppComparableVersion? tryParse(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final normalized =
        trimmed.startsWith('v') || trimmed.startsWith('V') ? trimmed.substring(1) : trimmed;
    final plusParts = normalized.split('+');
    final coreParts = plusParts.first.split('.');
    if (coreParts.length < 3) return null;

    final major = int.tryParse(coreParts[0]);
    final minor = int.tryParse(coreParts[1]);
    final patch = int.tryParse(coreParts[2]);
    if (major == null || minor == null || patch == null) return null;

    // Ignored for comparison.
    const build = 0;

    return AppComparableVersion(
      major: major,
      minor: minor,
      patch: patch,
      build: build,
    );
  }

  static AppComparableVersion fromVersionNameAndBuildNumber({
    required String versionName,
    required String buildNumber,
  }) {
    final v = versionName.trim();
    // buildNumber is intentionally ignored.
    return AppComparableVersion(
      major: int.parse(v.split('.')[0]),
      minor: int.parse(v.split('.')[1]),
      patch: int.parse(v.split('.')[2]),
      build: 0,
    );
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
  int get hashCode => Object.hash(major, minor, patch, build);

  @override
  String toString() => '$major.$minor.$patch';
}

class AppVersionService {
  AppVersionService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static Uri get _defaultVersionEndpoint =>
      Uri.parse('${AppEnv.apiBaseUrl}/app/version');

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
      // Compare ONLY the versionName; ignore buildNumber for dialog display.
      return AppComparableVersion.tryParse(v.split('+').first);
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

Future<void> showForceUpdateDialog({
  required BuildContext context,
  required AppVersionInfo remote,
  required AppComparableVersion current,
  required String? packageName,
}) async {
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
                  if (!ok) {
                    final messenger = ScaffoldMessenger.maybeOf(dialogContext);
                    messenger?.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Unable to open update link. Check the APK URL.',
                        ),
                      ),
                    );
                  }
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
}

