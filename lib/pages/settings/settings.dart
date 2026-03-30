import 'package:flutter/material.dart';
import 'package:eforward_app/pages/auth/login.dart'; // 👈 import your login screen
import 'package:eforward_app/components/bottom_navigator.dart';
import '../auth/change_password.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    int selectedIndex = 2;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 18,
                    color: const Color(0xFFCC0000),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    "EFORWARD SETTINGS",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Color(0xFFCC0000),
                    ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            const SizedBox(height: 24),

            // Profile Card
            Center(
              child: Column(
                children: [
                  // Avatar
                  Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F0F0),
                          border: Border.all(
                            color: const Color(0xFFDDDDDD),
                            width: 1.5,
                          ),
                        ),
                        child: const Icon(
                          Icons.person,
                          size: 50,
                          color: Color(0xFF999999),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Name
                  const Text(
                    "Mark Cedrick M. Almueda",
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 4),

                  // Role
                  const Text(
                    "Technical Support",
                    style: TextStyle(
                      fontSize: 18,
                      color: Color(0xFF1A1A1A),
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),

                  const SizedBox(height: 12),

                  // ID / Unit / Status
                  Text(
                    "ID: 001 · UNIT: 01",
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.black38,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "STATUS: ACTIVE",
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.black38,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),

            // Change Password
            _buildMenuItem(
              context,
              icon: Icons.lock_outline,
              iconColor: const Color(0xFFCC0000),
              label: "SYSTEM ACCESS",
              title: "CHANGE PASSWORD",
              trailing: const Icon(
                Icons.chevron_right,
                color: Color(0xFFAAAAAA),
                size: 20,
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
              ),
            ),

            const Divider(height: 1, color: Color(0xFFEEEEEE)),

            // Logout
            _buildMenuItem(
              context,
              icon: Icons.logout,
              iconColor: const Color(0xFF555555),
              label: "SESSION MANAGEMENT",
              title: "LOGOUT",
              trailing: const Icon(
                Icons.power_settings_new,
                color: Color(0xFFAAAAAA),
                size: 18,
              ),
              onTap: () {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
            ),

            const Divider(height: 1, color: Color(0xFFEEEEEE)),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigator(
        selectedIndex: selectedIndex,
        onTap: (index) => setState(() => selectedIndex = index),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String title,
    required Widget trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                border: Border.all(color: const Color(0xFFEEEEEE)),
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFFAAAAAA),
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  void setState(int Function() param0) {}
}
