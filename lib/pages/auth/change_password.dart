import 'package:flutter/material.dart';
import 'login.dart'; // 👈 import your login screen

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

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  // Security requirements
  bool get _hasMinLength => _newPasswordController.text.length >= 8;
  bool get _hasNumber => _newPasswordController.text.contains(RegExp(r'[0-9]'));
  bool get _hasSpecialChar =>
      _newPasswordController.text.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
  bool get _hasMixedCase =>
      _newPasswordController.text.contains(RegExp(r'[A-Z]')) &&
      _newPasswordController.text.contains(RegExp(r'[a-z]'));

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
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_currentPasswordController.text.isEmpty ||
        _newPasswordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill in all fields."),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("New passwords do not match."),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }

    if (!_hasMinLength || !_hasNumber || !_hasSpecialChar || !_hasMixedCase) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Password does not meet security requirements."),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    setState(() => _isLoading = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Password changed successfully!"),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8F8F8),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Color(0xFF1A1A1A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "SECURITY",
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
            color: Color(0xFF1A1A1A),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: const [
                Icon(Icons.shield_outlined, color: Color(0xFFCC0000), size: 16),
                SizedBox(width: 4),
                Text(
                  "E-FORWARD",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: Color(0xFFCC0000),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
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
                border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "SECURITY REQUIREMENTS",
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: Color(0xFF1A1A1A),
                    ),
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

            // Reset Password Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _changePassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCC0000),
                  disabledBackgroundColor: const Color(
                    0xFFCC0000,
                  ).withOpacity(0.7),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text(
                            "CHANGE PASSWORD",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                            size: 16,
                          ),
                        ],
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

            // Account Protection Notice
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                border: const Border(
                  left: BorderSide(color: Color(0xFFCC0000), width: 3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.account_circle_outlined,
                    color: Color(0xFFCC0000),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "ACCOUNT PROTECTION",
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          "Changing your password will sign you out of all other active sessions on multiple devices for your protection.",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
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
