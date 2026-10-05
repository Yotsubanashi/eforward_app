import 'package:flutter/material.dart';

/// Branded loading screen shown while the app resolves the saved session on
/// startup. Replaces the previous bare white `Scaffold` + spinner, which left
/// the user staring at a plain white screen with no logo during the (possibly
/// several-second) network session check. The logo here matches the native
/// launch screen, so startup reads as one continuous branded splash.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/eforward-logo.png',
                width: 180,
                height: 180,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  debugPrint('❌ Splash logo load error: $error');
                  return const Icon(
                    Icons.shield_outlined,
                    color: Color(0xFFCC0000),
                    size: 80,
                  );
                },
              ),
              const SizedBox(height: 32),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFCC0000)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
