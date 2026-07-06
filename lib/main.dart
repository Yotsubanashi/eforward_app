import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app.dart';
import 'services/notifications/firebase_notification_service.dart';
import 'services/app_lifecycle_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Loads the correct env file based on build-time define.
  // Example:
  //   flutter build apk --release --dart-define=DOTENV_FILE=.env.ardent
  //   flutter build apk --release --dart-define=DOTENV_FILE=.env.versa
  const dotenvFile = String.fromEnvironment(
    'DOTENV_FILE',
    defaultValue: '.env',
  );
  await dotenv.load(fileName: dotenvFile);

  // 1. Init Firebase first
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 2. Set navigator key BEFORE initialize() so background-tap navigation works
  FirebaseNotificationService.setNavigatorKey(navigatorKey);

  // 3. Init notifications (permissions, channel, listeners, background handler)
  await FirebaseNotificationService().initialize();

  // 4. Initialize app lifecycle service to monitor app lifecycle
  AppLifecycleService().initialize();

  runApp(const MyApp());
}
