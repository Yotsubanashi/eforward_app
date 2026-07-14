import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_env.dart';
import '../../services/api/auth_api.dart';
import '../../services/notifications/fcm_token_service.dart';
import '../../services/secure_unlock_service.dart';
import '../../validators/email_validator.dart';
import '../../validators/required_field_validator.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/loading_overlay.dart';
import '../dashboard/dashboard_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;

  final AuthApi _authApi = AuthApi();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Single unified build: the login logo uses the env default branding; the
  // per-user backend is chosen from the email domain at login time.
  final Map<String, String> _branding = AppEnv.defaultBranding;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  void _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('remember_me') ?? false) {
      _emailController.text = prefs.getString('saved_email') ?? '';
      setState(() => _rememberMe = true);
    }
  }

  void _saveRememberMe(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', _rememberMe);
    _rememberMe
        ? await prefs.setString('saved_email', email)
        : await prefs.remove('saved_email');
  }

  bool _isEmailAllowedForCurrentBrand(String email) {
    // Unified single build: allow both Ardent and Versatech institutional
    // domains. The correct backend is chosen from the domain at login time.
    return EmailValidator.isKnownInstitutionalDomain(email);
  }

  String? _extractAccountStatus(Map<String, dynamic>? data) {
    if (data == null) return null;

    String? readStatus(Map<String, dynamic>? source) {
      if (source == null) return null;
      const candidateKeys = ['status', 'account_status', 'accountStatus'];
      for (final key in candidateKeys) {
        final value = source[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim().toUpperCase();
        }
      }
      return null;
    }

    final topLevelStatus = readStatus(data);
    if (topLevelStatus != null) return topLevelStatus;

    final nestedUser = data['user'];
    if (nestedUser is Map<String, dynamic>) {
      final nestedStatus = readStatus(nestedUser);
      if (nestedStatus != null) return nestedStatus;
    }

    final nestedData = data['data'];
    if (nestedData is Map<String, dynamic>) {
      final nestedStatus = readStatus(nestedData);
      if (nestedStatus != null) return nestedStatus;
    }

    return null;
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (RequiredFieldValidator.anyEmpty([email, password])) {
      AppSnackbar.error(context, 'Email and password are required.');
      return;
    }

    if (!_isEmailAllowedForCurrentBrand(email)) {
      AppSnackbar.error(context, 'No user found.');
      return;
    }

    setState(() => _isLoading = true);

    // Route this login — and the whole session — to the correct backend based
    // on the email domain (Ardent vs Versatech).
    await AppEnv.selectBackendForEmail(email);

    final result = await _authApi.login(email: email, password: password);

    if (!mounted) return;

    if (!result.isSuccess) {
      debugPrint('Login failed [${result.statusCode}]: ${result.message}');
      setState(() => _isLoading = false);
      AppSnackbar.error(context, result.message);
      return;
    }

    final status = _extractAccountStatus(result.data);
    final inactiveStatuses = <String>{
      'ITV',
      'INACTIVE',
      'INA',
      'DISABLED',
      'DEACTIVATED',
      'SUSPENDED',
      'BLOCKED',
    };

    if (status != null && inactiveStatuses.contains(status)) {
      setState(() => _isLoading = false);
      AppSnackbar.error(
        context,
        'Your account is inactive. Please contact support.',
      );
      return;
    }

    _saveRememberMe(email);
    debugPrint('Login success: ${result.data}');

    final token =
        result.data?['accessToken'] ??
        result.data?['access_token'] ??
        result.data?['token'];
    final refreshToken =
        result.data?['refreshToken'] ?? result.data?['refresh_token'];

    if (token != null && token.toString().isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', token.toString());
      if (refreshToken != null && refreshToken.toString().isNotEmpty) {
        await prefs.setString('refresh_token', refreshToken.toString());
      }
      if (result.data != null) {
        await prefs.setString('user_data', jsonEncode(result.data));

        final user = result.data!['user'] is Map
            ? result.data!['user']
            : result.data;
        final userId =
            user['id']?.toString() ??
            user['employee_id']?.toString() ??
            user['employeeId']?.toString();

        if (userId != null) {
          await prefs.setString('employee_id', userId);
          await FCMTokenService.registerToken(userId);
        }
      }
    }

    if (!mounted) return;

    final isUnlocked = await SecureUnlockService.authenticateAfterLogin();
    if (!mounted) return;
    if (!isUnlocked) {
      setState(() => _isLoading = false);
      AppSnackbar.error(
        context,
        'Authentication cancelled. Please login again.',
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DashboardPage(userData: result.data),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _authApi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),

                    // Logo
                    Center(
                      child: Column(
                        children: [
                          Image.asset(
                            _branding['logo']!,
                            width: 280,
                            height: 120,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              debugPrint('❌ Logo load error: $error');
                              return const Icon(
                                Icons.shield_outlined,
                                color: Color(0xFFCC0000),
                                size: 60,
                              );
                            },
                          ),
                          const SizedBox(height: 15),
                          Text(
                            _branding['name']!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Email Field
                    const Text(
                      "EMAIL",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        hintText: "ENTER EMAIL ADDRESS",
                        hintStyle: TextStyle(
                          color: Colors.black26,
                          fontSize: 12,
                        ),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black26),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFCC0000)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Password Field
                    const Text(
                      "PASSWORD",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      // Prevent the keyboard's suggestion strip / autocorrect
                      // from echoing the typed characters. Combined with
                      // obscureText this keeps the password fully hidden unless
                      // the user taps the eye icon.
                      enableSuggestions: false,
                      autocorrect: false,
                      keyboardType: _obscurePassword
                          ? TextInputType.visiblePassword
                          : TextInputType.text,
                      decoration: InputDecoration(
                        hintText: "ENTER PASSWORD",
                        hintStyle: const TextStyle(
                          color: Colors.black26,
                          fontSize: 12,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: Colors.black38,
                            size: 20,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.black26),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFCC0000)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Remember Me Checkbox — whole row is tappable so the label
                    // toggles the checkbox too (larger, more reliable target).
                    InkWell(
                      onTap: _isLoading
                          ? null
                          : () => setState(() => _rememberMe = !_rememberMe),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: Checkbox(
                                value: _rememberMe,
                                onChanged: _isLoading
                                    ? null
                                    : (val) => setState(
                                        () => _rememberMe = val ?? false,
                                      ),
                                activeColor: const Color(0xFFCC0000),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                side: const BorderSide(
                                  color: Colors.black38,
                                  width: 1.5,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              "Remember Me",
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Login Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _handleLogin,
                        icon: const Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                        ),
                        label: const Text(
                          "LOGIN",
                          style: TextStyle(
                            color: Colors.white,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFCC0000),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Forgot Password
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        ),
                        child: const Text(
                          "FORGOT PASSWORD",
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_isLoading) const LoadingOverlay(),
      ],
    );
  }
}
