import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/pages/auth/change_password.dart';
import 'package:eforward_app/pages/auth/login.dart';
import 'package:eforward_app/components/bottom_navigator.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final int _selectedIndex = 3;
  File? _profileImage;

  // 👇 Loaded from API via SharedPreferences
  String _firstName = '';
  String _middleName = '';
  String _lastName = '';
  String _email = '';
  String _employeeId = '';
  String _role = '';
  bool _isLoading = true;

  String get _displayName =>
      '$_firstName${_middleName.isNotEmpty ? ' $_middleName' : ''} $_lastName'
          .trim();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // 👇 Load credentials from SharedPreferences (saved during OTP login)
  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataStr = prefs.getString('user_data');

    if (userDataStr != null && userDataStr.isNotEmpty) {
      try {
        final Map<String, dynamic> full = jsonDecode(userDataStr);
        // Support both nested 'data' and flat structure
        final userData = (full['data'] is Map<String, dynamic>)
            ? full['data'] as Map<String, dynamic>
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

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _profileImage = File(picked.path));
  }

  void _showEditProfileSheet() {
    final firstNameController = TextEditingController(text: _firstName);
    final middleNameController = TextEditingController(text: _middleName);
    final lastNameController = TextEditingController(text: _lastName);
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

              // Avatar picker
              Center(
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: () async {
                        final picked = await ImagePicker().pickImage(
                          source: ImageSource.gallery,
                        );
                        if (picked != null) {
                          setSheetState(() {});
                          setState(() => _profileImage = File(picked.path));
                        }
                      },
                      child: Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F0F0),
                          border: Border.all(
                            color: const Color(0xFFDDDDDD),
                            width: 1.5,
                          ),
                        ),
                        child: _profileImage != null
                            ? Image.file(_profileImage!, fit: BoxFit.cover)
                            : const Icon(
                                Icons.person,
                                size: 40,
                                color: Color(0xFF999999),
                              ),
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 26,
                        height: 26,
                        color: const Color(0xFFCC0000),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
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

              // Read-only fields from API
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
                  onPressed: () async {
                    if (firstNameController.text.trim().isNotEmpty) {
                      _firstName = firstNameController.text.trim();
                    }
                    if (middleNameController.text.trim().isNotEmpty) {
                      _middleName = middleNameController.text.trim();
                    }
                    if (lastNameController.text.trim().isNotEmpty) {
                      _lastName = lastNameController.text.trim();
                    }

                    // 👇 Save updated name back to SharedPreferences
                    final prefs = await SharedPreferences.getInstance();
                    final userDataStr = prefs.getString('user_data');
                    if (userDataStr != null) {
                      try {
                        final Map<String, dynamic> full = jsonDecode(
                          userDataStr,
                        );
                        final userData = (full['data'] is Map)
                            ? full['data'] as Map<String, dynamic>
                            : full;
                        userData['fname'] = _firstName;
                        userData['mname'] = _middleName;
                        userData['lname'] = _lastName;
                        await prefs.setString('user_data', jsonEncode(full));
                        debugPrint('Profile saved to SharedPreferences');
                      } catch (e) {
                        debugPrint('Error saving profile: $e');
                      }
                    }

                    setState(() {});
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFCC0000),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
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

            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            const SizedBox(height: 24),

            // Profile Section
            Center(
              child: _isLoading
                  ? const CircularProgressIndicator(color: Color(0xFFCC0000))
                  : Column(
                      children: [
                        // Avatar
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
                          child: _profileImage != null
                              ? Image.file(_profileImage!, fit: BoxFit.cover)
                              : const Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Color(0xFF999999),
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

                        // Role
                        if (_role.isNotEmpty)
                          Text(
                            _role,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF555555),
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),

                        const SizedBox(height: 10),

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
              onTap: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              ),
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
}
