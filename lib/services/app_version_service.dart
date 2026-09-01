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
const Color _kInk = Color(0xFF1A1A1A);
const Color _kMuted = Color(0xFF6B7280);

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
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (dialogContext) {
      return PopScope(
        canPop: false,
        child: _ForceUpdateCard(
          remote: remote,
          current: current,
          onUpdate: (setProgress) async {
            final svc = AppVersionService();
            try {
              // On Android, download the APK and hand it to the system
              // installer so the app is actually replaced. Fall back to opening
              // the URL in a browser only if that path is unavailable.
              if (Platform.isAndroid) {
                final result = await svc.downloadAndInstallApk(
                  remote.downloadUrl,
                  onProgress: setProgress,
                );

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
                // Download/install failed → fall through to the browser link.
              }

              final ok = await svc.launchDownload(remote.downloadUrl);
              if (!dialogContext.mounted) return;

              if (!ok) {
                ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
                  const SnackBar(
                    content:
                        Text('Unable to open update link. Please try again.'),
                  ),
                );
                return;
              }

              updateInitiated = true;
              Navigator.of(dialogContext).pop();
            } catch (e) {
              debugPrint('Update launch failed: $e');
            } finally {
              svc.dispose();
            }
          },
        ),
      );
    },
  );

  return updateInitiated;
}

class _ForceUpdateCard extends StatefulWidget {
  const _ForceUpdateCard({
    required this.remote,
    required this.current,
    required this.onUpdate,
  });

  final AppVersionInfo remote;
  final AppComparableVersion current;
  final Future<void> Function(void Function(double progress) setProgress)
      onUpdate;

  @override
  State<_ForceUpdateCard> createState() => _ForceUpdateCardState();
}

class _ForceUpdateCardState extends State<_ForceUpdateCard> {
  bool _busy = false;
  double? _progress;

  Future<void> _handleUpdate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _progress = null;
    });
    try {
      await widget.onUpdate((p) {
        if (mounted) setState(() => _progress = p.clamp(0.0, 1.0));
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
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
            // Header with brand gradient + icon badge.
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
                      Icons.system_update_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Update Required',
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
            // Body.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                children: [
                  const Text(
                    'A newer version of the app is available. '
                    'Please update to continue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _kMuted,
                      fontSize: 14.5,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _VersionRow(
                    current: widget.current.toString(),
                    latest: widget.remote.latestVersion.toString(),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _busy ? null : _handleUpdate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kBrandRed,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _kBrandRed.withOpacity(0.6),
                        disabledForegroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: _busy
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  height: 22,
                                  width: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    value: _progress,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                ),
                                if (_progress != null) ...[
                                  const SizedBox(width: 12),
                                  Text(
                                    'Downloading ${(_progress! * 100).round()}%',
                                  ),
                                ],
                              ],
                            )
                          : const Text('Update Now'),
                    ),
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

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.current, required this.latest});

  final String current;
  final String latest;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEEF1)),
      ),
      child: Row(
        children: [
          Expanded(child: _VersionChip(label: 'Current', value: current)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward_rounded, size: 18, color: _kMuted),
          ),
          Expanded(
            child: _VersionChip(
              label: 'Latest',
              value: latest,
              highlight: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: _kMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: highlight ? _kBrandRed : _kInk,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
