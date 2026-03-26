import 'package:flutter/material.dart';
import 'package:eforward_app/components/status_card.dart';
import 'package:eforward_app/components/status_ticket.dart';
import 'package:eforward_app/components/ticket_model.dart';
import 'package:eforward_app/components/bottom_navigator.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.draw, color: Color(0xFFCC0000)),
        backgroundColor: Colors.white,
        title: const Text(
          "Signing Documents",
          style: TextStyle(
            color: Color(0xFFCC0000),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: buildCard("PENDING", "42", const Color(0xFFFFB4AC))),
                const SizedBox(width: 12),
                Expanded(child: buildCard("COMPLETED", "1,342", const Color(0xFF64B5F6))),
              ],
            ),
            const SizedBox(height: 24),
            RecentTicketsSection(
              tickets: const [
                TicketData(
                  id: 'J098479',
                  title: 'Network Failure at Branch 04',
                  createdBy: 'Marcus Chen',
                  dateTime: 'Oct 24, 09:15 AM',
                  progress: 0.0,
                  priority: TicketPriority.high,
                ),
                TicketData(
                  id: 'J098482',
                  title: 'Server Migration Sync',
                  createdBy: 'Sarah Jenkins',
                  dateTime: 'Oct 24, 10:42 AM',
                  progress: 0.45,
                  priority: TicketPriority.standard,
                ),
                TicketData(
                  id: 'J098485',
                  title: 'Software Update Rollout',
                  createdBy: 'David Lee',
                  dateTime: 'Oct 24, 11:30 AM',
                  progress: 0.75,
                  priority: TicketPriority.low,
                ),
                TicketData(
                  id: 'J098485',
                  title: 'Software Update Rollout',
                  createdBy: 'David Lee',
                  dateTime: 'Oct 24, 11:30 AM',
                  progress: 0.75,
                  priority: TicketPriority.low,
                ),
                 TicketData(
                  id: 'J098485',
                  title: 'Software Update Rollout',
                  createdBy: 'David Lee',
                  dateTime: 'Oct 24, 11:30 AM',
                  progress: 0.75,
                  priority: TicketPriority.low,
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigator(
        selectedIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}