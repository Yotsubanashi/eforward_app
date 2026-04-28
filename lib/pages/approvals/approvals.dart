import 'dart:async';
import 'dart:convert';
import 'package:eforward_app/config/app_env.dart';
import 'package:eforward_app/pages/dashboard/dashboard.dart';
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final int _selectedIndex = 0;
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String get _baseUrl => AppEnv.apiBaseUrl;
  static const int _pageLimit = 10;

  // ── Pending pagination ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _pendingApprovals = [];
  bool _isLoadingPending = false;
  bool _isLoadingMorePending = false;
  int _pendingPage = 1;
  bool _pendingHasMore = true;
  String? _pendingError;
  final ScrollController _pendingScrollController = ScrollController();

  // ── History pagination ──────────────────────────────────────────────────
  List<Map<String, dynamic>> _historyApprovals = [];
  bool _isLoadingHistory = false;
  bool _isLoadingMoreHistory = false;
  int _historyPage = 1;
  bool _historyHasMore = true;
  String? _historyError;
  final ScrollController _historyScrollController = ScrollController();

  DateTime? _lastUpdatedPending;
  DateTime? _lastUpdatedHistory;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 &&
          _historyApprovals.isEmpty &&
          !_isLoadingHistory) {
        _fetchHistory();
      }
    });

    _pendingScrollController.addListener(_onPendingScroll);
    _historyScrollController.addListener(_onHistoryScroll);

    _fetchPending();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[Approvals] App resumed — refreshing data...');
      _fetchPending();
      if (_tabController.index == 1) {
        _fetchHistory();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _searchController.dispose();
    _pendingScrollController.dispose();
    _historyScrollController.dispose();
    super.dispose();
  }

  void _onPendingScroll() {
    if (_pendingScrollController.position.pixels >=
            _pendingScrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMorePending &&
        _pendingHasMore) {
      _fetchMorePending();
    }
  }

  void _onHistoryScroll() {
    if (_historyScrollController.position.pixels >=
            _historyScrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMoreHistory &&
        _historyHasMore) {
      _fetchMoreHistory();
    }
  }

  // ─── GET /approvals/pending (initial / refresh) ───────────────────────────
  Future<void> _fetchPending({String? search}) async {
    setState(() {
      _isLoadingPending = true;
      _pendingError = null;
      _pendingPage = 1;
      _pendingHasMore = true;
      _pendingApprovals = [];
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

      final queryParams = <String, String>{'page': '1', 'limit': '$_pageLimit'};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      final uri = Uri.parse(
        '$_baseUrl/approvals/pending',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
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
          _pendingHasMore = rawList.length >= _pageLimit;
          _pendingPage = 2;
          _isLoadingPending = false;
          _lastUpdatedPending = DateTime.now();
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

  // ─── GET /approvals/pending (load more) ───────────────────────────────────
  Future<void> _fetchMorePending() async {
    if (_isLoadingMorePending || !_pendingHasMore) return;
    setState(() => _isLoadingMorePending = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      if (token.isEmpty) {
        setState(() => _isLoadingMorePending = false);
        return;
      }

      final queryParams = <String, String>{
        'page': '$_pendingPage',
        'limit': '$_pageLimit',
      };
      if (_searchQuery.isNotEmpty) queryParams['search'] = _searchQuery;

      final uri = Uri.parse(
        '$_baseUrl/approvals/pending',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final rawList = _extractList(decoded);
        final normalized = rawList
            .map((e) => _normalizeItem(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _pendingApprovals.addAll(normalized);
          _pendingHasMore = rawList.length >= _pageLimit;
          _pendingPage++;
          _isLoadingMorePending = false;
        });
      } else {
        setState(() => _isLoadingMorePending = false);
      }
    } catch (e) {
      debugPrint('Fetch more pending error: $e');
      if (mounted) setState(() => _isLoadingMorePending = false);
    }
  }

  // ─── GET /approvals/history (initial / refresh) ───────────────────────────
  Future<void> _fetchHistory({String? search}) async {
    setState(() {
      _isLoadingHistory = true;
      _historyError = null;
      _historyPage = 1;
      _historyHasMore = true;
      _historyApprovals = [];
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

      final queryParams = <String, String>{'page': '1', 'limit': '$_pageLimit'};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;

      final uri = Uri.parse(
        '$_baseUrl/approvals/history',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
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
          _historyApprovals = rawList
              .map((e) => _normalizeItem(e as Map<String, dynamic>))
              .toList();
          _historyHasMore = rawList.length >= _pageLimit;
          _historyPage = 2;
          _isLoadingHistory = false;
          _lastUpdatedHistory = DateTime.now();
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

  // ─── GET /approvals/history (load more) ───────────────────────────────────
  Future<void> _fetchMoreHistory() async {
    if (_isLoadingMoreHistory || !_historyHasMore) return;
    setState(() => _isLoadingMoreHistory = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token') ?? '';
      if (token.isEmpty) {
        setState(() => _isLoadingMoreHistory = false);
        return;
      }

      final queryParams = <String, String>{
        'page': '$_historyPage',
        'limit': '$_pageLimit',
      };
      if (_searchQuery.isNotEmpty) queryParams['search'] = _searchQuery;

      final uri = Uri.parse(
        '$_baseUrl/approvals/history',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        final rawList = _extractList(decoded);
        final normalized = rawList
            .map((e) => _normalizeItem(e as Map<String, dynamic>))
            .toList();
        setState(() {
          _historyApprovals.addAll(normalized);
          _historyHasMore = rawList.length >= _pageLimit;
          _historyPage++;
          _isLoadingMoreHistory = false;
        });
      } else {
        setState(() => _isLoadingMoreHistory = false);
      }
    } catch (e) {
      debugPrint('Fetch more history error: $e');
      if (mounted) setState(() => _isLoadingMoreHistory = false);
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

  // ─── Normalize any status string to a consistent abbreviation ─────────────
  // Returns: 'PND' | 'APV' | 'REJ' | 'OPN' — mirrors _getStatus() in approval_details.dart
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

  // ─── Normalize API fields to consistent keys ──────────────────────────────
  DateTime? _parseApiDate(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      // Keep API clock values exactly as sent (ignore timezone shifting).
      var normalized = raw.trim();
      normalized = normalized.replaceFirst(RegExp(r'(Z|[+-]\d{2}:\d{2})$'), '');
      return DateTime.parse(normalized);
    } catch (_) {
      return null;
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

  String _formatApiDate(String raw) {
    if (raw.isEmpty) return '';
    final dt = _parseApiDate(raw);
    if (dt == null) return raw;
    return _relativeDate(dt);
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

    // Pending endpoint rows contain top-level date_sent.
    // History endpoint rows should show routing.date_updated.
    final isHistoryItem = raw['history_id'] != null;
    final rawDate = isHistoryItem
        ? (routing['date_updated'] ?? raw['date_updated'] ?? raw['created_at'])
                  ?.toString() ??
              ''
        : (raw['date_sent'] ?? routing['date_sent'] ?? routing['date_created'])
                  ?.toString() ??
              '';
    final dateSent = _formatApiDate(rawDate);

    // ── STATUS RESOLUTION (priority order) ───────────────────────────────
    // 1. to_status  — history endpoint action result  (e.g. "APV", "APPROVED")
    // 2. status     — pending endpoint or flat status  (e.g. "PND", "PENDING")
    // 3. routing.status — fallback from routing object
    // 4. action     — some APIs use "action" field     (e.g. "approved")
    // Log all candidate fields so we can debug easily
    debugPrint(
      '[normalizeItem] routing_id=${raw['routing_id']} '
      'to_status=${raw['to_status']} '
      'status=${raw['status']} '
      'routing.status=${routing['status']} '
      'action=${raw['action']}',
    );

    // Priority: routing.status (most authoritative) → raw.status → to_status → action
    String status = _normalizeStatus(routing['status']?.toString());
    if (status.isEmpty) status = _normalizeStatus(raw['status']?.toString());
    if (status.isEmpty) status = _normalizeStatus(raw['to_status']?.toString());
    // Some APIs express history action as a verb — map it to a status code
    if (status.isEmpty) {
      final action = raw['action']?.toString().toUpperCase().trim() ?? '';
      if (action == 'APPROVED' || action == 'APPROVE') status = 'APV';
      if (action == 'REJECTED' || action == 'REJECT') status = 'REJ';
    }
    if (status.isEmpty) status = 'PND'; // absolute last resort

    return {
      ...raw,
      'id': raw['routing_id']?.toString() ?? '',
      'referenceNo': routing['reference_no'] ?? '',
      'particulars': routing['particulars'] ?? '',
      'requester': requesterName.isNotEmpty ? requesterName : '—',
      'dateSent': dateSent,
      'status': status, // always one of: PND | APV | REJ | OPN
      'routing': routing,
      'owner': owner,
    };
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

  String _getLastUpdatedText(DateTime? lastUpdated) {
    if (lastUpdated == null) return 'Loading...';
    final now = DateTime.now();
    final diff = now.difference(lastUpdated);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // ── Status helpers — abbreviation-only input (PND/APV/REJ/OPN) ────────────
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

  String _getStatusLabel(String status) {
    switch (status.toUpperCase().trim()) {
      case 'PND':
        return 'PENDING';
      case 'APV':
        return 'APPROVED';
      case 'OPN':
        return 'OPEN';
      case 'CNL':
        return 'CANCELLED';
      default:
        return status;
    }
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
                                '${_pendingApprovals.length}${_pendingHasMore ? '+' : ''} PENDING',
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
                                  '${_pendingApprovals.length}${_pendingHasMore ? '+' : ''}',
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
                    isLoadingMore: _isLoadingMorePending,
                    hasMore: _pendingHasMore,
                    error: _pendingError,
                    onRefresh: _fetchPending,
                    scrollController: _pendingScrollController,
                  ),
                  _buildCardList(
                    _filteredHistory,
                    isPending: false,
                    isLoading: _isLoadingHistory,
                    isLoadingMore: _isLoadingMoreHistory,
                    hasMore: _historyHasMore,
                    error: _historyError,
                    onRefresh: _fetchHistory,
                    scrollController: _historyScrollController,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigator(
        selectedIndex: _selectedIndex,
        onTap: (index) {
          if (index == 0) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const DashboardPage()),
              (route) => false,
            );
          }
        },
      ),
    );
  }

  Widget _buildCardList(
    List<Map<String, dynamic>> items, {
    required bool isPending,
    required bool isLoading,
    required bool isLoadingMore,
    required bool hasMore,
    required String? error,
    required VoidCallback onRefresh,
    required ScrollController scrollController,
  }) {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFFCC0000)),
            const SizedBox(height: 12),
            const Text(
              "LOADING...",
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.5,
                color: Colors.black38,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Last: ${_getLastUpdatedText(isPending ? _lastUpdatedPending : _lastUpdatedHistory)}',
              style: const TextStyle(
                fontSize: 9,
                color: Colors.black26,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      );
    }

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
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: items.length + 1,
        separatorBuilder: (_, i) => i == items.length - 1
            ? const SizedBox(height: 16)
            : const SizedBox(height: 12),
        itemBuilder: (context, index) {
          // Footer
          if (index == items.length) {
            if (isLoadingMore) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFCC0000),
                    ),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Center(
                child: Column(
                  children: [
                    if (!hasMore)
                      const Text(
                        "— End of list —",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.black26,
                          letterSpacing: 1,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Last updated: ${_getLastUpdatedText(isPending ? _lastUpdatedPending : _lastUpdatedHistory)}',
                      style: const TextStyle(
                        fontSize: 9,
                        color: Colors.black38,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return _buildApprovalCard(items[index], isPending: isPending);
        },
      ),
    );
  }

  Widget _buildApprovalCard(
    Map<String, dynamic> item, {
    required bool isPending,
  }) {
    final status = item['status']?.toString() ?? 'PND';
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

    final statusColor = _getStatusColor(status);
    final statusLabel = _getStatusLabel(status);

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                ApprovalDetailPage(item: item, isFromHistory: !isPending),
          ),
        );
        await Future.delayed(const Duration(milliseconds: 800));
        if (isPending)
          _fetchPending();
        else
          _fetchHistory();
      },
      child: Opacity(
        opacity: status == 'CNL' ? 0.5 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ─────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
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

              // ── Body ───────────────────────────────────────────────────
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      particulars,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                        letterSpacing: 0.2,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Requester
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFEEEEEE),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.person_outline,
                                  size: 13,
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
                        ),
                        const SizedBox(width: 8),
                        // Date
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
                      ],
                    ),
                  ],
                ),
              ),

              // ── Footer ─────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(8),
                  ),
                  border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isPending
                          ? 'Tap to review & take action'
                          : 'Tap to view details',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFBBBBBB),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: Color(0xFFCC0000),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
