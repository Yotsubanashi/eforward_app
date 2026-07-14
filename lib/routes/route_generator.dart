import 'package:flutter/material.dart';

import '../screens/approvals/approvals_screen.dart';
import '../screens/auth/change_password_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/document/sign_screen.dart';
import '../screens/document/view_sign_screen.dart';
import '../screens/legal/privacy_policy_screen.dart';
import '../screens/notifications/notification_settings_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/settings/settings_screen.dart';
import 'app_routes.dart';

/// Centralized [MaterialApp.onGenerateRoute] handler for the screens listed
/// in [AppRoutes]. Screens outside that set keep navigating via direct
/// `Navigator.push(MaterialPageRoute(...))` calls elsewhere in the app.
class RouteGenerator {
  RouteGenerator._();

  /// Instant cross-fade used for switching between the bottom-navigation tabs.
  ///
  /// Bottom-nav destinations are peers, not a hierarchy, so the default
  /// left/right page-slide (the "book" flip) is the wrong metaphor and feels
  /// jarring on mobile. A short fade — with no slide — matches native tab
  /// switching (Instagram, Twitter, etc.).
  static PageRouteBuilder<dynamic> _tabRoute(
    Widget page,
    RouteSettings settings,
  ) {
    return PageRouteBuilder<dynamic>(
      settings: settings,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());

      case AppRoutes.dashboard:
        final userData = settings.arguments as Map<String, dynamic>?;
        return _tabRoute(DashboardPage(userData: userData), settings);

      case AppRoutes.approvals:
        final initialTabIndex = settings.arguments as int? ?? 0;
        return MaterialPageRoute(
          builder: (_) => ApprovalsPage(initialTabIndex: initialTabIndex),
        );

      case AppRoutes.settings:
        return _tabRoute(const SettingsPage(), settings);

      case AppRoutes.sign:
        return _tabRoute(const SignScreen(), settings);

      case AppRoutes.viewSign:
        return _tabRoute(const ViewSignPage(), settings);

      case AppRoutes.notifications:
        return _tabRoute(const NotificationsPage(), settings);

      case AppRoutes.notificationSettings:
        return MaterialPageRoute(builder: (_) => const NotificationTestPage());

      case AppRoutes.forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());

      case AppRoutes.changePassword:
        return MaterialPageRoute(builder: (_) => const ChangePasswordScreen());

      case AppRoutes.privacyPolicy:
        return MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen());

      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(child: Text('No route defined for ${settings.name}')),
          ),
        );
    }
  }
}
