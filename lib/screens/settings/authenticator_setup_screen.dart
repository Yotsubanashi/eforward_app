import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api/auth_api.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/eforward_app_bar.dart';

/// Authenticator-app (TOTP) enrollment, mirroring ANI HRIS 2FA.
///
/// Flow: call `/auth/mfa/setup` to get a QR + secret, let the user scan it with
/// Google/Microsoft Authenticator, then confirm with a 6-digit code via
/// `/auth/mfa/verify-setup`. On success the account requires the authenticator
/// code at every mobile login. Pops `true` when enabled.
class AuthenticatorSetupScreen extends StatefulWidget {
  const AuthenticatorSetupScreen({super.key});

  @override
  State<AuthenticatorSetupScreen> createState() =>
      _AuthenticatorSetupScreenState();
}

class _AuthenticatorSetupScreenState extends State<AuthenticatorSetupScreen> {
  static const Color _brandRed = Color(0xFFCC0000);
  static const Color _ink = Color(0xFF1A1A1A);

  final AuthApi _authApi = AuthApi();
  final TextEditingController _codeController = TextEditingController();

  bool _loading = true; // loading the QR
  bool _submitting = false; // verifying the code
  String? _error;

  String? _secret;
  Uint8List? _qrBytes;

  @override
  void initState() {
    super.initState();
    _startSetup();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _authApi.dispose();
    super.dispose();
  }

  Future<void> _startSetup() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await _authApi.mfaSetup();
    if (!mounted) return;
    if (!result.isSuccess || result.data == null) {
      setState(() {
        _loading = false;
        _error = result.message;
      });
      return;
    }
    final data = result.data!;
    setState(() {
      _secret = data['secret']?.toString();
      _qrBytes = _decodeQr(data['qrCode']?.toString());
      _loading = false;
    });
  }

  /// Decodes a `data:image/png;base64,...` string into raw bytes for Image.memory.
  Uint8List? _decodeQr(String? dataUrl) {
    if (dataUrl == null || dataUrl.isEmpty) return null;
    final comma = dataUrl.indexOf(',');
    final b64 = comma >= 0 ? dataUrl.substring(comma + 1) : dataUrl;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length < 6) {
      AppSnackbar.error(context, 'Enter the 6-digit code from your app.');
      return;
    }
    setState(() => _submitting = true);
    final result = await _authApi.mfaVerifySetup(code: code);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (result.isSuccess) {
      AppSnackbar.success(context, 'Authenticator enabled.');
      Navigator.pop(context, true);
    } else {
      AppSnackbar.error(context, result.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const EForwardAppBar(
        title: "AUTHENTICATOR",
        backgroundColor: Colors.white,
        showBrand: false,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: _brandRed))
            : _error != null
                ? _errorView()
                : _setupView(),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: _brandRed),
            const SizedBox(height: 12),
            Text(_error ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _ink)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _startSetup,
              style: ElevatedButton.styleFrom(
                backgroundColor: _brandRed,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setupView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '1. Open Google Authenticator or Microsoft Authenticator and scan this QR code.',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          if (_qrBytes != null)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: Image.memory(_qrBytes!, width: 220, height: 220),
              ),
            ),
          const SizedBox(height: 16),
          if (_secret != null) ...[
            const Text("Can't scan? Enter this key manually:",
                style: TextStyle(fontSize: 13, color: Color(0xFF666666))),
            const SizedBox(height: 6),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _secret!));
                AppSnackbar.info(context, 'Key copied.');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _secret!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    const Icon(Icons.copy, size: 18, color: Color(0xFF888888)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const Text(
            '2. Enter the 6-digit code shown in your authenticator app:',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 24, letterSpacing: 8, color: _ink),
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide:
                    const BorderSide(color: Color(0xFFDDDDDD), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: const BorderSide(color: _brandRed, width: 1.5),
              ),
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _verify(),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _submitting ? null : _verify,
            style: ElevatedButton.styleFrom(
              backgroundColor: _brandRed,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFE09999),
              disabledForegroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              textStyle: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700),
            ),
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: Colors.white),
                  )
                : const Text('Enable authenticator'),
          ),
        ],
      ),
    );
  }
}
