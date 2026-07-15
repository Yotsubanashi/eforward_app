import 'package:flutter/material.dart';

import '../../services/biometric_credential_store.dart';
import '../../services/secure_unlock_service.dart';
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

    await SecureUnlockService.setEnabled(enabled);
    // Turning it off must forget the securely-stored login so the biometric
    // login button can't reappear with stale credentials.
    if (!enabled) {
      await BiometricCredentialStore.clear();
    }
    if (!mounted) return;
    setState(() => _biometricEnabled = enabled);
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
