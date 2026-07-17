import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_env.dart';
import '../../services/api/auth_api.dart';
import '../../services/biometric_credential_store.dart';
import '../../services/secure_unlock_service.dart';
import '../../services/session_service.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/eforward_app_bar.dart';

/// Dedicated Security page reached from Settings. Groups the login-security
/// switches: biometric / fingerprint / PIN unlock, and two-factor auth.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool _loading = true;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _twoFactorEnabled = false;
  final AuthApi _authApi = AuthApi();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await SecureUnlockService.isEnabled();
    final available = await SecureUnlockService.isAvailable();
    final twoFactor = await SecureUnlockService.isTwoFactorEnabled();
    if (!mounted) return;
    setState(() {
      _biometricEnabled = enabled && available;
      _biometricAvailable = available;
      _twoFactorEnabled = twoFactor;
      _loading = false;
    });
  }

  Future<void> _onToggleBiometric(bool enabled) async {
    if (enabled && !_biometricAvailable) {
      AppSnackbar.error(
        context,
        'Biometric unlock is not available on this device. Device PIN will be used when supported.',
      );
      return;
    }

    // Turning it OFF: forget the securely-stored login so the biometric login
    // button can't reappear with stale credentials.
    if (!enabled) {
      await SecureUnlockService.setEnabled(false);
      await BiometricCredentialStore.clear();
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

    final password = await _promptForPassword(email);
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

  /// Pulls the signed-in user's email out of the persisted `user_data`.
  Future<String?> _currentSessionEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('user_data');
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final user = SessionService.normalizeUser(decoded);
      for (final key in [
        'email',
        'email_address',
        'emailAddress',
        'user_email',
        'username',
      ]) {
        final v = user[key];
        if (v != null && v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
    } catch (e) {
      debugPrint('Read session email failed: $e');
    }
    return null;
  }

  /// One-time password confirmation dialog used to arm biometric login.
  Future<String?> _promptForPassword(String email) async {
    final controller = TextEditingController();
    bool obscure = true;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: const RoundedRectangleBorder(),
              title: const Text(
                'CONFIRM PASSWORD',
                style: TextStyle(
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
                    'Enter the password for $email once to turn on biometric login. You won\'t need to type it again.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    autofocus: true,
                    onSubmitted: (v) => Navigator.pop(dialogContext, v.trim()),
                    decoration: InputDecoration(
                      hintText: 'Password',
                      isDense: true,
                      border: const OutlineInputBorder(),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFFCC0000)),
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          size: 18,
                          color: Colors.black45,
                        ),
                        onPressed: () => setLocal(() => obscure = !obscure),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, null),
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, controller.text.trim()),
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
          },
        );
      },
    );
    controller.dispose();
    return result;
  }

  Future<void> _onToggleTwoFactor(bool enabled) async {
    if (enabled && !_biometricAvailable) {
      AppSnackbar.error(
        context,
        'Two-factor needs biometrics or a device PIN set up on this device.',
      );
      return;
    }
    await SecureUnlockService.setTwoFactorEnabled(enabled);
    if (!mounted) return;
    setState(() => _twoFactorEnabled = enabled);
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
                    subtitle:
                        "Use Face ID, fingerprint, or your device PIN as a quick way to log in.",
                    value: _biometricEnabled,
                    onChanged: _onToggleBiometric,
                  ),
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),
                  _toggleTile(
                    icon: Icons.verified_user_outlined,
                    title: "TWO-FACTOR AUTHENTICATION",
                    subtitle:
                        "After your email and password, confirm with Face ID, fingerprint, or your device PIN each time you log in.",
                    value: _twoFactorEnabled,
                    onChanged: _onToggleTwoFactor,
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
  }) {
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
              child: Icon(icon, size: 18, color: const Color(0xFFCC0000)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: Color(0xFF1A1A1A),
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
              onChanged: onChanged,
              activeThumbColor: const Color(0xFFCC0000),
            ),
          ],
        ),
      ),
    );
  }
}
