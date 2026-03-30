import 'package:flutter/material.dart';
import 'package:eforward_app/components/bottom_navigator.dart';
import 'package:eforward_app/pages/document/document_sign.dart'; // 👈 import separate file

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 0;

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

              const Text(
                "WELCOME BACK,\nMark",
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  height: 1.1,
                  color: Color(0xFF1A1A1A),
                ),
              ),

              const SizedBox(height: 24),

              // Stats Row
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFE8E8E8)),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: const BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: Color(0xFFCC0000),
                                width: 3,
                              ),
                            ),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "REQUIRES ACTION",
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Color(0xFFCC0000),
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: const [
                                  Text(
                                    "14",
                                    style: TextStyle(
                                      fontSize: 38,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF1A1A1A),
                                      height: 1,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(
                                    Icons.arrow_forward,
                                    size: 16,
                                    color: Color(0xFFCC0000),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                "PENDING\nAPPROVALS",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black45,
                                  letterSpacing: 0.5,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(width: 1, color: const Color(0xFFE8E8E8)),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                "VERIFIED TODAY",
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.black38,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                "28",
                                style: TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF1A1A1A),
                                  height: 1,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                "DOCUMENTS\nPROCESSED",
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.black45,
                                  letterSpacing: 0.5,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              const Text(
                "FOR SIGNING DOCUMENTS",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                  color: Color(0xFF1A1A1A),
                ),
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
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> item) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              DocumentSignScreen(document: item), // 👈 goes to separate page
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE8E8E8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item['id'],
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFFCC0000),
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item['title'],
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.black26,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  size: 12,
                  color: Colors.black38,
                ),
                const SizedBox(width: 4),
                Text(
                  "CREATED BY: ${item['createdBy']}",
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black45,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 12,
                  color: Colors.black38,
                ),
                const SizedBox(width: 4),
                Text(
                  item['dateTime'],
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item['label'],
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black45,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  "${(item['progress'] * 100).toInt()}%",
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black45,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Stack(
              children: [
                Container(
                  height: 4,
                  width: double.infinity,
                  color: const Color(0xFFEEEEEE),
                ),
                FractionallySizedBox(
                  widthFactor: item['progress'],
                  child: Container(height: 4, color: const Color(0xFFCC0000)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
