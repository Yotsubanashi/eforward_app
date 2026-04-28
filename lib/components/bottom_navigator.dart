import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:eforward_app/config/app_env.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/pages/dashboard/dashboard.dart';
import 'package:eforward_app/pages/settings/settings.dart';
import 'package:eforward_app/pages/document/sign.dart';
import 'package:eforward_app/pages/document/view_sign.dart';
import 'package:eforward_app/pages/notifications/notifications.dart';
import 'package:eforward_app/services/notifications_service.dart';

class BottomNavigator extends StatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const BottomNavigator({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  State<BottomNavigator> createState() => _BottomNavigatorState();
}

class _BottomNavigatorState extends State<BottomNavigator> {
  final NotificationsService _notificationsService = NotificationsService();
  Timer? _timer;

  Widget _buildNotificationIcon({
    required int unreadCount,
    required bool isActive,
  }) {
    final icon = Icon(
      isActive ? Icons.notifications : Icons.notifications_outlined,
    );

    if (unreadCount <= 0) return icon;

    final String label = unreadCount > 99 ? '99+' : unreadCount.toString();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -6,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFCC0000),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _notificationsService.fetchUnreadCount();
    // Refresh unread count every 30 seconds
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      _notificationsService.fetchUnreadCount();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _navigate(BuildContext context, int index) async {
    if (index == widget.selectedIndex) return;

    final prefs = await SharedPreferences.getInstance();

    switch (index) {
      case 0:
        // 👇 Retrieve saved userData from SharedPreferences
        final userDataStr = prefs.getString('user_data');
        Map<String, dynamic>? userData;
        if (userDataStr != null && userDataStr.isNotEmpty) {
          try {
            userData = jsonDecode(userDataStr) as Map<String, dynamic>?;
          } catch (e) {
            debugPrint('Error parsing userData: $e');
          }
        }
        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => DashboardPage(userData: userData),
            ),
          );
        }
        break;
      case 1:
        // Check local first
        bool hasSignature = prefs.getBool('has_signature') ?? false;
        final token = prefs.getString('access_token') ?? '';

        // If not found locally, check API
        if (!hasSignature && token.isNotEmpty) {
          try {
            final response = await http.get(
              Uri.parse('${AppEnv.apiBaseUrl}/upload/signature/image'),
              headers: {'Authorization': 'Bearer $token'},
            );
            if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
              hasSignature = true;
              await prefs.setBool('has_signature', true); // save for next time
              debugPrint('Signature found on server, updating local flag.');
            }
          } catch (e) {
            debugPrint('Signature check error: $e');
          }
        }

        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  hasSignature ? const ViewSignPage() : const SignScreen(),
            ),
          );
        }
        break;
      case 2:
        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsPage()),
          );
        }
        break;
      case 3:
        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const SettingsPage()),
          );
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: widget.selectedIndex,
      onTap: (index) => _navigate(context, index),
      backgroundColor: Colors.white,
      selectedItemColor: const Color(0xFFCC0000),
      unselectedItemColor: const Color(0xFFAAAAAA),
      selectedLabelStyle: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_outlined),
          activeIcon: Icon(Icons.dashboard),
          label: 'DASHBOARD',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.draw_outlined),
          activeIcon: Icon(Icons.draw),
          label: 'SIGN',
        ),
        // Notifications with reactive badge
        BottomNavigationBarItem(
          icon: ValueListenableBuilder<int>(
            valueListenable: _notificationsService.unreadCountNotifier,
            builder: (context, unreadCount, _) {
              return _buildNotificationIcon(
                unreadCount: unreadCount,
                isActive: false,
              );
            },
          ),
          activeIcon: ValueListenableBuilder<int>(
            valueListenable: _notificationsService.unreadCountNotifier,
            builder: (context, unreadCount, _) {
              return _buildNotificationIcon(
                unreadCount: unreadCount,
                isActive: true,
              );
            },
          ),
          label: 'NOTIFICATIONS',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings),
          label: 'SETTINGS',
        ),
      ],
    );
  }
}
