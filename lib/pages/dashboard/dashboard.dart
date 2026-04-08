import 'package:eforward_app/pages/approvals/approvals.dart';
import 'package:flutter/material.dart';
import 'package:eforward_app/components/bottom_navigator.dart';
import 'package:eforward_app/pages/document/document_sign.dart';

class DashboardPage extends StatefulWidget {
  final Map<String, dynamic>? userData;

  const DashboardPage({super.key, this.userData});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final int _selectedIndex = 0;

  late String _userName;
  late String _userEmail;
  late String _userRole;
  late List<Map<String, dynamic>> _userModules;

  @override
  void initState() {
    super.initState();
    _userName = 'User';
    _userEmail = 'N/A';
    _userRole = 'USER';
    _userModules = [];
    _loadUserData();
  }

  void _loadUserData() {
    if (widget.userData != null) {
      debugPrint('Full userData: ${widget.userData}');
      
      // Extract user info from userData['user']
      final user = widget.userData!['user'] as Map<String, dynamic>?;
      if (user != null) {
        _userName = '${user['fname'] ?? ''} ${user['lname'] ?? ''}';
        _userEmail = user['email_add'] ?? 'N/A';
        _userRole = user['role'] ?? 'USER';
      }

      // Extract modules from userData['permissions']['modules']
      final permissions = widget.userData!['permissions'] as Map<String, dynamic>?;
      if (permissions != null) {
        final modulesList = permissions['modules'] as List?;
        _userModules = [];
        if (modulesList != null) {
          for (var module in modulesList) {
            if (module is Map<String, dynamic>) {
              _userModules.add(module);
            }
          }
        }
      }

      debugPrint('User: $_userName, Email: $_userEmail, Role: $_userRole');
      debugPrint('Modules: ${_userModules.length} loaded');
    }
  }

  final List<Map<String, dynamic>> _recentActivity = [
    {
      'id': '#J098479',
      'title': 'QUARTERLY AUDIT REPORT',
      'createdBy': 'RAMON NAPA JR',
      'dateTime': 'OCT 24, 2023 | 09:15 AM',
      'label': 'COMPLIANCE REVIEW',
      'progress': 0.0,
    },
    {
      'id': '#X822704',
      'title': 'OPERATIONAL RISK MEMO',
      'createdBy': 'MARK ANTHONY CANAL',
      'dateTime': 'OCT 23, 2023 | 02:43 PM',
      'label': 'LEGAL VERIFICATION',
      'progress': 0.0,
    },
    {
      'id': '#B441522',
      'title': 'FY24 BUDGET PROPOSAL',
      'createdBy': 'DHARIEL SULAT',
      'dateTime': 'OCT 22, 2023 | 11:00 AM',
      'label': 'FINAL REVIEW',
      'progress': 0.0,
    },
  ];

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
                  Icon(Icons.shield_outlined, color: Color(0xFFCC0000), size: 16),
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

              Text(
                'Email: $_userEmail | Role: $_userRole',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  letterSpacing: 0.5,
                ),
              ),

              const SizedBox(height: 24),

              // Stats Row
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
                      // Left — info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              "PENDING APPROVALS",
                              style: TextStyle(
                                fontSize: 9,
                                color: Color(0xFFCC0000),
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              "14",
                              style: TextStyle(
                                fontSize: 38,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1A1A1A),
                                height: 1,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              "High-priority authorizations requiring immediate executive review.",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.black45,
                                letterSpacing: 0.3,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Right — REVIEW NOW button
                      ElevatedButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ApprovalsPage()),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFCC0000),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
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

   

              // Section Header with View All
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
                      // TODO: navigate to full logs/approvals page
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

              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _recentActivity.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) =>
                    _buildActivityCard(_recentActivity[index]),
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
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentSignScreen(document: item),
        ),
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

            // Left — red accent line
            Container(
              width: 3,
              height: 40,
              color: const Color(0xFFCC0000),
            ),
            const SizedBox(width: 12),

            // Middle — reference no + status
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['id'],
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
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

            // Right — time + chevron
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item['dateTime'],
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black38,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 6),
                const Icon(Icons.chevron_right,
                    color: Colors.black26, size: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}