import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_env.dart';
import '../../services/api/auth_api.dart';
import '../../services/biometric_credential_store.dart';
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

  // Biometric login button is shown only when the unlock toggle is on AND a
  // credential was stored on a previous biometric-enabled login. [_unlockMethod]
  // decides its label/icon (Face ID / Fingerprint / PIN) from the device.
  bool _biometricLoginAvailable = false;
  UnlockMethod _unlockMethod = UnlockMethod.pin;

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
    _refreshBiometricLogin();
    // Rebuild so the Login button enables/disables as the fields change.
    _emailController.addListener(_onCredentialsChanged);
    _passwordController.addListener(_onCredentialsChanged);
  }

  void _onCredentialsChanged() => setState(() {});

  /// Login is only allowed once both fields have content.
  bool get _canLogin =>
      _emailController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty;

  Future<void> _refreshBiometricLogin() async {
    final enabled = await SecureUnlockService.isEnabled();
    final hasCreds = await BiometricCredentialStore.hasCredentials();
    final method = await SecureUnlockService.resolveMethod();
    if (!mounted) return;
    setState(() {
      _biometricLoginAvailable = enabled && hasCreds;
      _unlockMethod = method;
    });
  }

  /// Face ID / Fingerprint / PIN as an alternate way to log in: authenticate on
  /// the device, then re-login with the securely-stored credentials.
  Future<void> _handleBiometricLogin() async {
    setState(() => _isLoading = true);

    final ok = await SecureUnlockService.authenticate(
      biometricOnly: _unlockMethod != UnlockMethod.pin,
      reason: 'Authenticate to log in to your account',
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _isLoading = false);
      AppSnackbar.error(context, 'Authentication failed. Please try again.');
      return;
    }

    final creds = await BiometricCredentialStore.read();
    if (!mounted) return;
    if (creds == null) {
      setState(() {
        _isLoading = false;
        _biometricLoginAvailable = false;
      });
      AppSnackbar.error(
        context,
        'No saved login found. Please log in with your password.',
      );
      return;
    }

    await AppEnv.selectBackendForEmail(creds.email);
    final result = await _authApi.login(
      email: creds.email,
      password: creds.password,
    );
    if (!mounted) return;

    if (!result.isSuccess) {
      // Stored credential no longer works (e.g. password changed) — drop it so
      // the button disappears and require a fresh password login.
      await BiometricCredentialStore.clear();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _biometricLoginAvailable = false;
      });
      AppSnackbar.error(
        context,
        'Saved login is no longer valid. Please log in with your password.',
      );
      return;
    }

    await _enterWithSession(
      result: result,
      email: creds.email,
      password: creds.password,
    );
  }

  /// Shared post-login persistence used by both password and biometric login:
  /// stores the session, (re)stores the biometric credential when the toggle is
  /// on, registers FCM, and enters the dashboard. Assumes the account-status
  /// check already passed. Returns nothing; navigates on success.
  Future<void> _enterWithSession({
    required AuthLoginResult result,
    required String email,
    required String password,
  }) async {
    // Block inactive accounts regardless of how they authenticated (password
    // or biometric).
    final status = _extractAccountStatus(result.data);
    if (status != null && _inactiveStatuses.contains(status)) {
      setState(() => _isLoading = false);
      AppSnackbar.error(
        context,
        'Your account is inactive. Please contact support.',
      );
      return;
    }

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

    // Persist (or refresh) the credential for biometric login when the toggle
    // is on; otherwise make sure nothing stale is left behind.
    if (await SecureUnlockService.isEnabled()) {
      await BiometricCredentialStore.save(email: email, password: password);
    } else {
      await BiometricCredentialStore.clear();
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DashboardPage(userData: result.data),
      ),
    );
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

    _saveRememberMe(email);
    debugPrint('Login success: ${result.data}');

    // Biometrics are an alternate login method, not a gate: a successful
    // password login enters directly (storing the credential for next time
    // when the unlock toggle is on).
    await _enterWithSession(result: result, email: email, password: password);
  }

  static const Set<String> _inactiveStatuses = {
    'ITV',
    'INACTIVE',
    'INA',
    'DISABLED',
    'DEACTIVATED',
    'SUSPENDED',
    'BLOCKED',
  };

  IconData get _unlockMethodIcon => switch (_unlockMethod) {
    UnlockMethod.face => Icons.face,
    UnlockMethod.fingerprint => Icons.fingerprint,
    UnlockMethod.pin => Icons.pin_outlined,
  };

  String get _unlockMethodLabel => switch (_unlockMethod) {
    UnlockMethod.face => "LOG IN WITH FACE ID",
    UnlockMethod.fingerprint => "LOG IN WITH FINGERPRINT",
    UnlockMethod.pin => "LOG IN WITH PIN",
  };

  Widget _buildUnlockButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: const Color(0xFFCC0000)),
        label: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFCC0000),
            fontSize: 12,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFCC0000)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.removeListener(_onCredentialsChanged);
    _passwordController.removeListener(_onCredentialsChanged);
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
                      // Use plain text input. TextInputType.visiblePassword
                      // asks the OS keyboard to render characters unmasked on
                      // Android, which defeated obscureText and briefly showed
                      // each typed letter. With plain text, obscureText fully
                      // masks the field to dots.
                      keyboardType: TextInputType.text,
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
                        onPressed: (_isLoading || !_canLogin)
                            ? null
                            : _handleLogin,
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
                          disabledBackgroundColor: const Color(
                            0xFFCC0000,
                          ).withOpacity(0.4),
                          disabledForegroundColor: Colors.white70,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    // Biometric login — an alternate way to sign in, shown only
                    // after a biometric-enabled login stored a credential. The
                    // method (Face ID / Fingerprint / PIN) follows the device.
                    if (_biometricLoginAvailable) ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          const Expanded(
                            child: Divider(color: Color(0xFFE8E8E8)),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              "OR LOG IN WITH",
                              style: TextStyle(
                                color: Colors.black38,
                                fontSize: 10,
                                letterSpacing: 1.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Expanded(
                            child: Divider(color: Color(0xFFE8E8E8)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildUnlockButton(
                        icon: _unlockMethodIcon,
                        label: _unlockMethodLabel,
                        onTap: _isLoading ? null : _handleBiometricLogin,
                      ),
                    ],

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
