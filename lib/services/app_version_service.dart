import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:eforward_app/config/app_env.dart';

class AppVersionInfo {
  const AppVersionInfo({
    required this.latestVersion,
    required this.downloadUrl,
  });

  final Version latestVersion;
  final Uri downloadUrl;
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

      final latestStr = (decoded['latest_version'] ?? decoded['latestVersion'])
          ?.toString()
          .trim();
      final urlStr = (decoded['download_url'] ?? decoded['downloadUrl'])
          ?.toString()
          .trim();

      if (latestStr == null || latestStr.isEmpty) return null;
      if (urlStr == null || urlStr.isEmpty) return null;

      final latest = Version.parse(latestStr);
      final url = Uri.tryParse(urlStr);
      if (url == null) return null;

      return AppVersionInfo(latestVersion: latest, downloadUrl: url);
    } catch (e) {
      debugPrint('fetchLatestVersion failed: $e');
      return null;
    }
  }

  Future<Version?> getInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      if (v.isEmpty) return null;
      return Version.parse(v);
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

  Future<void> launchDownload(Uri url) async {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  void dispose() {
    _client.close();
  }
}

Future<void> showForceUpdateDialog({
  required BuildContext context,
  required AppVersionInfo remote,
  required Version current,
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
                  await svc.launchDownload(remote.downloadUrl);
                  svc.dispose();
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

