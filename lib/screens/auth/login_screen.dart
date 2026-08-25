import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_env.dart';
import '../../services/api/auth_api.dart';
import '../../services/biometric_credential_store.dart';
import '../../services/notifications/fcm_token_service.dart';
import '../../services/privacy_cover_service.dart';
import '../../services/session_service.dart';
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

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    _loadRememberedEmail();
    _refreshBiometricLogin();
    // Rebuild so the Login button enables/disables as the fields change.
    _emailController.addListener(_onCredentialsChanged);
    _passwordController.addListener(_onCredentialsChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have left to add a screen lock in device settings after we
    // told them to; pick the button back up as soon as they return.
    if (state == AppLifecycleState.resumed) _refreshBiometricLogin();
  }

  void _onCredentialsChanged() => setState(() {});

  /// Login is only allowed once both fields have content.
  bool get _canLogin =>
      _emailController.text.trim().isNotEmpty &&
      _passwordController.text.isNotEmpty;

  Future<void> _refreshBiometricLogin() async {
    // Show the biometric icon when the unlock toggle is on AND the device can
    // still authenticate. The availability half matters because a screen lock
    // can be removed after the toggle was turned on — offering the button then
    // would dead-end, since there is nothing to fall back to once the user has
    // no PIN, pattern, password, or enrolled biometric.
    final enabled = await SecureUnlockService.isEnabled();
    final available = await SecureUnlockService.isAvailable();
    final method = await SecureUnlockService.resolveMethod();
    if (!mounted) return;
    setState(() {
      _biometricLoginAvailable = enabled && available;
      _unlockMethod = method;
    });
  }

  /// Face ID / Fingerprint / PIN as an alternate way to log in: authenticate on
  /// the device, then re-login with the securely-stored credentials.
  Future<void> _handleBiometricLogin() async {
    setState(() => _isLoading = true);

    final unlock = await SecureUnlockService.authenticate(
      biometricOnly: _unlockMethod != UnlockMethod.pin,
      reason: 'Authenticate to log in to your account',
    );
    if (!mounted) return;
    if (!unlock.success) {
      setState(() => _isLoading = false);
      // The OS already told the user why it rejected a cancel/bad scan; only
      // speak up when we have something they can act on.
      if (!unlock.cancelled) {
        AppSnackbar.error(context, unlock.message!);
      }
      return;
    }

    // Preferred path: restore the session straight from the stored refresh
    // token — no password, no dialog. This is the true "Face ID unlock".
    if (await _tryBiometricRefreshLogin()) return;
    if (!mounted) return;

    final creds = await BiometricCredentialStore.read();
    if (!mounted) return;
    if (creds == null) {
      // Face ID passed but there is no stored credential/token to log in with.
      // Enabling the toggle in Security Settings arms one, so this should not
      // happen — if it does, don't fall back to a password dialog. Surface an
      // error and stop; the user re-enables biometric login by signing in with
      // their password once.
      setState(() => _isLoading = false);
      AppSnackbar.error(
        context,
        'Biometric login is not set up. Log in with your email and password '
        'once to enable it.',
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

  /// Restores the session from a securely-stored refresh token so biometric
  /// login needs no password and shows no dialog. Returns true (and navigates
  /// into the dashboard) on success; false when there is no usable token or the
  /// backend rejected it, so the caller can fall back to the stored password.
  Future<bool> _tryBiometricRefreshLogin() async {
    final refreshToken = await BiometricCredentialStore.readRefreshToken();
    if (refreshToken == null) return false;

    // Route to the correct backend (Ardent vs Versatech) before hitting the
    // refresh endpoint. On a logged-out launch the active backend was cleared,
    // so without this the refresh could hit the wrong host and fail — dropping
    // us back to the password path. The email is stored alongside the token.
    final email = await BiometricCredentialStore.readEmail();
    if (email != null) await AppEnv.selectBackendForEmail(email);

    final result = await _authApi.refresh(token: refreshToken);
    if (!mounted || !result.isSuccess) return false;

    final newAccess =
        (result.data?['accessToken'] ??
                result.data?['access_token'] ??
                result.data?['token'])
            ?.toString()
            .trim();
    if (newAccess == null || newAccess.isEmpty) return false;
    final newRefresh =
        (result.data?['refreshToken'] ?? result.data?['refresh_token'])
            ?.toString()
            .trim();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', newAccess);
    if (newRefresh != null && newRefresh.isNotEmpty) {
      await prefs.setString('refresh_token', newRefresh);
      await BiometricCredentialStore.saveRefreshToken(newRefresh);
    }

    // Load the profile the dashboard needs.
    final me = await _authApi.getMe(token: newAccess);
    if (!mounted || !me.isSuccess || me.data == null) return false;

    await prefs.setString('user_data', jsonEncode(me.data));
    // /auth/me nests the user under `data` (login nests it under `user`);
    // normalizeUser resolves either shape so the employee id is found.
    final user = SessionService.normalizeUser(me.data!);
    final userId = SessionService.extractEmployeeId(user);
    if (userId != null) {
      await prefs.setString('employee_id', userId);
      await FCMTokenService.registerToken(userId);
    }

    // Arm the background/app-switcher cover for the new session before entering,
    // so it protects the first backgrounding without waiting for a resume.
    await PrivacyCoverService.sync();
    if (!mounted) return false;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => DashboardPage(userData: me.data)),
    );
    return true;
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

    // Remember the credential so biometric login works the moment the unlock
    // toggle is turned on (even if it's enabled later from Settings). It is
    // cleared when the toggle is turned off or the credential is rejected.
    await BiometricCredentialStore.save(email: email, password: password);
    // Also stash the refresh token so the biometric button can restore the
    // session with NO password prompt (preferred path). Falls back to the
    // stored password only if the token is expired/revoked.
    if (refreshToken != null && refreshToken.toString().trim().isNotEmpty) {
      await BiometricCredentialStore.saveRefreshToken(refreshToken.toString());
    }

    // Arm the background/app-switcher cover for the new session before entering,
    // so it protects the first backgrounding without waiting for a resume.
    await PrivacyCoverService.sync();
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
    // Open multi-tenant build: allow any email with a valid, routable domain.
    // Emails with no usable domain are rejected here; the backend for the
    // domain is derived at login time (AppEnv.selectBackendForEmail).
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

  // Public web pages opened from the login footer. Both are served by Firebase
  // Hosting (cleanUrls) from public/privacy.html and public/support.html, and
  // are the same URLs registered in App Store Connect / Play Console.
  static final Uri _privacyUrl =
      Uri.parse('https://eforward.ardentnetworks.com.ph/privacy');
  static final Uri _supportUrl =
      Uri.parse('https://eforward.ardentnetworks.com.ph/support');

  /// Opens [url] in the device browser, surfacing a snackbar if it can't launch.
  Future<void> _openUrl(Uri url) async {
    final launched = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      AppSnackbar.error(context, 'Could not open $url');
    }
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

    // Two-factor: when enabled, require a device biometric/PIN check as a second
    // factor after the password before entering. (Skipped for the biometric
    // login button, which is already a biometric factor.)
    //
    // Only enforce it while the device can still satisfy it. A user who enabled
    // two-factor and later removed their screen lock has no way to pass this
    // check and no way to reach Settings to turn it off — the correct password
    // would lock them out of their own account permanently. Their screen lock
    // is gone, so the second factor no longer exists: drop the stale flag and
    // let the password stand on its own.
    if (await SecureUnlockService.isTwoFactorEnabled() &&
        !await SecureUnlockService.isAvailable()) {
      await SecureUnlockService.setTwoFactorEnabled(false);
      debugPrint('Two-factor cleared: device no longer has a screen lock.');
    }

    if (await SecureUnlockService.isTwoFactorEnabled()) {
      final verified = await SecureUnlockService.authenticate(
        biometricOnly: false,
        reason: "Verify it's you to finish signing in",
      );
      if (!mounted) return;
      if (!verified.success) {
        setState(() => _isLoading = false);
        AppSnackbar.error(
          context,
          verified.message ??
              'Two-factor verification was cancelled. Please try again.',
        );
        return;
      }
    }

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
    UnlockMethod.pin => Icons.dialpad,
  };

  String get _unlockMethodShortLabel =>
      SecureUnlockService.labelFor(_unlockMethod);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emailController.removeListener(_onCredentialsChanged);
    _passwordController.removeListener(_onCredentialsChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _authApi.dispose();
    super.dispose();
  }

  /// A grey footer text link matching the Forgot Password style, sized to its
  /// label so two can sit side by side in a centered row without wrapping.
  Widget _footerLink(String label, {required VoidCallback onPressed}) {
    return TextButton(
      onPressed: _isLoading ? null : onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black54,
          fontSize: 12,
          letterSpacing: 1.5,
        ),
      ),
    );
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
                    // Biometric login — a tappable Face ID / Fingerprint / PIN
                    // icon shown whenever the unlock toggle is on (UnionBank
                    // style). The icon follows the device's enrolled method.
                    if (_biometricLoginAvailable) ...[
                      const SizedBox(height: 24),
                      Center(
                        child: GestureDetector(
                          onTap: _isLoading ? null : _handleBiometricLogin,
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFCC0000),
                                    width: 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _unlockMethodIcon,
                                  size: 30,
                                  color: const Color(0xFFCC0000),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _unlockMethodShortLabel,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Forgot Password — kept directly under the login button,
                    // its natural place.
                    Center(
                      child: TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.push(
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

                    const SizedBox(height: 24),

                    // "NEED AN ACCOUNT?" section label with divider rules — sets
                    // off the support/legal footer from the sign-in actions.
                    Row(
                      children: [
                        const Expanded(
                          child: Divider(
                            color: Color(0xFFEEEEEE),
                            thickness: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: const Text(
                            "NEED AN ACCOUNT?",
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const Expanded(
                          child: Divider(
                            color: Color(0xFFEEEEEE),
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Contact Support and Privacy Policy side by side, centered
                    // with a divider between them. Contact Support tells users
                    // (and App Store reviewers) how to obtain an account, since
                    // there is no self-signup; Privacy Policy must be reachable
                    // before login for store review. Both open hosted pages.
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _footerLink(
                          "CONTACT SUPPORT",
                          onPressed: () => _openUrl(_supportUrl),
                        ),
                        Container(
                          width: 1,
                          height: 12,
                          color: const Color(0xFFDDDDDD),
                        ),
                        _footerLink(
                          "PRIVACY POLICY",
                          onPressed: () => _openUrl(_privacyUrl),
                        ),
                      ],
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
