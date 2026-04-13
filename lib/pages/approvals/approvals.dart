import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/components/bottom_navigator.dart';
import 'package:eforward_app/pages/approvals/approval_details.dart';

class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key});

  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage>
    with SingleTickerProviderStateMixin {
  final int _selectedIndex = 0;
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const String _baseUrl =
      'https://eforward-api.ardentnetworks.com.ph/api';

  // API data
  List<Map<String, dynamic>> _pendingApprovals = [];
  List<Map<String, dynamic>> _historyApprovals = [];
  bool _isLoadingPending = false;
  bool _isLoadingHistory = false;
  String? _pendingError;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      // Load history only when that tab is opened
      if (_tabController.index == 1 &&
          _historyApprovals.isEmpty &&
          !_isLoadingHistory) {
        _fetchHistory();
      }
    });
    _fetchPending();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ─── GET /approvals/pending ───────────────────────────────────────────────
  Future<void> _fetchPending({String? search}) async {
    setState(() {
      _isLoadingPending = true;
      _pendingError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';

      if (token.isEmpty) {
        setState(() {
          _isLoadingPending = false;
          _pendingError = 'Session expired. Please login again.';
        });
        return;
      }

      final queryParams = <String, String>{'page': '1', 'limit': '50'};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      final uri = Uri.parse(
        '$_baseUrl/approvals/pending',
      ).replace(queryParameters: queryParams);

      debugPrint('Fetching pending approvals: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      debugPrint('Pending status: ${response.statusCode}');
      debugPrint(
        'Pending body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
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
        final decoded = jsonDecode(response.body);
        setState(() {
          _isLoadingPending = false;
          _pendingError = decoded['message'] ?? 'Failed to load approvals.';
        });
      }
    } catch (e) {
      debugPrint('Fetch pending error: $e');
      if (mounted) {
        setState(() {
          _isLoadingPending = false;
          _pendingError = 'Network error. Please try again.';
        });
      }
    }
  }

  // ─── GET /approvals/history ───────────────────────────────────────────────
  Future<void> _fetchHistory({String? search}) async {
    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';

      if (token.isEmpty) {
        setState(() {
          _isLoadingHistory = false;
          _historyError = 'Session expired.';
        });
        return;
      }

      final queryParams = <String, String>{'page': '1', 'limit': '50'};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      final uri = Uri.parse(
        '$_baseUrl/approvals/history',
      ).replace(queryParameters: queryParams);

      debugPrint('Fetching history: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      debugPrint('History status: ${response.statusCode}');

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final rawList = _extractList(decoded);
        setState(() {
          _historyApprovals = rawList
              .map((e) => _normalizeItem(e as Map<String, dynamic>))
              .toList();
          _isLoadingHistory = false;
        });
      } else {
        setState(() {
          _isLoadingHistory = false;
          _historyError = 'Failed to load history.';
        });
      }
    } catch (e) {
      debugPrint('Fetch history error: $e');
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
          _historyError = 'Network error.';
        });
      }
    }
  }

  // ─── Extract list from various API response structures ────────────────────
  List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map) {
      for (final key in ['data', 'approvals', 'items', 'results', 'list']) {
        if (decoded[key] is List) return decoded[key] as List;
        if (decoded[key] is Map && decoded[key]['data'] is List) {
          return decoded[key]['data'] as List;
        }
      }
    }
    return [];
  }

  // ─── Normalize API fields to consistent keys ──────────────────────────────
  Map<String, dynamic> _normalizeItem(Map<String, dynamic> raw) {
    // All document data is nested inside raw['routing']
    final routing = raw['routing'] as Map<String, dynamic>? ?? {};
    // Requester is inside routing['owner']
    final owner = routing['owner'] as Map<String, dynamic>? ?? {};

    final firstName = owner['fname']?.toString().trim() ?? '';
    final middleName = owner['mname']?.toString().trim() ?? '';
    final lastName = owner['lname']?.toString().trim() ?? '';
    final requesterName = [
      firstName,
      middleName,
      lastName,
    ].where((p) => p.isNotEmpty).join(' ').trim();

    // Format date from ISO to readable
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
      'status': raw['status'] ?? 'PND',
      // Keep routing object for detail page
      'routing': routing,
      'owner': owner,
    };
  }

  // ─── Extract requester (kept for compatibility) ────────────────────────────
  String _extractRequester(Map<String, dynamic> raw) {
    return raw['requester']?.toString() ?? '—';
  }

  void _onSearch(String val) {
    setState(() => _searchQuery = val);
    if (_tabController.index == 0) {
      _fetchPending(search: val);
    } else {
      _fetchHistory(search: val);
    }
  }

  List<Map<String, dynamic>> get _filteredPending {
    if (_searchQuery.isEmpty) return _pendingApprovals;
    return _pendingApprovals.where((item) {
      final q = _searchQuery.toLowerCase();
      return (item['referenceNo'] ?? '').toLowerCase().contains(q) ||
          (item['requester'] ?? '').toLowerCase().contains(q) ||
          (item['particulars'] ?? '').toLowerCase().contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredHistory {
    if (_searchQuery.isEmpty) return _historyApprovals;
    return _historyApprovals.where((item) {
      final q = _searchQuery.toLowerCase();
      return (item['referenceNo'] ?? '').toLowerCase().contains(q) ||
          (item['requester'] ?? '').toLowerCase().contains(q) ||
          (item['particulars'] ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back,
            color: Color(0xFF1A1A1A),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
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
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "APPROVALS",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                      // Pending badge
                      if (_pendingApprovals.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFCC0000).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFCC0000).withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.pending_outlined,
                                size: 12,
                                color: Color(0xFFCC0000),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${_pendingApprovals.length} PENDING',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFCC0000),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    "Review and approve pending documents",
                    style: TextStyle(fontSize: 13, color: Colors.black45),
                  ),
                  const SizedBox(height: 16),

                  // Tabs
                  TabBar(
                    controller: _tabController,
                    labelColor: const Color(0xFFCC0000),
                    unselectedLabelColor: Colors.black38,
                    indicatorColor: const Color(0xFFCC0000),
                    indicatorWeight: 2,
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                    tabs: [
                      Tab(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text("PENDING"),
                            if (_pendingApprovals.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFCC0000),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_pendingApprovals.length}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Tab(text: "HISTORY"),
                    ],
                  ),
                ],
              ),
            ),

            // Search
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8F8),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    const Icon(Icons.search, size: 18, color: Colors.black38),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearch,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1A1A1A),
                        ),
                        decoration: const InputDecoration(
                          hintText: "Search approvals...",
                          hintStyle: TextStyle(
                            color: Colors.black26,
                            fontSize: 13,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 0),
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          _onSearch('');
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: Colors.black38,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCardList(
                    _filteredPending,
                    isPending: true,
                    isLoading: _isLoadingPending,
                    error: _pendingError,
                    onRefresh: _fetchPending,
                  ),
                  _buildCardList(
                    _filteredHistory,
                    isPending: false,
                    isLoading: _isLoadingHistory,
                    error: _historyError,
                    onRefresh: _fetchHistory,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigator(
        selectedIndex: _selectedIndex,
        onTap: (_) {},
      ),
    );
  }

  Widget _buildCardList(
    List<Map<String, dynamic>> items, {
    required bool isPending,
    required bool isLoading,
    required String? error,
    required VoidCallback onRefresh,
  }) {
    // Loading
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Color(0xFFCC0000)),
            SizedBox(height: 12),
            Text(
              "LOADING...",
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                color: Colors.black38,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    // Error
    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Color(0xFFCC0000)),
            const SizedBox(height: 12),
            Text(
              error,
              style: const TextStyle(fontSize: 13, color: Colors.black45),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRefresh,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFCC0000),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: const Text(
                "RETRY",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Empty
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => onRefresh(),
        color: const Color(0xFFCC0000),
        child: ListView(
          children: [
            SizedBox(
              height: 300,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 48,
                      color: Colors.black12,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isPending ? "All caught up!" : "No history yet.",
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black38,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPending
                          ? "You don't have any pending approvals"
                          : "Completed approvals will appear here.",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black26,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: const Color(0xFFCC0000),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) =>
            _buildApprovalCard(items[index], isPending: isPending),
      ),
    );
  }

  Widget _buildEmptyState({required bool isPending}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 48,
            color: Colors.black12,
          ),
          const SizedBox(height: 12),
          Text(
            isPending ? "All caught up!" : "No history yet.",
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black38,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isPending
                ? "You don't have any pending approvals"
                : "Completed approvals will appear here.",
            style: const TextStyle(fontSize: 12, color: Colors.black26),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalCard(
    Map<String, dynamic> item, {
    required bool isPending,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reference No + Status badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item['referenceNo']?.toString().isNotEmpty == true
                    ? item['referenceNo'].toString()
                    : item['id']?.toString() ?? '—',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFFCC0000),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isPending
                      ? const Color(0xFFCC0000).withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  isPending ? "PENDING" : "DONE",
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: isPending ? const Color(0xFFCC0000) : Colors.green,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Particulars
          Text(
            item['particulars']?.toString().isNotEmpty == true
                ? item['particulars'].toString()
                : '—',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: Color(0xFF1A1A1A),
            ),
          ),

          const SizedBox(height: 10),

          // Requester
          Row(
            children: [
              const Icon(Icons.person_outline, size: 12, color: Colors.black38),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  "REQUESTER: ${item['requester'] ?? '—'}",
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black45,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Date Sent
          Row(
            children: [
              const Icon(
                Icons.calendar_today_outlined,
                size: 12,
                color: Colors.black38,
              ),
              const SizedBox(width: 4),
              Text(
                item['dateSent']?.toString().isNotEmpty == true
                    ? item['dateSent'].toString()
                    : '—',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.black45,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 12),

          // Action button
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ApprovalDetailPage(item: item),
                  ),
                );
                // Refresh list after returning (document may have been approved)
                if (isPending) {
                  _fetchPending();
                } else {
                  _fetchHistory();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isPending
                    ? const Color(0xFFCC0000)
                    : Colors.green,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isPending
                        ? Icons.rate_review_outlined
                        : Icons.visibility_outlined,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isPending ? "REVIEW" : "VIEW DETAILS",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
