import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/pages/auth/change_password.dart';
import 'package:eforward_app/pages/auth/login.dart';
import 'package:eforward_app/components/bottom_navigator.dart';
import 'package:eforward_app/services/auth_api.dart';
import 'package:eforward_app/services/fcm_token_service.dart';
import 'package:eforward_app/services/notifications_service.dart';
import 'package:eforward_app/services/secure_unlock_service.dart';

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
  String _role = '';
  bool _isLoading = true;
  bool _biometricUnlockEnabled = false;
  bool _biometricAvailable = false;

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
    _loadSecuritySettings();
  }

  Future<void> _loadSecuritySettings() async {
    final enabled = await SecureUnlockService.isEnabled();
    final available = await SecureUnlockService.isAvailable();
    if (!mounted) return;
    setState(() {
      _biometricUnlockEnabled = enabled && available;
      _biometricAvailable = available;
    });
  }

  Future<void> _onToggleBiometricUnlock(bool enabled) async {
    if (enabled && !_biometricAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Biometric unlock is not available on this device. Device PIN will be used when supported.',
          ),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }

    await SecureUnlockService.setEnabled(enabled);
    if (!mounted) return;
    setState(() => _biometricUnlockEnabled = enabled);
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataStr = prefs.getString('user_data');

    if (userDataStr != null && userDataStr.isNotEmpty) {
      try {
        final Map<String, dynamic> full = jsonDecode(userDataStr);

        final userData = (full['user'] is Map<String, dynamic>)
            ? full['user'] as Map<String, dynamic>
            : full;

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
          _role = userData['role'] ?? userData['position'] ?? '';
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

  void _showEditProfileSheet() {
    final firstNameController = TextEditingController(text: _firstName);
    final middleNameController = TextEditingController(text: _middleName);
    final lastNameController = TextEditingController(text: _lastName);
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "EDIT PROFILE",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Initials Avatar
              Center(
                child: CircleAvatar(
                  radius: 45,
                  backgroundColor: Colors.black,
                  child: Text(
                    _initials.isNotEmpty ? _initials : '?',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 2,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Editable name fields
              _buildSheetField("FIRST NAME", firstNameController),
              const SizedBox(height: 16),
              _buildSheetField("MIDDLE NAME", middleNameController),
              const SizedBox(height: 16),
              _buildSheetField("LAST NAME", lastNameController),
              const SizedBox(height: 16),

              // Read-only fields
              _buildReadOnlyField("EMAIL ADDRESS", _email),
              const SizedBox(height: 16),
              _buildReadOnlyField("EMPLOYEE ID", _employeeId),
              const SizedBox(height: 16),
              _buildReadOnlyField("ROLE", _role),
              const SizedBox(height: 28),

              // Save button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final newFirst = firstNameController.text.trim();
                          final newMiddle = middleNameController.text.trim();
                          final newLast = lastNameController.text.trim();

                          setSheetState(() => isSaving = true);

                          final prefs = await SharedPreferences.getInstance();
                          final token = prefs.getString('access_token') ?? '';

                          final api = AuthApi();
                          final result = await api.updateProfile(
                            token: token,
                            employeeId: _employeeId,
                            fname: newFirst.isNotEmpty ? newFirst : _firstName,
                            mname: newMiddle.isNotEmpty
                                ? newMiddle
                                : _middleName,
                            lname: newLast.isNotEmpty ? newLast : _lastName,
                          );

                          setSheetState(() => isSaving = false);

                          if (result.isSuccess) {
                            if (newFirst.isNotEmpty) _firstName = newFirst;
                            if (newMiddle.isNotEmpty) _middleName = newMiddle;
                            if (newLast.isNotEmpty) _lastName = newLast;

                            final userDataStr = prefs.getString('user_data');
                            if (userDataStr != null) {
                              try {
                                final Map<String, dynamic> full = jsonDecode(
                                  userDataStr,
                                );
                                final userData = (full['user'] is Map)
                                    ? full['user'] as Map<String, dynamic>
                                    : full;
                                userData['fname'] = _firstName;
                                userData['mname'] = _middleName;
                                userData['lname'] = _lastName;
                                await prefs.setString(
                                  'user_data',
                                  jsonEncode(full),
                                );
                              } catch (e) {
                                debugPrint('Error saving profile cache: $e');
                              }
                            }

                            setState(() {});
                            Navigator.pop(context);

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Profile updated successfully.'),
                                backgroundColor: Color(0xFF2E7D32),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(result.message),
                                backgroundColor: const Color(0xFFCC0000),
                              ),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCC0000),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          "SAVE CHANGES",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSheetField(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: Colors.black45,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.black26),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFCC0000)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: Colors.black45,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          enabled: false,
          controller: TextEditingController(
            text: value.isNotEmpty ? value : '—',
          ),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black38,
          ),
          decoration: const InputDecoration(
            disabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.black12),
            ),
            suffixIcon: Icon(
              Icons.lock_outline,
              size: 14,
              color: Colors.black26,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _logout() async {
    try {
      await FCMTokenService.clearSavedToken();

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('access_token');
      await prefs.remove('refresh_token');
      await prefs.remove('user_data');

      NotificationsService().reset();

      debugPrint('✅ Logout successful - FCM token cleared');

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    } catch (e) {
      debugPrint('❌ Logout error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Logout error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      bottomNavigationBar: BottomNavigator(
        selectedIndex: _selectedIndex,
        onTap: (_) {},
      ),
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

            const SizedBox(height: 40),

            // Profile Section
            Center(
              child: _isLoading
                  ? const CircularProgressIndicator(color: Color(0xFFCC0000))
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
              onTap: _showEditProfileSheet,
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
                MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
              ),
            ),

            const Divider(height: 1, color: Color(0xFFEEEEEE)),

            _buildMenuItem(
              context,
              icon: Icons.fingerprint,
              iconColor: const Color(0xFFCC0000),
              label: "SECURITY",
              title: "BIOMETRIC/PIN UNLOCK",
              trailing: Switch(
                value: _biometricUnlockEnabled,
                onChanged: _onToggleBiometricUnlock,
                activeThumbColor: const Color(0xFFCC0000),
              ),
              onTap: () => _onToggleBiometricUnlock(!_biometricUnlockEnabled),
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
          ],
        ),
      ),
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
