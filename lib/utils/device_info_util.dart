import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

/// Shared device-identification helper used anywhere a device id/model pair
/// needs to be sent to the backend (auth logout/session payloads, FCM token
/// registration, etc.) — previously duplicated verbatim in multiple services.
class DeviceInfoUtil {
  DeviceInfoUtil._();

  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  static Future<Map<String, String>> current() async {
    if (Platform.isAndroid) {
      final info = await _deviceInfo.androidInfo;
      return {
        'deviceId': info.id,
        'deviceModel': '${info.brand} ${info.model}',
      };
    } else if (Platform.isIOS) {
      final info = await _deviceInfo.iosInfo;
      return {
        'deviceId': info.identifierForVendor ?? 'unknown',
        'deviceModel': info.utsname.machine,
      };
    }
    return {'deviceId': 'unknown', 'deviceModel': 'unknown'};
  }
}
