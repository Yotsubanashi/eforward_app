import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eforward_app/config/app_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    // No env overrides → AppEnv uses its built-in defaults.
    dotenv.loadFromString(envString: 'DUMMY=1');
    SharedPreferences.setMockInitialValues({});
  });

  test('watermark follows the signed-in domain', () async {
    await AppEnv.selectBackendForEmail('user@versatech.com.ph');
    expect(AppEnv.watermarkAsset, 'assets/images/versa-watermarks.png');
    expect(AppEnv.defaultBranding['color'], '0xFF0056b3');

    await AppEnv.selectBackendForEmail('user@ardentnetworks.com.ph');
    expect(AppEnv.watermarkAsset, 'assets/images/eforward_watermark.png');
    expect(AppEnv.defaultBranding['color'], '0xFFCC0000');
  });

  test('unknown domain routes but uses default watermark/branding', () async {
    await AppEnv.selectBackendForEmail('user@acme.com.ph');
    expect(AppEnv.apiBaseUrl, 'https://eforward-api.acme.com.ph/api');
    expect(AppEnv.watermarkAsset, 'assets/images/eforward_watermark.png');
  });

  test('logout clears the session watermark back to default', () async {
    await AppEnv.selectBackendForEmail('user@versatech.com.ph');
    await AppEnv.clearActiveBackend();
    expect(AppEnv.watermarkAsset, 'assets/images/eforward_watermark.png');
  });
}
