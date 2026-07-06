import 'package:flutter/material.dart';
import '../../services/api/auth_api.dart';
import '../../validators/password_validator.dart';
import '../../validators/required_field_validator.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/eforward_app_bar.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/section_label.dart';
import 'login_screen.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? token;

  const ResetPasswordScreen({super.key, this.token});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final AuthApi _authApi = AuthApi();
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  bool _isVerifying = true;
  bool _isTokenValid = false;
  String _errorMessage = '';

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
    _verifyResetToken();
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _authApi.dispose();
    super.dispose();
  }

  Future<void> _verifyResetToken() async {
    if (widget.token == null || widget.token!.isEmpty) {
      setState(() {
        _isVerifying = false;
        _isTokenValid = false;
        _errorMessage =
            'No reset token provided. Please use the link from your email.';
      });
      return;
    }

    final result = await _authApi.verifyResetToken(token: widget.token!);

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _isVerifying = false;
        _isTokenValid = true;
      });
    } else {
      setState(() {
        _isVerifying = false;
        _isTokenValid = false;
        _errorMessage = result.message;
      });
    }
  }

  Future<void> _resetPassword() async {
    if (RequiredFieldValidator.anyEmpty([
      _newPasswordController.text,
      _confirmPasswordController.text,
    ])) {
      AppSnackbar.error(context, "Please fill in all fields.");
      return;
    }

    if (_newPasswordController.text != _confirmPasswordController.text) {
      AppSnackbar.error(context, "Passwords do not match.");
      return;
    }

    if (!PasswordValidator.meetsRequirements(_newPasswordController.text)) {
      AppSnackbar.error(
        context,
        "Password does not meet security requirements.",
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authApi.resetPasswordWithToken(
      token: widget.token!,
      newPassword: _newPasswordController.text,
    );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result.isSuccess) {
      AppSnackbar.success(context, "Password reset successful!");
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } else {
      AppSnackbar.error(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while verifying token
    if (_isVerifying) {
      return const Stack(
        children: [
          Scaffold(backgroundColor: Color(0xFFF8F8F8)),
          LoadingOverlay(),
        ],
      );
    }

    // Show error if token is invalid
    if (!_isTokenValid) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F8F8),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFCC0000),
                  size: 48,
                ),
                const SizedBox(height: 24),
                const Text(
                  'LINK EXPIRED OR INVALID',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                    letterSpacing: 1,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  _errorMessage,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                      (route) => false,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFCC0000),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'BACK TO LOGIN',
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

    // Normal reset password form
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF8F8F8),
          appBar: EForwardAppBar(
            title: "SECURITY",
            backgroundColor: const Color(0xFFF8F8F8),
            onBackPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),

                // Title
                const Text(
                  "CREATE NEW\nPASSWORD",
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
                  "Your new password must be unique and adhere to institutional security protocols to protect your institutional assets.",
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black45,
                    height: 1.6,
                  ),
                ),

                const SizedBox(height: 28),

                // New Password Label
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

                // New Password Field
                TextField(
                  controller: _newPasswordController,
                  obscureText: _obscureNew,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1A1A1A),
                  ),
                  decoration: InputDecoration(
                    hintText: "• • • • • • • •",
                    hintStyle: const TextStyle(
                      color: Colors.black26,
                      fontSize: 13,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNew
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                        color: Colors.black38,
                      ),
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.black26),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFCC0000)),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Confirm Password Label
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

                // Confirm Password Field
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF1A1A1A),
                  ),
                  decoration: InputDecoration(
                    hintText: "• • • • • • • •",
                    hintStyle: const TextStyle(
                      color: Colors.black26,
                      fontSize: 13,
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirm
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 18,
                        color: Colors.black38,
                      ),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.black26),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFFCC0000)),
                    ),
                  ),
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

                // Reset Password Button
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _resetPassword,
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
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "RESET PASSWORD",
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

                const SizedBox(height: 24),

                // Account Protection Notice
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      left: BorderSide(
                        color: const Color(0xFFCC0000),
                        width: 3,
                      ),
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
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
        ),
        if (_isLoading) const LoadingOverlay(),
      ],
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
