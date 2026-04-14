import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/components/bottom_navigator.dart';
import 'package:eforward_app/pages/approvals/approvals.dart';
import 'package:eforward_app/pages/approvals/approval_details.dart';
import 'package:eforward_app/services/fcm_token_service.dart';
import 'package:eforward_app/services/notifications_service.dart';

class DashboardPage extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const DashboardPage({super.key, this.userData});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final int _selectedIndex = 0;

  static const String _baseUrl =
      'https://eforward-api.ardentnetworks.com.ph/api';

  late String _userName;
  late String _userEmail;
  late String _userRole;
  late List<Map<String, dynamic>> _userModules;

  // Pending approvals from API
  List<Map<String, dynamic>> _pendingApprovals = [];
  bool _isLoadingPending = false;

  @override
  void initState() {
    super.initState();
    _userName = 'User';
    _userEmail = 'N/A';
    _userRole = 'USER';
    _userModules = [];

    // Load user data then fetch pending
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadUserData();
      _fetchPendingApprovals();
      _syncFCMToken();
      NotificationsService().fetchUnreadCount();
    });
  }

  Future<void> _syncFCMToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token') ?? '';
      if (accessToken.isNotEmpty) {
        await FCMTokenService.syncTokenIfNeeded(accessToken: accessToken);
      }
    } catch (e) {
      debugPrint('Error syncing FCM token: $e');
    }
  }

  Future<void> _loadUserData() async {
    // Try widget.userData first (from OTP login)
    if (widget.userData != null) {
      debugPrint('Loading from widget.userData: ${widget.userData}');
      _applyUserData(widget.userData!);
      return;
    }

    // Fallback — load from SharedPreferences (when navigating via BottomNavigator)
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
    // Try nested 'data' key first, then flat
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

    String dateSent = raw['date_sent'] ?? '';
    try {
      if (dateSent.isNotEmpty) {
        final dt = DateTime.parse(dateSent).toLocal();
        final months = [
          'JAN',
          'FEB',
          'MAR',
          'APR',
          'MAY',
          'JUN',
          'JUL',
          'AUG',
          'SEP',
          'OCT',
          'NOV',
          'DEC',
        ];
        final hour = dt.hour > 12
            ? dt.hour - 12
            : (dt.hour == 0 ? 12 : dt.hour);
        final ampm = dt.hour >= 12 ? 'PM' : 'AM';
        dateSent =
            '${months[dt.month - 1]} ${dt.day}, ${dt.year} | '
            '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $ampm';
      }
    } catch (_) {}

    return {
      ...raw,
      'id': raw['routing_id']?.toString() ?? '',
      'referenceNo': routing['reference_no'] ?? '',
      'particulars': routing['particulars'] ?? '',
      'requester': requesterName.isNotEmpty ? requesterName : '—',
      'dateSent': dateSent,
      'routing': routing,
      'owner': owner,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchPendingApprovals,
          color: const Color(0xFFCC0000),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
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
                  "WELCOME BACK,\n${_userName.isNotEmpty ? _userName.split(' ').first.toUpperCase() : 'User'}",
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    height: 1.1,
                    color: Color(0xFF1A1A1A),
                  ),
                ),

                const SizedBox(height: 12),

                // Text(
                //   'Email: $_userEmail | Role: $_userRole',
                //   style: const TextStyle(
                //     fontSize: 12,
                //     color: Colors.black54,
                //     letterSpacing: 0.5,
                //   ),
                // ),
                // const SizedBox(height: 24),

                // ─── PENDING APPROVALS CARD ───────────────────────────────
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
                              // 👇 Real count from API
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
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ApprovalsPage(),
                            ),
                          ),
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

                // ─── ACCESSIBLE MODULES ───────────────────────────────────
                if (_userModules.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "ACCESSIBLE MODULES",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 16),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1,
                            ),
                        itemCount: _userModules.length,
                        itemBuilder: (context, index) {
                          final module = _userModules[index];
                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(
                                color: const Color(0xFFE8E8E8),
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.dashboard,
                                    color: Color(0xFFCC0000),
                                    size: 28,
                                  ),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Text(
                                      module['module_name'] ?? 'Module',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                        color: Color(0xFF1A1A1A),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),

                // ─── RECENT ACTIVITY — from pending API ───────────────────
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
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ApprovalsPage(),
                        ),
                      ),
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

                // 👇 Show pending approvals from API
                if (_isLoadingPending)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: CircularProgressIndicator(
                        color: Color(0xFFCC0000),
                      ),
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
                        : _pendingApprovals.length, // show max 5
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _buildActivityCard(_pendingApprovals[index]),
                  ),

                const SizedBox(height: 24),
              ],
            ),
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
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ApprovalDetailPage(item: item)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE8E8E8)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Red accent line
            Container(width: 3, height: 44, color: const Color(0xFFCC0000)),
            const SizedBox(width: 12),

            // Reference no + PENDING badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['referenceNo']?.toString().isNotEmpty == true
                        ? item['referenceNo'].toString()
                        : item['id']?.toString() ?? '—',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Particulars
                  Text(
                    item['particulars']?.toString().isNotEmpty == true
                        ? item['particulars'].toString()
                        : '—',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCC0000).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      "PENDING",
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: Color(0xFFCC0000),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Date + chevron
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item['dateSent']?.toString().isNotEmpty == true
                      ? item['dateSent'].toString()
                      : '—',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.black38,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 6),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.black26,
                  size: 18,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
