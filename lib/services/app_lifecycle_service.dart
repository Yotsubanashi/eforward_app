import 'package:flutter/material.dart';

/// Handles app lifecycle events to monitor when the app goes to background/foreground
/// Session remains active during multitasking - user stays logged in
class AppLifecycleService with WidgetsBindingObserver {
  static final AppLifecycleService _instance = AppLifecycleService._internal();

  AppLifecycleService._internal();

  factory AppLifecycleService() => _instance;

  bool _isInitialized = false;

  /// Initialize the lifecycle service and register as observer
  void initialize() {
    if (_isInitialized) return;

    _isInitialized = true;
    WidgetsBinding.instance.addObserver(this);

    debugPrint('🔄 AppLifecycleService initialized - monitoring app lifecycle');
  }

  /// Clean up - remove observer
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isInitialized = false;
    debugPrint('🔄 AppLifecycleService disposed');
  }

  /// Handle lifecycle state changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('📱 App lifecycle state: $state');

    switch (state) {
      case AppLifecycleState.paused:
        // App goes to background (multitasking) - KEEP SESSION ALIVE
        debugPrint('⏸️ App paused - session remains active');
        break;

      case AppLifecycleState.resumed:
        // App comes to foreground
        debugPrint('▶️ App resumed');
        break;

      case AppLifecycleState.inactive:
        // Transition state
        debugPrint('⏳ App inactive');
        break;

      case AppLifecycleState.hidden:
        // For Flutter 3.13+ - app is hidden but still in memory
        debugPrint('🙈 App hidden - session remains active');
        break;

      case AppLifecycleState.detached:
        // Only logout when app process is actually terminated
        // This typically happens on force stop, not normal multitasking
        debugPrint('⚠️ App detached - process terminating');
        // Session will be cleared on next app launch if needed
        break;
    }
  }
}
