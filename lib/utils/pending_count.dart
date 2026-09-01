import 'dart:convert';
import 'package:eforward_app/constants/api_endpoints.dart';
import 'package:eforward_app/constants/shared_prefs_keys.dart';
import 'package:eforward_app/services/session_expiry_service.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Result of counting all pending approvals.
class PendingCountResult {
  const PendingCountResult({required this.count, required this.capped});

  /// The total number of pending approvals.
  final int count;

  /// True when the count hit the safety page limit and may be an undercount
  /// (display with a trailing "+"). False for an exact total.
  final bool capped;
}

/// Page size used when paging through pending approvals to count them.
const int _pendingCountPageSize = 100;

/// Hard safety limit on how many pages to walk (100 * 100 = 10,000 records).
const int _pendingCountMaxPages = 100;

/// Returns the authoritative number of pending approvals for the current user.
///
/// Used by BOTH the dashboard "PENDING APPROVALS" card and the approvals
/// screen "PENDING" badge so the two can never disagree. It prefers a
/// server-provided total from the response envelope; when the server exposes no
/// total it pages through every pending record with `GET /approvals/pending`
/// and counts them, so the result reflects the real total no matter how many
/// there are (no 10/50 cap).
///
/// Returns null on auth/network failure so the caller can leave its current
/// value untouched.
Future<PendingCountResult?> countAllPending(String baseUrl) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(SharedPrefsKeys.accessToken) ?? '';
    if (token.isEmpty) return null;

    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };

    var total = 0;
    var page = 1;

    while (page <= _pendingCountMaxPages) {
      final uri = Uri.parse('$baseUrl${ApiEndpoints.approvalsPending}').replace(
        queryParameters: {
          'page': '$page',
          'limit': '$_pendingCountPageSize',
        },
      );

      final response = await http.get(uri, headers: headers);

      if (SessionExpiryService().isUnauthorized(response.statusCode)) {
        return null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(response.body);

      // Prefer an authoritative total from the response envelope.
      final serverTotal = _extractTotal(decoded);
      if (serverTotal != null) {
        return PendingCountResult(count: serverTotal, capped: false);
      }

      final pageCount = _extractList(decoded).length;
      total += pageCount;

      // A short (or empty) page means we've reached the end.
      if (pageCount < _pendingCountPageSize) {
        return PendingCountResult(count: total, capped: false);
      }
      page++;
    }

    // Reached the safety limit — report what we have, flagged as capped.
    return PendingCountResult(count: total, capped: true);
  } catch (e) {
    debugPrint('countAllPending error: $e');
    return null;
  }
}

/// Extracts the list of rows from the various shapes the API may return.
List<dynamic> _extractList(dynamic decoded) {
  if (decoded is List) return decoded;
  if (decoded is Map) {
    for (final key in ['data', 'approvals', 'items', 'results', 'list']) {
      if (decoded[key] is List) return decoded[key] as List;
      if (decoded[key] is Map && decoded[key]['data'] is List) {
        return decoded[key]['data'] as List;
      }
    }
  }
  return [];
}

/// Extracts an authoritative total count from the response envelope, checking
/// both top-level keys and keys nested under a meta/pagination object. Returns
/// null when the server exposes no total.
int? _extractTotal(dynamic decoded) {
  const keys = [
    'total',
    'total_count',
    'totalCount',
    'total_records',
    'totalItems',
    'count',
  ];

  int? readFrom(Map map) {
    for (final key in keys) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  if (decoded is Map) {
    final top = readFrom(decoded);
    if (top != null) return top;
    for (final key in ['meta', 'pagination', 'paging']) {
      if (decoded[key] is Map) {
        final nested = readFrom(decoded[key] as Map);
        if (nested != null) return nested;
      }
    }
  }
  return null;
}
