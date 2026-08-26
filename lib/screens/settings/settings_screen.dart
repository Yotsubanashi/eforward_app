import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/screens/auth/change_password_screen.dart';
import 'package:eforward_app/screens/auth/login_screen.dart';
import 'package:eforward_app/screens/legal/privacy_policy_screen.dart';
import 'package:eforward_app/screens/settings/edit_profile_screen.dart';
import 'package:eforward_app/screens/settings/security_screen.dart';
import 'package:eforward_app/widgets/bottom_navigator.dart';
import 'package:eforward_app/services/api/auth_api.dart';
import 'package:eforward_app/services/session_service.dart';
import 'package:eforward_app/widgets/loading_overlay.dart';
import 'package:eforward_app/services/notifications/fcm_token_service.dart';
import 'package:eforward_app/services/notifications/notifications_service.dart';
import 'package:eforward_app/services/privacy_cover_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final int _selectedIndex = 3;

  String _firstName = '';
  String _middleName = '';
  String _lastName = '';
  String _email = '';
  String _employeeId = '';
  bool _isLoading = true;
  bool _isLoggingOut = false;

  String get _displayName =>
      '$_firstName${_middleName.isNotEmpty ? ' $_middleName' : ''} $_lastName'
          .trim();

  String get _initials {
    final f = _firstName.isNotEmpty ? _firstName[0].toUpperCase() : '';
    final l = _lastName.isNotEmpty ? _lastName[0].toUpperCase() : '';
    return '$f$l';
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataStr = prefs.getString('user_data');

    if (userDataStr != null && userDataStr.isNotEmpty) {
      try {
        final Map<String, dynamic> full = jsonDecode(userDataStr);

        final userData = SessionService.normalizeUser(full);

        debugPrint('Settings loaded user: $userData');

        setState(() {
          _firstName =
              userData['fname'] ??
              userData['first_name'] ??
              userData['firstName'] ??
              '';
          _middleName =
              userData['mname'] ??
              userData['middle_name'] ??
              userData['middleName'] ??
              '';
          _lastName =
              userData['lname'] ??
              userData['last_name'] ??
              userData['lastName'] ??
              '';
          _email = userData['email_add'] ?? userData['email'] ?? '';
          _employeeId =
              userData['employee_id'] ??
              userData['employeeId'] ??
              userData['emp_id'] ??
              '';
          _isLoading = false;
        });
      } catch (e) {
        debugPrint('Error loading user data: $e');
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    // Avoid double taps while the logout request is in flight.
    if (_isLoggingOut) return;
    setState(() => _isLoggingOut = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? userId = prefs.getString('employee_id');

      if (userId != null && userId.isNotEmpty) {
        // 1. Specifically remove FCM token from database
        await FCMTokenService.removeToken(userId);
      }

      // 2. Call Auth API logout for full session cleanup (includes clearing local prefs)
      await AuthApi().logout();

      // 3. Sign out from Firebase Auth
      await FirebaseAuth.instance.signOut();

      // 4. Reset notifications
      NotificationsService().reset();

      debugPrint('✅ Logout successful - FCM token and local session cleared');

      // Session is gone — drop the background/app-switcher cover so the login
      // screen isn't hidden behind it on the next backgrounding.
      await PrivacyCoverService.sync();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } catch (e) {
      debugPrint('❌ Logout error: $e');
      // If error occurs, still try to clear session and redirect
      await AuthApi().clearSession();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.white,
          bottomNavigationBar: BottomNavigator(
            selectedIndex: _selectedIndex,
            onTap: (_) {},
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 20,
                    ),
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

                  const SizedBox(height: 40),

                  // Profile Section
                  Center(
                    child: _isLoading
                        ? const SizedBox.shrink()
                        : Column(
                            children: [
                              // Initials Avatar
                              CircleAvatar(
                                radius: 60,
                                backgroundColor: Colors.black,
                                child: Text(
                                  _initials.isNotEmpty ? _initials : '?',
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 3,
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Full Name
                              Text(
                                _displayName.isNotEmpty ? _displayName : '—',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),

                              const SizedBox(height: 4),

                              // Email
                              if (_email.isNotEmpty)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.email_outlined,
                                      size: 13,
                                      color: Colors.black38,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _email,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black45,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ],
                                ),

                              const SizedBox(height: 4),

                              // Employee ID
                              if (_employeeId.isNotEmpty)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.badge_outlined,
                                      size: 13,
                                      color: Colors.black38,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _employeeId,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black45,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                  ),

                  const SizedBox(height: 32),
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),

                  // Edit Profile
                  _buildMenuItem(
                    context,
                    icon: Icons.person_outline,
                    iconColor: const Color(0xFFCC0000),
                    label: "ACCOUNT",
                    title: "EDIT PROFILE",
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Color(0xFFAAAAAA),
                      size: 20,
                    ),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const EditProfileScreen(),
                        ),
                      );
                      if (mounted) {
                        _loadUserData();
                      }
                    },
                  ),

                  const Divider(height: 1, color: Color(0xFFEEEEEE)),

                  // Change Password
                  _buildMenuItem(
                    context,
                    icon: Icons.lock_outline,
                    iconColor: const Color(0xFFCC0000),
                    label: "SECURITY",
                    title: "CHANGE PASSWORD",
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Color(0xFFAAAAAA),
                      size: 20,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ChangePasswordScreen(),
                      ),
                    ),
                  ),

                  const Divider(height: 1, color: Color(0xFFEEEEEE)),

                  _buildMenuItem(
                    context,
                    icon: Icons.security,
                    iconColor: const Color(0xFFCC0000),
                    label: "AUTHENTICATION",
                    title: "SECURITY SETTINGS",
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Color(0xFFAAAAAA),
                      size: 20,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SecurityScreen()),
                    ),
                  ),

                  const Divider(height: 1, color: Color(0xFFEEEEEE)),

                  // Privacy Policy
                  _buildMenuItem(
                    context,
                    icon: Icons.privacy_tip_outlined,
                    iconColor: const Color(0xFFCC0000),
                    label: "LEGAL",
                    title: "PRIVACY POLICY",
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Color(0xFFAAAAAA),
                      size: 20,
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyScreen(),
                      ),
                    ),
                  ),

                  const Divider(height: 1, color: Color(0xFFEEEEEE)),

                  // Logout
                  // Logout
                  _buildMenuItem(
                    context,
                    icon: Icons.logout,
                    iconColor: const Color(0xFF555555),
                    label: "SESSION MANAGEMENT",
                    title: "LOGOUT",
                    onTap: _logout,
                  ),

                  const Divider(height: 1, color: Color(0xFFEEEEEE)),

                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Align(
                      alignment: Alignment.center,
                      child: FutureBuilder(
                        future: PackageInfo.fromPlatform(),
                        builder: (context, snapshot) {
                          final version = snapshot.hasData
                              ? 'Version ${snapshot.data!.version}'
                              : 'Loading...';
                          return Text(
                            version,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFAAAAAA),
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_isLoading || _isLoggingOut) const LoadingOverlay(),
      ],
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String title,
    Widget? trailing, // ← now optional
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
            if (trailing != null) trailing, // ← only renders if provided
          ],
        ),
      ),
    );
  }
}
