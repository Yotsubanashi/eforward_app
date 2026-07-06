import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/screens/settings/settings_screen.dart';
import 'package:eforward_app/services/api/auth_api.dart';
import 'package:eforward_app/screens/auth/login_screen.dart';
import 'package:eforward_app/widgets/loaders.dart';
import 'package:eforward_app/validators/password_validator.dart';
import 'package:eforward_app/validators/required_field_validator.dart';
import 'package:eforward_app/constants/shared_prefs_keys.dart';
import 'package:eforward_app/widgets/app_snackbar.dart';
import 'package:eforward_app/widgets/section_label.dart';
import 'package:eforward_app/widgets/eforward_app_bar.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final AuthApi _authApi = AuthApi();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _isSuccess = false;

  // Security requirements
  bool get _hasMinLength =>
      PasswordValidator.hasMinLength(_newPasswordController.text);
  bool get _hasNumber =>
      PasswordValidator.hasNumber(_newPasswordController.text);
  bool get _hasSpecialChar =>
      PasswordValidator.hasSpecialChar(_newPasswordController.text);
  bool get _hasMixedCase =>
      PasswordValidator.hasMixedCase(_newPasswordController.text);

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _authApi.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final currentPw = _currentPasswordController.text.trim();
    final newPw = _newPasswordController.text.trim();
    final confirmPw = _confirmPasswordController.text.trim();

    // Validations
    if (RequiredFieldValidator.anyEmpty([currentPw, newPw, confirmPw])) {
      _showSnackbar("Please fill in all fields.");
      return;
    }

    if (newPw != confirmPw) {
      _showSnackbar("New passwords do not match.");
      return;
    }

    if (!_hasMinLength || !_hasNumber || !_hasSpecialChar || !_hasMixedCase) {
      _showSnackbar("Password does not meet security requirements.");
      return;
    }

    LoadingDialog.show(context, message: "UPDATING PASSWORD...");

    // Get token
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(SharedPrefsKeys.accessToken) ?? '';

    if (token.isEmpty) {
      if (mounted) LoadingDialog.hide(context);
      _showSnackbar("Session expired. Please log in again.");
      return;
    }

    // Call API with all 3 fields matching the payload
    final result = await _authApi.changePassword(
      token: token,
      currentPassword: currentPw,
      newPassword: newPw,
      confirmPassword: confirmPw,
    );

    if (!mounted) return;
    LoadingDialog.hide(context);

    if (result.isSuccess) {
      setState(() {
        _isSuccess = true;
      });
      AppSnackbar.success(context, "Password updated successfully");
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } else {
      _showSnackbar(result.message);
    }
  }

  void _showSnackbar(String message, {bool isError = true}) {
    if (isError) {
      AppSnackbar.error(context, message);
    } else {
      AppSnackbar.success(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: EForwardAppBar(
        title: "SECURITY",
        backgroundColor: const Color(0xFFF8F8F8),
        onBackPressed: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // Title
                const Text(
                  "CHANGE\nPASSWORD",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                    height: 1.1,
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
                  "Update your security credentials. Your new password must adhere to institutional security protocols.",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black45,
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 28),

                // Current Password
                const Text(
                  "CURRENT PASSWORD",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                _buildPasswordField(
                  controller: _currentPasswordController,
                  obscure: _obscureCurrent,
                  onToggle: () =>
                      setState(() => _obscureCurrent = !_obscureCurrent),
                ),

                const SizedBox(height: 24),

                // New Password
                const Text(
                  "NEW PASSWORD",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                _buildPasswordField(
                  controller: _newPasswordController,
                  obscure: _obscureNew,
                  onToggle: () => setState(() => _obscureNew = !_obscureNew),
                ),

                const SizedBox(height: 24),

                // Confirm New Password
                const Text(
                  "CONFIRM NEW PASSWORD",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 8),
                _buildPasswordField(
                  controller: _confirmPasswordController,
                  obscure: _obscureConfirm,
                  onToggle: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),

                const SizedBox(height: 24),

                // Security Requirements Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: const Color(0xFFEEEEEE),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel(
                        "SECURITY REQUIREMENTS",
                        color: Color(0xFF1A1A1A),
                      ),
                      const SizedBox(height: 12),
                      _buildRequirement("At least 8 characters", _hasMinLength),
                      _buildRequirement("Include a number (0-9)", _hasNumber),
                      _buildRequirement(
                        "Special character (!@#\$)",
                        _hasSpecialChar,
                      ),
                      _buildRequirement("Mixed case (Aa)", _hasMixedCase),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Change Password Button
                Center(
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _changePassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFCC0000),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: const Text(
                        "CHANGE PASSWORD",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Cancel
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      "CANCEL AND RETURN TO PROFILE",
                      style: TextStyle(
                        color: Colors.black45,
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
      decoration: InputDecoration(
        hintText: "• • • • • • • •",
        hintStyle: const TextStyle(color: Colors.black26, fontSize: 13),
        suffixIcon: IconButton(
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            size: 18,
            color: Colors.black38,
          ),
          onPressed: onToggle,
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.black26),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFCC0000)),
        ),
      ),
    );
  }

  Widget _buildRequirement(String label, bool met) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: met ? const Color(0xFFCC0000) : Colors.transparent,
              border: Border.all(
                color: met ? const Color(0xFFCC0000) : Colors.black26,
                width: 1.5,
              ),
            ),
            child: met
                ? const Icon(Icons.check, size: 10, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: met ? const Color(0xFF1A1A1A) : Colors.black38,
              fontWeight: met ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
