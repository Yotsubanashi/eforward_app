import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'pages/auth/login.dart';
import 'services/firebase_notification_service.dart';
import 'firebase_options.dart'; // ← We'll create this file

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Create navigator key for dialogs
  final navigatorKey = GlobalKey<NavigatorState>();

  // Initialize Firebase Notifications with navigator key
  FirebaseNotificationService.setNavigatorKey(navigatorKey);
  await FirebaseNotificationService().initialize();

  runApp(MyApp(navigatorKey: navigatorKey));
}

class MyApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const MyApp({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      home: const LoginScreen(),
    );
  }
}
