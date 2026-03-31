import 'package:flutter/material.dart';
import 'otp.dart'; // 👈 added

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    if (_emailController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter your email address."),
          backgroundColor: Color(0xFFCC0000),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 1500));
    setState(() => _isLoading = false);

    if (mounted) {
      Navigator.push(
        // 👈 navigate to OTP screen
        context,
        MaterialPageRoute(builder: (_) => const OtpScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo + Brand
              Row(
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    color: Color(0xFFCC0000),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    "E-FORWARD",
                    style: TextStyle(
                      color: Color(0xFFCC0000),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 48),

              // Title
              const Text(
                "FORGOT\nPASSWORD",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  height: 1.1,
                  color: Color(0xFF1A1A1A),
                ),
              ),

              const SizedBox(height: 12),

              // Subtitle
              const Text(
                "Enter your registered email to reset your account.",
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 32),

              // Email Label
              const Text(
                "EMAIL ADDRESS",
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 8),

              // Email Field
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontSize: 13, color: Color(0xFF1A1A1A)),
                decoration: const InputDecoration(
                  hintText: "name@institution.com",
                  hintStyle: TextStyle(color: Colors.black26, fontSize: 13),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.black26),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFCC0000)),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // Send OTP Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _sendResetLink,
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
                              "SEND OTP",
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

              const SizedBox(height: 20),

              // Back to Login
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "BACK TO LOGIN",
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Footer
              const Center(
                child: Text(
                  "© 2024 E-FORWARD INSTITUTIONAL SYSTEMS.\nALL RIGHTS RESERVED.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 8,
                    color: Colors.black26,
                    letterSpacing: 1.2,
                    height: 1.8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
