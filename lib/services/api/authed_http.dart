import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:eforward_app/config/app_env.dart';
import 'package:eforward_app/services/api/auth_api.dart';
import 'package:eforward_app/services/token_store.dart';

export 'package:http/http.dart'
    hide get, post, put, patch, delete, head, read, readBytes;

/// Drop-in replacement for `package:http`'s top-level request functions that
/// refreshes an expired session once and retries.
///
/// Import it in place of `package:http/http.dart as http`. When a request to
/// our backend that carried `Authorization: Bearer …` comes back `401`, it
/// calls `/auth/refresh` once (shared across concurrent requests), stores BOTH
/// rotated tokens, and replays the request with the new access token. If the
/// refresh fails, the original `401` is returned, so the existing
/// `SessionExpiryService` handling still logs the user out.

Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
    _withRefresh(url, headers, (h) => http.get(url, headers: h));

Future<http.Response> post(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _withRefresh(
  url,
  headers,
  (h) => http.post(url, headers: h, body: body, encoding: encoding),
);

Future<http.Response> put(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _withRefresh(
  url,
  headers,
  (h) => http.put(url, headers: h, body: body, encoding: encoding),
);

Future<http.Response> patch(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _withRefresh(
  url,
  headers,
  (h) => http.patch(url, headers: h, body: body, encoding: encoding),
);

Future<http.Response> delete(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
}) => _withRefresh(
  url,
  headers,
  (h) => http.delete(url, headers: h, body: body, encoding: encoding),
);

/// For requests that can't be expressed with the helpers above (e.g.
/// [http.MultipartRequest]). [build] is called again for the retry because a
/// request can only be sent once.
Future<http.Response> send(FutureOr<http.BaseRequest> Function() build) async {
  final first = await build();
  final response = await http.Response.fromStream(await first.send());
  final stale = _bearer(first.headers);
  if (!_shouldRefresh(first.url, stale, response)) return response;

  final fresh = await refreshAccessToken(stale!);
  if (fresh == null) return response;
  final retry = (await build())..headers['Authorization'] = 'Bearer $fresh';
  return http.Response.fromStream(await retry.send());
}

Future<http.Response> _withRefresh(
  Uri url,
  Map<String, String>? headers,
  Future<http.Response> Function(Map<String, String>? headers) request,
) async {
  final response = await request(headers);
  final stale = _bearer(headers);
  if (!_shouldRefresh(url, stale, response)) return response;

  final fresh = await refreshAccessToken(stale!);
  if (fresh == null) return response;
  return request({...?headers, 'Authorization': 'Bearer $fresh'});
}

bool _shouldRefresh(Uri url, String? bearer, http.Response response) {
  if (response.statusCode != 401 || bearer == null) return false;
  // Only our own backend; never leak a refresh attempt to third-party hosts.
  return url.host == Uri.tryParse(AppEnv.apiBaseUrl)?.host;
}

String? _bearer(Map<String, String>? headers) {
  if (headers == null) return null;
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() != 'authorization') continue;
    final value = entry.value.trim();
    if (!value.startsWith('Bearer ')) return null;
    final token = value.substring(7).trim();
    return token.isEmpty ? null : token;
  }
  return null;
}

Future<String?>? _inflight;

/// Exchanges the stored refresh token for a new pair and returns the new
/// access token, or null when the session can't be renewed.
///
/// [staleToken] is the access token that just got a 401. If the stored token
/// has already moved on (another request refreshed first), that one is
/// returned without a second refresh call — refresh tokens rotate, so firing
/// two refreshes with the same token would make the second one fail.
Future<String?> refreshAccessToken(String staleToken) async {
  final current = await TokenStore.accessToken();
  if (current.isNotEmpty && current != staleToken) return current;

  return _inflight ??= () async {
    try {
      final authApi = AuthApi();
      final result = await authApi.refreshWithStoredToken();
      authApi.dispose();
      if (!result.isSuccess) return null;
      final fresh = await TokenStore.accessToken();
      return fresh.isEmpty ? null : fresh;
    } catch (e) {
      debugPrint('Token refresh failed: $e');
      return null;
    } finally {
      _inflight = null;
    }
  }();
}
