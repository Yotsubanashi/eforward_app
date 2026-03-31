import 'dart:io';
import 'dart:convert';
import 'package:eforward_app/pages/dashboard/dashboard.dart';
import 'package:eforward_app/pages/document/sign.dart';
import 'package:eforward_app/pages/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/components/bottom_navigator.dart';

class ViewSignPage extends StatefulWidget {
  const ViewSignPage({super.key});

  @override
  State<ViewSignPage> createState() => _ViewSignPageState();
}

class _ViewSignPageState extends State<ViewSignPage> {
  int _selectedIndex = 1;
  String _signatureType = '';
  String _signatureText = '';
  String _signatureImagePath = '';
  String _timestamp = '';
  String? _drawBase64;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSignature();
  }

  Future<void> _loadSignature() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _signatureType = prefs.getString('signature_type') ?? '';
      _signatureText = prefs.getString('signature_text') ?? '';
      _signatureImagePath = prefs.getString('signature_image_path') ?? '';
      _drawBase64 = prefs.getString('signature_draw_data');
      _timestamp = prefs.getString('signature_timestamp') ?? '';
      _loaded = true;
    });
  }

  // 👇 Handle all bottom nav taps
  void _onBottomNavTap(int index) {
    if (index == 0) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardPage()),
      );
    } else if (index == 1) {
      // Already here, do nothing
    } else if (index == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SettingsPage()),
      );
    }
  }

  Widget _buildSignaturePreview() {
    if (_signatureType == 'draw' && _drawBase64 != null) {
      return Container(
        width: double.infinity,
        height: 200,
        color: Colors.white,
        child: Image.memory(base64Decode(_drawBase64!), fit: BoxFit.contain),
      );
    } else if (_signatureType == 'type' && _signatureText.isNotEmpty) {
      return Container(
        width: double.infinity,
        height: 200,
        color: const Color(0xFF1A1A1A),
        alignment: Alignment.center,
        child: Text(
          _signatureText,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 34,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w300,
          ),
        ),
      );
    } else if (_signatureType == 'capture' && _signatureImagePath.isNotEmpty) {
      return Container(
        width: double.infinity,
        height: 200,
        color: const Color(0xFF1A1A1A),
        child: Image.file(File(_signatureImagePath), fit: BoxFit.contain),
      );
    } else {
      return Container(
        width: double.infinity,
        height: 200,
        color: const Color(0xFF1A1A1A),
        alignment: Alignment.center,
        child: Text(
          "Signature",
          style: TextStyle(
            color: Colors.white.withOpacity(0.85),
            fontSize: 36,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w300,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Brand Header
              Row(
                children: const [
                  Icon(
                    Icons.shield_outlined,
                    color: Color(0xFFCC0000),
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
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

              const SizedBox(height: 24),

              const Text(
                "SECURITY CREDENTIALS",
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFFCC0000),
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "DIGITAL SIGNATURE",
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: Color(0xFF1A1A1A),
                ),
              ),

              const SizedBox(height: 32),

              if (!_loaded)
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFFCC0000)),
                )
              else
                Column(
                  children: [
                    // Signature Preview Box
                    Stack(
                      children: [
                        _buildSignaturePreview(),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.15),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.verified,
                              size: 18,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      "TIMESTAMP",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.black38,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _timestamp.isNotEmpty ? _timestamp : "—",
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                        letterSpacing: 0.5,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Edit Signature Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const SignScreen()),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFCC0000),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Text(
                              "EDIT SIGNATURE",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                              ),
                            ),
                            SizedBox(width: 10),
                            Icon(Icons.edit, color: Colors.white, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigator(
        selectedIndex: _selectedIndex,
        onTap: (_) {}, // 👈 handles all tab navigation
      ),
    );
  }
}
