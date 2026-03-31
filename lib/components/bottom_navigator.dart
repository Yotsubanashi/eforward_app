import 'package:eforward_app/pages/dashboard/dashboard.dart';
import 'package:eforward_app/pages/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/pages/document/sign.dart';
import 'package:eforward_app/pages/document/view_sign.dart';

class BottomNavigator extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const BottomNavigator({
    super.key,
    required this.selectedIndex,
    required this.onTap,
  });

  Future<void> _navigate(BuildContext context, int index) async {
    // Don't navigate if already on the same tab
    if (index == selectedIndex) return;

    switch (index) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DashboardPage()),
        );
        break;
      case 1:
        final prefs = await SharedPreferences.getInstance();
        final hasSignature = prefs.getBool('has_signature') ?? false;
        if (context.mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  hasSignature ? const ViewSignPage() : const SignScreen(),
            ),
          );
        }
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const SettingsPage()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: selectedIndex,
      onTap: (index) => _navigate(context, index), // 👈 handles all tabs
      backgroundColor: Colors.white,
      selectedItemColor: const Color(0xFFCC0000),
      unselectedItemColor: const Color(0xFFAAAAAA),
      selectedLabelStyle: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
      unselectedLabelStyle: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
      ),
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard_outlined),
          activeIcon: Icon(Icons.dashboard),
          label: 'DASHBOARD',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.draw_outlined),
          activeIcon: Icon(Icons.draw),
          label: 'SIGN',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings),
          label: 'SETTINGS',
        ),
      ],
    );
  }
}
