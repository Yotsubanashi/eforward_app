import 'package:flutter/material.dart';
import 'components/status_card.dart';
import 'components/status_ticket.dart';
import 'components/ticket_model.dart';
import 'components/bottom_navigator.dart';

void main() {
  runApp(const MyApp());
}

// ← Step 1: Wrap in a StatelessWidget for MaterialApp
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MainPage(),
    );
  }
}

// ← Step 2: StatefulWidget so setState() works
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0; // ← Step 3: proper type + default value

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.draw, color: Color(0xFFFFB4AC)),
        backgroundColor: const Color(0xFF131313),
        title: const Text(
          "Signing Documents",
          style: TextStyle(
            color: Color(0xFFFFB4AC),
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      backgroundColor: const Color(0xFF131313),
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
              ],
            ),
          ],
        ),
      ),

      // ← Step 4: Use BottomNavigator (your component), not BottomAppBar
      bottomNavigationBar: BottomNavigator(
        selectedIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}