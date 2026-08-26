import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/constants/shared_prefs_keys.dart';
import 'package:eforward_app/services/api/auth_api.dart';
import 'package:eforward_app/services/session_service.dart';
import 'package:eforward_app/validators/required_field_validator.dart';
import 'package:eforward_app/widgets/app_snackbar.dart';
import 'package:eforward_app/widgets/eforward_app_bar.dart';
import 'package:eforward_app/widgets/loading_overlay.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

  final AuthApi _authApi = AuthApi();

  String _email = '';
  String _employeeId = '';
  String _role = '';
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _authApi.dispose();
    super.dispose();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final userDataStr = prefs.getString(SharedPrefsKeys.userData) ??
        prefs.getString('user_data');

    if (userDataStr != null && userDataStr.isNotEmpty) {
      try {
        final Map<String, dynamic> full = jsonDecode(userDataStr);
        final userData = SessionService.normalizeUser(full);

        final fname = (userData['fname'] ??
                userData['first_name'] ??
                userData['firstName'] ??
                '')
            .toString();
        final mname = (userData['mname'] ??
                userData['middle_name'] ??
                userData['middleName'] ??
                '')
            .toString();
        final lname = (userData['lname'] ??
                userData['last_name'] ??
                userData['lastName'] ??
                '')
            .toString();

        _firstNameController.text = fname;
        _middleNameController.text = mname;
        _lastNameController.text = lname;

        _email = (userData['email_add'] ??
                userData['email'] ??
                userData['emailAdd'] ??
                '')
            .toString();
        _employeeId = (userData['employee_id'] ??
                userData['employeeId'] ??
                userData['emp_id'] ??
                userData['id'] ??
                prefs.getString(SharedPrefsKeys.employeeId) ??
                prefs.getString('employee_id') ??
                '')
            .toString();
        _role = (userData['role'] ??
                userData['position'] ??
                '')
            .toString();

        if (mounted) {
          setState(() => _isLoading = false);
        }
      } catch (e) {
        debugPrint('Error loading profile data: $e');
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    final newFirst = _firstNameController.text.trim();
    final newMiddle = _middleNameController.text.trim();
    final newLast = _lastNameController.text.trim();

    if (RequiredFieldValidator.isEmpty(newFirst)) {
      AppSnackbar.error(context, "First name cannot be empty.");
      return;
    }

    if (RequiredFieldValidator.isEmpty(newLast)) {
      AppSnackbar.error(context, "Last name cannot be empty.");
      return;
    }

    setState(() => _isSaving = true);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(SharedPrefsKeys.accessToken) ??
        prefs.getString('access_token') ??
        '';

    final result = await _authApi.updateProfile(
      token: token,
      employeeId: _employeeId,
      fname: newFirst,
      mname: newMiddle,
      lname: newLast,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.isSuccess) {
      // Update local storage
      final userDataStr = prefs.getString(SharedPrefsKeys.userData) ??
          prefs.getString('user_data');
      if (userDataStr != null && userDataStr.isNotEmpty) {
        try {
          final Map<String, dynamic> full = jsonDecode(userDataStr);
          final userData = SessionService.normalizeUser(full);
          userData['fname'] = newFirst;
          userData['mname'] = newMiddle;
          userData['lname'] = newLast;
          userData['first_name'] = newFirst;
          userData['middle_name'] = newMiddle;
          userData['last_name'] = newLast;
          userData['firstName'] = newFirst;
          userData['middleName'] = newMiddle;
          userData['lastName'] = newLast;
          await prefs.setString(
            SharedPrefsKeys.userData,
            jsonEncode(full),
          );
        } catch (e) {
          debugPrint('Error saving updated profile cache: $e');
        }
      }

      if (!mounted) return;
      AppSnackbar.success(
        context,
        "Your profile has been updated successfully.",
      );
      Navigator.pop(context, true);
    } else {
      if (!mounted) return;
      AppSnackbar.error(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF8F8F8),
          appBar: EForwardAppBar(
            title: "ACCOUNT",
            backgroundColor: const Color(0xFFF8F8F8),
            showBrand: false,
            onBackPressed: () => Navigator.pop(context),
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                    child: _buildForm(),
                  ),
                ),
        ),
        if (_isSaving) const LoadingOverlay(),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          const SizedBox(height: 8),

          // Title
          const Text(
            "EDIT PROFILE",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              color: Color(0xFF1A1A1A),
            ),
          ),

          // Red underline accent
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 16),
            width: 40,
            height: 3,
            color: const Color(0xFFCC0000),
          ),

          // Subtitle
          const Text(
            "Update your personal details. Changes will reflect across your account and institutional records.",
            style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.6),
          ),

          const SizedBox(height: 28),

          _sectionHeader("PERSONAL INFORMATION"),

          const SizedBox(height: 16),

          // Editable name fields
          _buildField(
            label: "FIRST NAME",
            controller: _firstNameController,
            hint: "Enter first name",
          ),
          const SizedBox(height: 18),
          _buildField(
            label: "MIDDLE NAME (OPTIONAL)",
            controller: _middleNameController,
            hint: "Enter middle name",
          ),
          const SizedBox(height: 18),
          _buildField(
            label: "LAST NAME",
            controller: _lastNameController,
            hint: "Enter last name",
          ),

          const SizedBox(height: 32),

          _sectionHeader("ACCOUNT INFORMATION"),

          const SizedBox(height: 16),

          // Read-only fields
          _buildReadOnlyField("EMAIL ADDRESS", _email),
          const SizedBox(height: 18),
          _buildReadOnlyField("EMPLOYEE ID", _employeeId),
          const SizedBox(height: 18),
          _buildReadOnlyField("ROLE / POSITION", _role),

          const SizedBox(height: 32),

          // Save Changes Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCC0000),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: const Text(
                "SAVE CHANGES",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Cancel Button
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "CANCEL AND RETURN TO SETTINGS",
                style: TextStyle(
                  color: Colors.black45,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      );
  }

  Widget _sectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 14,
          color: const Color(0xFFCC0000),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: Color(0xFFCC0000),
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A1A),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.black26, fontSize: 13),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.black26),
            ),
            focusedBorder: const UnderlineInputBorder(
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
}
