import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_api.dart';
import '../../services/fcm_token_service.dart';
import '../dashboard/dashboard.dart';
import 'forgot_password.dart';
import 'package:flutter_svg/flutter_svg.dart';


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

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email and password are required.'),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authApi.login(email: email, password: password);

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (result.isSuccess) {
      _saveRememberMe(email);
      debugPrint('Login success: ${result.data}');

      final token =
          result.data?['accessToken'] ??
          result.data?['access_token'] ??
          result.data?['token'];

      if (token != null && token.toString().isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token', token.toString());
        if (result.data != null) {
          await prefs.setString('user_data', jsonEncode(result.data));
        }

        await FCMTokenService.saveFCMTokenToBackend(
          accessToken: token.toString(),
        );
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => DashboardPage(userData: result.data),
        ),
      );
      return;
    }

    debugPrint('Login failed [${result.statusCode}]: ${result.message}');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: const Color(0xFFCC0000),
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo + Brand
                
                const SizedBox(height: 102),

                // ✅ Fixed: SVG logo + subtitle properly wrapped
              Center(
                child: Column(
                  children: [
                    Image.network(
                      'https://ardentnetworks.com.ph/wp-content/uploads/2023/07/ardent-logo-with-powering-innovation-8.png',
                      width: 240,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const SizedBox(
                          width: 220,
                          height: 66,
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFCC0000),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.shield_outlined,
                          color: Color(0xFFCC0000),
                          size: 40,
                        );
                      },
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      "E-FORWARD",
                      textAlign: TextAlign.center,
                      style: TextStyle(
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
                    hintStyle: TextStyle(color: Colors.black26, fontSize: 12),
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
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
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

                // Remember Me Checkbox
                Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _rememberMe,
                        onChanged: _isLoading
                            ? null
                            : (val) =>
                                  setState(() => _rememberMe = val ?? false),
                        activeColor: const Color(0xFFCC0000),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                      style: TextStyle(color: Colors.black54, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Login Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _handleLogin,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.arrow_forward, color: Colors.white),
                    label: Text(
                      _isLoading ? "LOGGING IN..." : "LOGIN",
                      style: const TextStyle(
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
    );
  }
}