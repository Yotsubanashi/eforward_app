import 'package:flutter/material.dart';
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

  // Dummy data — replace with API later
  final List<Map<String, dynamic>> _pendingApprovals = [];
  final List<Map<String, dynamic>> _historyApprovals = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
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
          icon: const Icon(Icons.arrow_back,
              color: Color(0xFF1A1A1A), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Row(
              children: const [
                Icon(Icons.shield_outlined,
                    color: Color(0xFFCC0000), size: 16),
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
                  const Text(
                    "APPROVALS",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: Color(0xFF1A1A1A),
                    ),
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
                    tabs: const [
                      Tab(text: "PENDING"),
                      Tab(text: "HISTORY"),
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
                        onChanged: (val) =>
                            setState(() => _searchQuery = val),
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFF1A1A1A)),
                        decoration: const InputDecoration(
                          hintText: "Search approvals...",
                          hintStyle:
                              TextStyle(color: Colors.black26, fontSize: 13),
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
                          setState(() => _searchQuery = '');
                        },
                        child: const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Icon(Icons.close,
                              size: 16, color: Colors.black38),
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
                  _buildCardList(_filteredPending, isPending: true),
                  _buildCardList(_filteredHistory, isPending: false),
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

  Widget _buildCardList(List<Map<String, dynamic>> items,
      {required bool isPending}) {
    if (items.isEmpty) {
      return _buildEmptyState(isPending: isPending);
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) =>
          _buildApprovalCard(items[index], isPending: isPending),
    );
  }

  Widget _buildEmptyState({required bool isPending}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 48, color: Colors.black12),
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

  Widget _buildApprovalCard(Map<String, dynamic> item,
      {required bool isPending}) {
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
                item['referenceNo'] ?? '—',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFFCC0000),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

          // Particulars (title)
          Text(
            item['particulars'] ?? '—',
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
              const Icon(Icons.person_outline,
                  size: 12, color: Colors.black38),
              const SizedBox(width: 4),
              Text(
                "REQUESTER: ${item['requester'] ?? '—'}",
                style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black45,
                    letterSpacing: 0.5),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Date Sent
          Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 12, color: Colors.black38),
              const SizedBox(width: 4),
              Text(
                item['dateSent'] ?? '—',
                style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black45,
                    letterSpacing: 0.5),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 12),

          // Action button
          if (isPending)
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton(
                onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ApprovalDetailPage(item: item),
                      ),
                    );
                  },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFCC0000),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.rate_review_outlined,
                        color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      "REVIEW",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Icon(Icons.check_circle_outline,
                    size: 14, color: Colors.green),
                SizedBox(width: 4),
                Text(
                  "COMPLETED",
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.green,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}