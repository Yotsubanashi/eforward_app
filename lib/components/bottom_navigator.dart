import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/pages/dashboard/dashboard.dart';
import 'package:eforward_app/pages/settings/settings.dart';
import 'package:eforward_app/pages/document/sign.dart';
import 'package:eforward_app/pages/document/view_sign.dart';

class BottomNavigator extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const BottomNavigator({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  Future<void> _navigate(BuildContext context, int index) async {
    if (index == selectedIndex) return;

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
              Uri.parse(
                'https://eforward-api.ardentnetworks.com.ph/api/upload/signature/image',
              ),
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
            MaterialPageRoute(builder: (_) => const SettingsPage()),
          );
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: selectedIndex,
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
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_outlined),
          activeIcon: Icon(Icons.dashboard),
          label: 'DASHBOARD',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.draw_outlined),
          activeIcon: Icon(Icons.draw),
          label: 'SIGN',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings),
          label: 'SETTINGS',
        ),
      ],
    );
  }
}
