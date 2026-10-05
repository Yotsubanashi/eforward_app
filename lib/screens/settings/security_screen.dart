import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_env.dart';
import '../../services/api/auth_api.dart';
import '../../services/biometric_credential_store.dart';
import '../../services/privacy_cover_service.dart';
import '../../services/secure_unlock_service.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/eforward_app_bar.dart';
import 'authenticator_setup_screen.dart';

/// Dedicated Security page reached from Settings. Groups the login-security
/// switches: biometric / fingerprint / PIN unlock, and two-factor auth.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _authenticatorEnabled = false;
  final AuthApi _authApi = AuthApi();

  /// Both switches depend on the device being able to authenticate the user.
  /// Without a screen lock there is no fallback for either one, so we say
  /// exactly what to fix — in the platform's own wording — rather than failing
  /// at the prompt.
  String get _noScreenLockMessage => SecureUnlockService.screenLockSetupMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-enable the switches without a restart once the user comes back from
    // adding a screen lock in device settings.
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final enabled = await SecureUnlockService.isEnabled();
    final available = await SecureUnlockService.isAvailable();
    final authenticator = await _readAuthenticatorEnabled();
    if (!mounted) return;
    setState(() {
      // Show what is actually stored, not what is currently usable. Masking a
      // stored "on" as "off" would leave the user unable to turn it back off.
      _biometricEnabled = enabled;
      _biometricAvailable = available;
      _authenticatorEnabled = authenticator;
      _loading = false;
    });
  }

  /// Whether the account has an authenticator (TOTP) enrolled — read from the
  /// persisted profile's `mfa_confirmed` flag (set by the backend /auth/me).
  Future<bool> _readAuthenticatorEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_data');
    if (raw == null) return false;
    try {
      final decoded = jsonDecode(raw);
      dynamic v;
      if (decoded is Map) {
        v = decoded['mfa_confirmed'];
        if (v == null && decoded['user'] is Map) v = decoded['user']['mfa_confirmed'];
        if (v == null && decoded['data'] is Map) v = decoded['data']['mfa_confirmed'];
      }
      return v == true || v == 1 || v == '1';
    } catch (_) {
      return false;
    }
  }

  /// Persists the authenticator state into the stored profile so the toggle
  /// still reads correctly after an app restart (it loads from `mfa_confirmed`).
  Future<void> _persistMfaConfirmed(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_data');
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final value = enabled ? 1 : 0;
      decoded['mfa_confirmed'] = value;
      if (decoded['user'] is Map) decoded['user']['mfa_confirmed'] = value;
      if (decoded['data'] is Map) decoded['data']['mfa_confirmed'] = value;
      await prefs.setString('user_data', jsonEncode(decoded));
    } catch (_) {
      // Non-fatal: the in-session toggle state still reflects the change.
    }
  }

  /// Opens enrollment (scan QR) when off, or disables (password re-auth) when on.
  Future<void> _onAuthenticatorTap() async {
    if (_authenticatorEnabled) {
      final email = await _currentSessionEmail() ?? '';
      final password = await _promptForPassword(
        email,
        title: 'DISABLE 2FA',
        message:
            'Enter your password to turn off two-factor authentication (authenticator app).',
      );
      if (password == null || password.isEmpty) return;
      final result = await _authApi.mfaDisable(password: password);
      if (!mounted) return;
      if (result.isSuccess) {
        await _persistMfaConfirmed(false);
        if (!mounted) return;
        setState(() => _authenticatorEnabled = false);
        AppSnackbar.success(context, 'Authenticator disabled.');
      } else {
        AppSnackbar.error(context, result.message);
      }
    } else {
      // Turning it ON: require the password first — same gate as enabling
      // biometric login — before opening the authenticator setup page.
      final email = await _currentSessionEmail();
      if (!mounted) return;
      if (email == null || email.isEmpty) {
        AppSnackbar.error(
          context,
          'Could not find your account email. Please log out and sign in again.',
        );
        return;
      }
      final password = await _promptForPassword(
        email,
        title: 'ENABLE 2FA',
        message:
            'Enter your password to set up two-factor authentication with Google or Microsoft Authenticator.',
      );
      if (!mounted) return;
      if (password == null || password.isEmpty) return; // cancelled

      await AppEnv.selectBackendForEmail(email);
      final verify = await _authApi.login(email: email, password: password);
      if (!mounted) return;
      if (!verify.isSuccess) {
        AppSnackbar.error(context, 'Incorrect password. Please try again.');
        return;
      }

      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const AuthenticatorSetupScreen()),
      );
      if (ok == true) {
        await _persistMfaConfirmed(true);
        if (!mounted) return;
        setState(() => _authenticatorEnabled = true);
      }
    }
  }

  Future<void> _onToggleBiometric(bool enabled) async {
    if (enabled && !_biometricAvailable) {
      AppSnackbar.error(context, _noScreenLockMessage);
      return;
    }

    // Turning it OFF: forget the securely-stored login so the biometric login
    // button can't reappear with stale credentials.
    if (!enabled) {
      await SecureUnlockService.setEnabled(false);
      await BiometricCredentialStore.clear();
      // Drop the background/app-switcher cover now that the lock is off.
      await PrivacyCoverService.sync();
      if (!mounted) return;
      setState(() => _biometricEnabled = false);
      return;
    }

    // Turning it ON: the login-screen biometric button replays a securely
    // stored email+password. Always capture and verify a fresh credential here
    // (don't trust a possibly-stale or lost keychain entry) so enabling the
    // toggle ALWAYS leaves a valid email+password stored — the Face ID button
    // can then sign in with no password prompt and no dead-ends.
    final armed = await _armCredentialWithPassword();
    // If the user cancelled or the password was wrong, leave the toggle OFF so
    // biometric login is never enabled without a stored credential.
    if (!armed) return;

    await SecureUnlockService.setEnabled(true);
    // Arm the background/app-switcher cover immediately so it protects the very
    // next backgrounding, without waiting for an app resume to refresh it.
    await PrivacyCoverService.sync();
    if (!mounted) return;
    setState(() => _biometricEnabled = true);
  }

  /// Captures the email+password used by biometric login when none is stored
  /// yet. Reads the email from the active session and asks the user to confirm
  /// their password once, verifies it against the backend, and — only on
  /// success — stores it in the secure enclave. Returns true when a credential
  /// was armed.
  Future<bool> _armCredentialWithPassword() async {
    final email = await _currentSessionEmail();
    if (!mounted) return false;
    if (email == null || email.isEmpty) {
      AppSnackbar.error(
        context,
        'Could not find your account email. Please log out and sign in again.',
      );
      return false;
    }

    final password = await _promptForPassword(
      email,
      title: 'ENABLE BIOMETRICS',
      message:
          'Enter the password for $email once to turn on biometric login. You won\'t need to type it again.',
    );
    if (!mounted) return false;
    if (password == null || password.isEmpty) return false; // cancelled

    // Route to the correct backend for this email, then verify the password.
    await AppEnv.selectBackendForEmail(email);
    final result = await _authApi.login(email: email, password: password);
    if (!mounted) return false;
    if (!result.isSuccess) {
      AppSnackbar.error(
        context,
        'Incorrect password. Biometric login was not enabled.',
      );
      return false;
    }

    await BiometricCredentialStore.save(email: email, password: password);
    // Also stash the refresh token so the Face ID button can restore the
    // session with no password replay at all (preferred path).
    final refreshToken =
        result.data?['refreshToken'] ?? result.data?['refresh_token'];
    if (refreshToken != null && refreshToken.toString().trim().isNotEmpty) {
      await BiometricCredentialStore.saveRefreshToken(refreshToken.toString());
    }
    if (mounted) {
      AppSnackbar.info(context, 'Biometric login is set up. You can now sign in without your password.');
    }
    return true;
  }

  /// Resolves the signed-in user's email from every place it might live, in
  /// order of reliability: the persisted `user_data` profile (searched across
  /// all of the backend's nestings), the remembered login email, and finally
  /// any email already armed for biometric login. Returning null here is what
  /// triggers the "Could not find your account email" error, so we cast a wide
  /// net before giving up.
  Future<String?> _currentSessionEmail() async {
    final prefs = await SharedPreferences.getInstance();

    // 1) The persisted profile. The backend nests the user under `data`, under
    // `user`, or flat, and the email key name has varied — so scan the whole
    // decoded payload rather than trusting a single shape.
    try {
      final raw = prefs.getString('user_data');
      if (raw != null) {
        final email = _findEmailDeep(jsonDecode(raw));
        if (email != null) return email;
      }
    } catch (e) {
      debugPrint('Read session email failed: $e');
    }

    // 2) The email typed at the last login (present when "remember me" was on).
    final saved = prefs.getString('saved_email')?.trim();
    if (saved != null && saved.isNotEmpty) return saved;

    // 3) An email already stored for biometric login, if any.
    final stored = (await BiometricCredentialStore.readEmail())?.trim();
    if (stored != null && stored.isNotEmpty) return stored;

    return null;
  }

  /// Recursively searches a decoded JSON node for an email under any of the
  /// known key names, at any nesting depth. Requires an '@' so a numeric or
  /// handle-style `username` isn't mistaken for an email address.
  static const _emailKeys = {
    'email',
    'email_address',
    'emailAddress',
    'user_email',
    'username',
  };
  String? _findEmailDeep(dynamic node) {
    if (node is Map) {
      for (final entry in node.entries) {
        if (_emailKeys.contains(entry.key)) {
          final v = entry.value?.toString().trim() ?? '';
          if (v.contains('@')) return v;
        }
      }
      for (final v in node.values) {
        final found = _findEmailDeep(v);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final v in node) {
        final found = _findEmailDeep(v);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Password confirmation dialog. [title] and [message] let each caller say
  /// what the password is for (enable biometrics, enable 2FA, …).
  Future<String?> _promptForPassword(
    String email, {
    String title = 'CONFIRM PASSWORD',
    String? message,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          _ConfirmPasswordDialog(email: email, title: title, message: message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const EForwardAppBar(
        title: "SECURITY",
        backgroundColor: Colors.white,
        showBrand: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _sectionLabel("LOGIN & AUTHENTICATION"),
                  _toggleTile(
                    icon: Icons.fingerprint,
                    title: "BIOMETRIC / FINGERPRINT / PIN UNLOCK",
                    subtitle: _biometricAvailable
                        ? "Use Face ID, fingerprint, or your device PIN as a quick way to log in."
                        : _noScreenLockMessage,
                    value: _biometricEnabled,
                    onChanged: _onToggleBiometric,
                    // Turning OFF must stay possible even with no screen lock,
                    // otherwise a stale "on" setting can never be cleared.
                    enabled: _biometricAvailable || _biometricEnabled,
                  ),
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),
                  _toggleTile(
                    icon: Icons.verified_user_outlined,
                    title: "TWO-FACTOR AUTHENTICATION",
                    subtitle:
                        "After your email and password, enter a 6-digit code from Google or Microsoft Authenticator each time you log in. Tap to ${_authenticatorEnabled ? 'turn off' : 'set up'}.",
                    value: _authenticatorEnabled,
                    onChanged: (_) => _onAuthenticatorTap(),
                    enabled: true,
                  ),
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),
                ],
              ),
            ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: [
          Container(width: 3, height: 14, color: const Color(0xFFCC0000)),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: Color(0xFFCC0000),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    // When disabled the row still taps through to [onChanged], which explains
    // what's missing — silently swallowing the tap would leave the user with no
    // idea why the switch won't move.
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                border: Border.all(color: const Color(0xFFEEEEEE)),
              ),
              child: Icon(
                icon,
                size: 18,
                color: enabled ? const Color(0xFFCC0000) : Colors.black26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: enabled ? const Color(0xFF1A1A1A) : Colors.black38,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black45,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeThumbColor: const Color(0xFFCC0000),
            ),
          ],
        ),
      ),
    );
  }
}

/// Password confirmation dialog for arming biometric login. This is a widget
/// rather than an inline `StatefulBuilder` so the controller's lifetime is tied
/// to the dialog's element: disposing it when `showDialog` returns would kill
/// the controller while the route's exit transition is still rebuilding the
/// TextField, which throws "A TextEditingController was used after being
/// disposed".
class _ConfirmPasswordDialog extends StatefulWidget {
  const _ConfirmPasswordDialog({
    required this.email,
    this.title = 'CONFIRM PASSWORD',
    this.message,
  });

  final String email;
  final String title;
  final String? message;

  @override
  State<_ConfirmPasswordDialog> createState() => _ConfirmPasswordDialogState();
}

class _ConfirmPasswordDialogState extends State<_ConfirmPasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) => Navigator.pop(context, value.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(),
      title: Text(
        widget.title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
          color: Color(0xFF1A1A1A),
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.message ??
                'Enter the password for ${widget.email} once to turn on biometric login. You won\'t need to type it again.',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            obscureText: _obscure,
            autofocus: true,
            onSubmitted: _submit,
            decoration: InputDecoration(
              hintText: 'Password',
              isDense: true,
              border: const OutlineInputBorder(),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFCC0000)),
              ),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                  color: Colors.black45,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text(
            'CANCEL',
            style: TextStyle(color: Colors.black54),
          ),
        ),
        TextButton(
          onPressed: () => _submit(_controller.text),
          child: const Text(
            'CONFIRM',
            style: TextStyle(
              color: Color(0xFFCC0000),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
