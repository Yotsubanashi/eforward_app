import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/services/firebase_notification_service.dart';
import 'package:eforward_app/services/fcm_token_service.dart';

class NotificationTestPage extends StatefulWidget {
  const NotificationTestPage({super.key});

  @override
  State<NotificationTestPage> createState() => _NotificationTestPageState();
}

class _NotificationTestPageState extends State<NotificationTestPage> {
  String? _fcmToken;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFCMToken();
  }

  Future<void> _loadFCMToken() async {
    try {
      final token = await FirebaseNotificationService().getFCMToken();
      setState(() {
        _fcmToken = token;
        _isLoading = false;
      });
      // Automatically save token to backend
      if (token != null && token.isNotEmpty) {
        await _saveTokenToBackend();
      }
    } catch (e) {
      debugPrint('Error loading FCM token: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFCC0000),
        elevation: 0,
        title: const Text(
          'Notification Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // FCM Token Section
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE8E8E8)),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'FCM Token',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: Color(0xFFCC0000),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_isLoading)
                    const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFCC0000),
                      ),
                    )
                  else if (_fcmToken != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9F9F9),
                            border: Border.all(color: const Color(0xFFE8E8E8)),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: SelectableText(
                            _fcmToken ?? '',
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              letterSpacing: 0.3,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '✅ Token Retrieved',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Token copied to clipboard'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFCC0000),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text(
                                'Copy',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  else
                    const Text(
                      '❌ Unable to retrieve token',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Instructions Section
            const Text(
              'How to Send Notifications',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                color: Color(0xFF1A1A1A),
              ),
            ),

            const SizedBox(height: 12),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE8E8E8)),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInstructionStep(
                    '1',
                    'Firebase Console',
                    'Go to Firebase Console → Cloud Messaging',
                  ),
                  const SizedBox(height: 12),
                  _buildInstructionStep(
                    '2',
                    'Send Message',
                    'Click "Send your first message"',
                  ),
                  const SizedBox(height: 12),
                  _buildInstructionStep(
                    '3',
                    'Enter Title & Body',
                    'Add notification title and description',
                  ),
                  const SizedBox(height: 12),
                  _buildInstructionStep(
                    '4',
                    'Select Device',
                    'Choose "Send to a topic" or paste FCM token above',
                  ),
                  const SizedBox(height: 12),
                  _buildInstructionStep(
                    '5',
                    'Send',
                    'Click Send and check your device',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Test Scenarios
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE8E8E8)),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Test Scenarios',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: Color(0xFFCC0000),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildTestScenario(
                    '📱 App Open',
                    'Shows dialog when you have the app open',
                  ),
                  const SizedBox(height: 8),
                  _buildTestScenario(
                    '🔔 App Background',
                    'Shows notification in tray when app is backgrounded',
                  ),
                  const SizedBox(height: 8),
                  _buildTestScenario(
                    '🔒 App Closed',
                    'Notification appears even when app is completely closed',
                  ),
                  const SizedBox(height: 8),
                  _buildTestScenario(
                    '📵 Offline',
                    'Messages are queued and delivered when device comes online',
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Info Box
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                border: Border.all(color: const Color(0xFFBBDEFB)),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '💡 Tips',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: Color(0xFF1976D2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Keep this token safe - use it to send notifications\n'
                    '• Save this token to your backend database\n'
                    '• Each device gets a unique token\n'
                    '• Tokens can change, so check periodically\n'
                    '• Notifications work on Android 5.0+\n'
                    '• iOS requires APNs certificate configuration',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF1565C0),
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Save FCM token to backend automatically
  Future<void> _saveTokenToBackend() async {
    if (_fcmToken == null || _fcmToken!.isEmpty) {
      debugPrint('No FCM token available');
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token') ?? '';

      if (accessToken.isEmpty) {
        debugPrint('No access token found. Please login first.');
        return;
      }

      final success = await FCMTokenService.saveFCMTokenToBackend(
        accessToken: accessToken,
      );

      if (!mounted) return;

      if (success) {
        debugPrint('✅ FCM token saved to backend successfully!');
      } else {
        debugPrint('❌ Failed to save token to backend');
      }
    } catch (e) {
      debugPrint('Error saving token: $e');
    }
  }

  Widget _buildInstructionStep(
    String number,
    String title,
    String description,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFFCC0000),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTestScenario(String scenario, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                scenario,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              Text(
                description,
                style: const TextStyle(fontSize: 10, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
