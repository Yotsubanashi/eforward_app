import 'dart:convert';
import 'package:eforward_app/pages/approvals/approval_details.dart';
import 'package:eforward_app/services/fcm_token_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:eforward_app/pages/approvals/approvals.dart';
import 'package:flutter/material.dart';
import 'package:eforward_app/components/bottom_navigator.dart';
import 'package:eforward_app/config/app_env.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/services/secure_unlock_service.dart';

class DashboardPage extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const DashboardPage({super.key, this.userData});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  String get _baseUrl => AppEnv.apiBaseUrl;
  static const String _biometricPromptSeenKey = 'biometric_prompt_seen';
  final int _selectedIndex = 0;

  String _userName = 'User';
  String _userEmail = 'N/A';
  String _userRole = 'USER';
  List<Map<String, dynamic>> _userModules = [];

  List<Map<String, dynamic>> _pendingApprovals = [];
  bool _isLoadingPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadUserData();
      _fetchPendingApprovals();
      _syncFCMToken();
      _setupFCMListener();
      await _maybeShowBiometricSetupPrompt();
    });
  }

  Future<void> _maybeShowBiometricSetupPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    final alreadySeen = prefs.getBool(_biometricPromptSeenKey) ?? false;
    final biometricEnabled = await SecureUnlockService.isEnabled();

    if (alreadySeen || biometricEnabled || !mounted) return;

    await prefs.setBool(_biometricPromptSeenKey, true);

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFCC0000).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.fingerprint,
                    color: Color(0xFFCC0000),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  "ENABLE BIOMETRIC UNLOCK",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  "Protect app access with your fingerprint, Face ID, or device PIN. You can change this anytime in Settings.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, height: 1.5),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () async {
                      final success =
                          await SecureUnlockService.authenticateAfterLogin();
                      if (success) {
                        await SecureUnlockService.setEnabled(true);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Biometric/PIN unlock enabled.'),
                              backgroundColor: Color(0xFF2E7D32),
                            ),
                          );
                        }
                      } else if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Unable to enable biometric unlock right now.',
                            ),
                            backgroundColor: Color(0xFFCC0000),
                          ),
                        );
                      }
                      if (Navigator.of(dialogContext).canPop()) {
                        Navigator.of(dialogContext).pop();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFCC0000),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      "ENABLE NOW",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text(
                      "MAYBE LATER",
                      style: TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _setupFCMListener() {
    try {
      FirebaseMessaging.onMessage.listen((remoteMessage) {
        debugPrint(
          '[Dashboard] Received foreground message: ${remoteMessage.notification?.title}',
        );
        final title = remoteMessage.notification?.title ?? '';
        if (title.toLowerCase().contains('approval') ||
            title.toLowerCase().contains('forwarded') ||
            title.toLowerCase().contains('pending')) {
          debugPrint(
            '[Dashboard] Approval-related message detected, refreshing...',
          );
          _fetchPendingApprovals();
        }
      });
    } catch (e) {
      debugPrint('[Dashboard] Error setting up FCM listener: $e');
    }
  }

  Future<void> _syncFCMToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');
      if (userDataStr != null) {
        final userData = jsonDecode(userDataStr);
        final user = userData['user'] is Map ? userData['user'] : userData;
        final userId =
            user['id']?.toString() ??
            user['employee_id']?.toString() ??
            user['employeeId']?.toString();

        if (userId != null) {
          await FCMTokenService.registerToken(userId);
          debugPrint('✅ FCM token synced in Dashboard');
        }
      }
    } catch (e) {
      debugPrint('Error syncing FCM token: $e');
    }
  }

  Future<void> _loadUserData() async {
    if (widget.userData != null) {
      _applyUserData(widget.userData!);
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final userDataStr = prefs.getString('user_data');
      debugPrint('user_data from prefs: $userDataStr');
      if (userDataStr != null && userDataStr.isNotEmpty) {
        final decoded = jsonDecode(userDataStr) as Map<String, dynamic>;
        debugPrint('Decoded keys: ${decoded.keys.toList()}');
        if (mounted) _applyUserData(decoded);
      }
    } catch (e) {
      debugPrint('Error loading user_data: $e');
    }
  }

  void _applyUserData(Map<String, dynamic> fullData) {
    final userData =
        fullData['data'] as Map<String, dynamic>? ??
        fullData['user'] as Map<String, dynamic>? ??
        fullData;

    debugPrint('userData keys: ${userData.keys.toList()}');
    debugPrint(
      'fname: ${userData['fname']} | lname: ${userData['lname']} | email_add: ${userData['email_add']}',
    );

    final firstName = userData['fname']?.toString().trim() ?? '';
    final lastName = userData['lname']?.toString().trim() ?? '';

    setState(() {
      _userName = '$firstName $lastName'.trim();
      if (_userName.isEmpty) _userName = 'User';
      _userEmail =
          userData['email_add'] ??
          userData['email'] ??
          userData['emailAdd'] ??
          'N/A';
      _userRole = userData['role'] ?? 'USER';

      final modulesList = userData['modules'] as List?;
      _userModules = [];
      if (modulesList != null) {
        for (var item in modulesList) {
          if (item is Map<String, dynamic>) {
            final module = item['module'] as Map<String, dynamic>?;
            if (module != null) _userModules.add(module);
          }
        }
      }
      debugPrint(
        'Applied → name: $_userName | email: $_userEmail | role: $_userRole | modules: ${_userModules.length}',
      );
    });
  }

  // ─── FORMAT DATE ──────────────────────────────────────────────────────────
  // Handles dot-separated format: 2026.04.22T11:07:10.000Z
  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final datePart = raw.substring(0, 10).replaceAll('.', '-');
      final rest = raw.substring(10);
      // Strip timezone suffix so we treat the clock value as-is
      final stripped = (datePart + rest).replaceFirst(
        RegExp(r'(Z|[+-]\d{2}:\d{2})$'),
        '',
      );
      final dt = DateTime.parse(stripped);
      return _relativeDate(dt);
    } catch (_) {
      return raw;
    }
  }

  String _relativeDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(target).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '$diff days ago';
    if (diff < 14) return '1 week ago';
    if (diff < 30) return '${(diff / 7).floor()} weeks ago';
    if (diff < 60) return '1 month ago';
    if (diff < 365) return '${(diff / 30).floor()} months ago';
    return '${(diff / 365).floor()} year${(diff / 365).floor() > 1 ? 's' : ''} ago';
  }

  // ─── GET /approvals/pending ───────────────────────────────────────────────
  Future<void> _fetchPendingApprovals() async {
    setState(() => _isLoadingPending = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      if (token.isEmpty) {
        setState(() => _isLoadingPending = false);
        return;
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/approvals/pending?page=1&limit=50'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final rawList = _extractList(decoded);
        setState(() {
          _pendingApprovals = rawList
              .map((e) => _normalizeItem(e as Map<String, dynamic>))
              .toList();
          _isLoadingPending = false;
        });
      } else {
        setState(() => _isLoadingPending = false);
      }
    } catch (e) {
      debugPrint('Dashboard pending fetch error: $e');
      if (mounted) setState(() => _isLoadingPending = false);
    }
  }

  List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final key in ['data', 'approvals', 'items', 'results', 'list']) {
        if (decoded[key] is List) return decoded[key] as List;
      }
    }
    return [];
  }

  String _normalizeStatus(String? raw) {
    final s = (raw ?? '').toUpperCase().trim();
    if (s.isEmpty || s == 'NULL') return '';
    if (s.startsWith('PEND') || s == 'PND') return 'PND';
    if (s.startsWith('APP') || s == 'APV') return 'APV';
    if (s.startsWith('REJ') || s == 'REJ') return 'REJ';
    if (s == 'OPN' || s.startsWith('OPEN')) return 'OPN';
    if (s.startsWith('CANCEL') || s == 'CNL') return 'CNL';
    return s;
  }

  String _getStatusLabel(String status) {
    switch (status.toUpperCase().trim()) {
      case 'CNL':
        return 'CANCELLED';
      case 'APV':
        return 'APPROVED';
      case 'PND':
        return 'PENDING';
      case 'OPN':
        return 'OPEN';
      default:
        return status.toUpperCase().trim();
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toUpperCase().trim()) {
      case 'CNL':
        return const Color(0xFFCC0000);
      case 'APV':
        return Colors.green;
      case 'PND':
        return Colors.orange;
      case 'OPN':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Map<String, dynamic> _normalizeItem(Map<String, dynamic> raw) {
    final routing = raw['routing'] as Map<String, dynamic>? ?? {};
    final owner = routing['owner'] as Map<String, dynamic>? ?? {};

    final firstName = owner['fname']?.toString().trim() ?? '';
    final middleName = owner['mname']?.toString().trim() ?? '';
    final lastName = owner['lname']?.toString().trim() ?? '';
    final requesterName = [
      firstName,
      middleName,
      lastName,
    ].where((p) => p.isNotEmpty).join(' ').trim();

    String status = _normalizeStatus(routing['status']?.toString());
    if (status.isEmpty) status = _normalizeStatus(raw['status']?.toString());
    if (status.isEmpty) status = _normalizeStatus(raw['to_status']?.toString());
    if (status.isEmpty) status = 'PND';

    return {
      ...raw,
      'id': raw['routing_id']?.toString() ?? '',
      'referenceNo': routing['reference_no'] ?? '',
      'particulars': routing['particulars'] ?? '',
      'requester': requesterName.isNotEmpty ? requesterName : '—',
      'dateSent': _formatDateTime(raw['date_sent']?.toString()), // ✅ formatted
      'status': status,
      'routing': routing,
      'owner': owner,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: SingleChildScrollView(
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
                  SizedBox(width: 10),
                  Text(
                    "E-FORWARD",
                    style: TextStyle(
                      color: Color(0xFFCC0000),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              Text(
                "WELCOME BACK,\n${_userName.isNotEmpty ? _userName.split(' ').first.toUpperCase() : 'USER'}",
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  height: 1.1,
                  color: Color(0xFF1A1A1A),
                ),
              ),

              const SizedBox(height: 12),

              // ─── PENDING APPROVALS CARD ───────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE8E8E8)),
                ),
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      left: BorderSide(color: Color(0xFFCC0000), width: 3),
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "PENDING APPROVALS",
                              style: TextStyle(
                                fontSize: 9,
                                color: Color(0xFFCC0000),
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            _isLoadingPending
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFCC0000),
                                    ),
                                  )
                                : Text(
                                    '${_pendingApprovals.length}',
                                    style: const TextStyle(
                                      fontSize: 38,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF1A1A1A),
                                      height: 1,
                                    ),
                                  ),
                            const SizedBox(height: 6),
                            const Text(
                              "High-priority authorizations requiring immediate executive review.",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.black45,
                                letterSpacing: 0.3,
                                height: 1.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ApprovalsPage(),
                            ),
                          ).then((_) {
                            if (mounted) _fetchPendingApprovals();
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFCC0000),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        child: const Text(
                          "REVIEW NOW",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // ─── RECENT ACTIVITY ──────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "RECENT ACTIVITY",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ApprovalsPage(),
                        ),
                      ).then((_) {
                        if (mounted) _fetchPendingApprovals();
                      });
                    },
                    child: const Text(
                      "VIEW ALL LOGS →",
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: Color(0xFFCC0000),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              if (_isLoadingPending)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(color: Color(0xFFCC0000)),
                  ),
                )
              else if (_pendingApprovals.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFE8E8E8)),
                  ),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 32,
                        color: Colors.black12,
                      ),
                      SizedBox(height: 8),
                      Text(
                        "No pending approvals",
                        style: TextStyle(fontSize: 12, color: Colors.black38),
                      ),
                    ],
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _pendingApprovals.length > 5
                      ? 5
                      : _pendingApprovals.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) =>
                      _buildActivityCard(_pendingApprovals[index]),
                ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigator(
        selectedIndex: _selectedIndex,
        onTap: (_) {},
      ),
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> item) {
    final status = item['status']?.toString() ?? 'PND';
    final statusColor = _getStatusColor(status);
    final statusLabel = _getStatusLabel(status);
    final refNo = item['referenceNo']?.toString().isNotEmpty == true
        ? item['referenceNo'].toString()
        : item['id']?.toString() ?? '—';
    final particulars = item['particulars']?.toString().isNotEmpty == true
        ? item['particulars'].toString()
        : '—';
    final requester = item['requester']?.toString() ?? '—';
    final dateSent = item['dateSent']?.toString().isNotEmpty == true
        ? item['dateSent'].toString()
        : '—';

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () =>
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ApprovalDetailPage(item: item, isFromHistory: false),
            ),
          ).then((_) {
            if (mounted) _fetchPendingApprovals();
          }),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: ref + status ──────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
                border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
              ),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCC0000),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      refNo,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Color(0xFFCC0000),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: statusColor.withOpacity(0.20),
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Body: particulars + requester + date ──────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: particulars + requester
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          particulars,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1A1A),
                            letterSpacing: 0.2,
                            height: 1.4,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: const Color(0xFFEEEEEE),
                                ),
                              ),
                              child: const Icon(
                                Icons.person_outline,
                                size: 12,
                                color: Color(0xFF999999),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                requester,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF555555),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Right: date + chevron
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.access_time_rounded,
                            size: 11,
                            color: Color(0xFFAAAAAA),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            dateSent,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFAAAAAA),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: Color(0xFFCC0000),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
