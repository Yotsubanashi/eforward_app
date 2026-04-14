import 'dart:async';
import 'dart:convert';
import 'package:eforward_app/pages/auth/login.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_api.dart';
import '../../services/fcm_token_service.dart';
import '../dashboard/dashboard.dart';

class OtpScreen extends StatefulWidget {
  final String email;

  const OtpScreen({super.key, required this.email});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final List<TextEditingController> _controllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final AuthApi _authApi = AuthApi();

  int _secondsRemaining = 300;
  Timer? _timer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    _authApi.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsRemaining = 300);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining == 0) {
        timer.cancel();
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  Future<void> _resendOtp() async {
    final result = await _authApi.resendOtp(email: widget.email);

    if (!mounted) return;

    if (result.isSuccess) {
      debugPrint('OTP resent to email: ${result.message}');
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP resent to your email.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    debugPrint(
      'Failed to resend OTP [${result.statusCode}]: ${result.message}',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: const Color(0xFFCC0000),
      ),
    );
  }

  String get _timerText {
    final m = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _otpCode => _controllers.map((c) => c.text).join();

  Future<void> _verifyCode() async {
    if (_otpCode.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter the complete 6-digit code."),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authApi.verifyOtp(email: widget.email, otp: _otpCode);

    if (!mounted) return;

    if (result.isSuccess) {
      // 👇 Debug — print full response structure
      debugPrint('=== OTP VERIFY RESPONSE ===');
      debugPrint('Full data: ${result.data}');
      result.data?.forEach((key, value) {
        debugPrint('KEY: $key  →  VALUE: $value');
        // Also print nested maps
        if (value is Map) {
          value.forEach((k, v) => debugPrint('  NESTED KEY: $k  →  VALUE: $v'));
        }
      });
      debugPrint('===========================');

      // Deep search for token in any nested structure
      String? token = _extractToken(result.data);
      debugPrint('Extracted token: $token');

      if (token == null || token.isEmpty) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Authentication token not received. Please try again.",
            ),
            backgroundColor: Color(0xFFCC0000),
          ),
        );
        return;
      }

      // 👇 Save token to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', token);
      debugPrint('✅ Token saved successfully!');

      // 👇 Single getMe call (removed duplicate)
      final userResult = await _authApi.getMe(token: token);

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (userResult.isSuccess) {
        debugPrint('User profile loaded: ${userResult.data}');

        // 👇 Save userData to SharedPreferences so BottomNavigator can restore it
        if (userResult.data != null) {
          await prefs.setString('user_data', jsonEncode(userResult.data));
        }

        // 👇 Save FCM token to backend for push notifications
        await FCMTokenService.saveFCMTokenToBackend(accessToken: token);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => DashboardPage(userData: userResult.data),
          ),
        );
        return;
      }

      debugPrint(
        'Failed to load user profile [${userResult.statusCode}]: ${userResult.message}',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userResult.message),
          backgroundColor: const Color(0xFFCC0000),
        ),
      );
      return;
    }

    setState(() => _isLoading = false);

    debugPrint(
      'OTP verification failed [${result.statusCode}]: ${result.message}',
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: const Color(0xFFCC0000),
      ),
    );
  }

  // 👇 Deep search for token in any nested structure
  String? _extractToken(Map<String, dynamic>? data) {
    if (data == null) return null;

    // Common token field names to check
    const tokenKeys = [
      'accessToken',
      'access_token',
      'token',
      'jwt',
      'authToken',
      'auth_token',
      'bearerToken',
      'bearer_token',
    ];

    // Check top level
    for (final key in tokenKeys) {
      final val = data[key];
      if (val is String && val.isNotEmpty) return val;
    }

    // Check one level deep (e.g. data['data']['accessToken'])
    for (final entry in data.entries) {
      if (entry.value is Map<String, dynamic>) {
        for (final key in tokenKeys) {
          final val = (entry.value as Map<String, dynamic>)[key];
          if (val is String && val.isNotEmpty) return val;
        }
      }
    }

    return null;
  }

  void _onChanged(String value, int index) {
    if (value.isNotEmpty) {
      final upper = value.toUpperCase();
      _controllers[index].value = TextEditingValue(
        text: upper,
        selection: TextSelection.collapsed(offset: upper.length),
      );
    }
    if (value.length == 1 && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
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
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          ),
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
          children: [
            const SizedBox(height: 24),

            // Shield Icon
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.verified_user,
                color: Color(0xFFCC0000),
                size: 32,
              ),
            ),

            const SizedBox(height: 24),

            const Text(
              "VERIFY ACCOUNT",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: Color(0xFF1A1A1A),
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              "Enter the 6-digit code sent to your registered\ninstitutional email address.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.black45,
                height: 1.6,
              ),
            ),

            const SizedBox(height: 36),

            // OTP Fields
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(6, (index) => _buildOtpBox(index)),
            ),

            const SizedBox(height: 32),

            // Verify Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _verifyCode,
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
                            "VERIFY CODE",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.chevron_right,
                            color: Colors.white,
                            size: 20,
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 20),

            // Resend Code
            TextButton(
              onPressed: _secondsRemaining == 0 ? _resendOtp : null,
              child: const Text(
                "RESEND CODE",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),

            // Timer
            RichText(
              text: TextSpan(
                text: "CODE EXPIRES IN  ",
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.black38,
                  letterSpacing: 1,
                ),
                children: [
                  TextSpan(
                    text: _timerText,
                    style: const TextStyle(
                      color: Color(0xFFCC0000),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Security Notice
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    "SECURITY NOTICE",
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    "This verification step is mandatory for all high-value institutional transfers. Ensure you are on a secure network before proceeding.",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      height: 1.6,
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

  Widget _buildOtpBox(int index) {
    return SizedBox(
      width: 44,
      height: 52,
      child: TextField(
        controller: _controllers[index],
        focusNode: _focusNodes[index],
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        textDirection: TextDirection.ltr,
        textCapitalization: TextCapitalization.characters,
        keyboardType: TextInputType.visiblePassword,
        maxLength: 1,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
        ],
        onChanged: (value) => _onChanged(value, index),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A1A1A),
          height: 1.0,
        ),
        decoration: InputDecoration(
          counterText: "",
          filled: true,
          fillColor: Colors.white,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 0,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFFDDDDDD), width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Color(0xFFCC0000), width: 1.5),
          ),
        ),
      ),
    );
  }
}
