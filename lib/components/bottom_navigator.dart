import 'package:eforward_app/Pages/dashboard/dashboard.dart';
import 'package:eforward_app/pages/document/sign.dart';
import 'package:flutter/material.dart';
import 'package:eforward_app/pages/settings/settings.dart';

class BottomNavigator extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const BottomNavigator({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: selectedIndex,
      onTap: (index) => index == 1
          ? Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SignScreen()),
            )
          : index == 2
          ? Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            )
          : index == 0
          ? Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DashboardPage()),
            )
          : onTap(index),
      backgroundColor: Colors.white,
      selectedItemColor: Color(0xFFCC0000),
      unselectedItemColor: Color(0xFF0a0a0a),
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_outlined),
          activeIcon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.draw_outlined),
          activeIcon: Icon(Icons.draw),
          label: 'Sign',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
    );
  }
}
