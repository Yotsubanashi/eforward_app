import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class NotificationsService {
  static final NotificationsService _instance =
      NotificationsService._internal();
  static const String _baseUrl =
      'https://eforward-api.ardentnetworks.com.ph/api';

  // ValueNotifier to notify listeners when unread count changes
  final ValueNotifier<int> unreadCountNotifier = ValueNotifier<int>(0);

  NotificationsService._internal();

  factory NotificationsService() {
    return _instance;
  }

  /// Fetch unread count from API and update the notifier
  Future<void> fetchUnreadCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      if (token.isEmpty) return;

      final response = await http.get(
        Uri.parse('$_baseUrl/notifications/unread-count'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final count =
            decoded['unread_count'] as int? ?? decoded['count'] as int? ?? 0;
        unreadCountNotifier.value = count;
      }
    } catch (e) {
      debugPrint('Unread count fetch error: $e');
    }
  }

  /// Increment unread count (called when new notification arrives)
  void incrementUnreadCount() {
    unreadCountNotifier.value++;
    debugPrint('📬 Unread count incremented to: ${unreadCountNotifier.value}');
  }

  /// Mark a single notification as read and update unread count
  Future<bool> markAsRead(String notificationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      if (token.isEmpty) return false;

      final response = await http.patch(
        Uri.parse('$_baseUrl/notifications/$notificationId/read'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Immediately decrease the count without waiting for API call
        if (unreadCountNotifier.value > 0) {
          unreadCountNotifier.value--;
        }
        // Also fetch the actual count to ensure sync
        await Future.delayed(const Duration(milliseconds: 500));
        await fetchUnreadCount();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Mark as read error: $e');
      return false;
    }
  }

  /// Mark all notifications as read
  Future<bool> markAllAsRead() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      if (token.isEmpty) return false;

      final response = await http.patch(
        Uri.parse('$_baseUrl/notifications/mark-all-read'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Set count to 0
        unreadCountNotifier.value = 0;
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Mark all as read error: $e');
      return false;
    }
  }

  /// Reset the notifier (for testing or logout)
  void reset() {
    unreadCountNotifier.value = 0;
  }
}
