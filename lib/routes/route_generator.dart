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

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());

      case AppRoutes.dashboard:
        final userData = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (_) => DashboardPage(userData: userData),
        );

      case AppRoutes.approvals:
        final initialTabIndex = settings.arguments as int? ?? 0;
        return MaterialPageRoute(
          builder: (_) => ApprovalsPage(initialTabIndex: initialTabIndex),
        );

      case AppRoutes.settings:
        return MaterialPageRoute(builder: (_) => const SettingsPage());

      case AppRoutes.sign:
        return MaterialPageRoute(builder: (_) => const SignScreen());

      case AppRoutes.viewSign:
        return MaterialPageRoute(builder: (_) => const ViewSignPage());

      case AppRoutes.notifications:
        return MaterialPageRoute(builder: (_) => const NotificationsPage());

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
