import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:twince_alarm/services/app_version.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loadAppVersion returns the short version without the build number',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Twince Alarm',
        packageName: 'com.twince.alarm',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
      expect(await loadAppVersion(), '1.0.0');
    },
  );

  test(
    'loadAppVersion preserves the short version across build numbers',
    () async {
      PackageInfo.setMockInitialValues(
        appName: 'Twince Alarm',
        packageName: 'com.twince.alarm',
        version: '2.3.4',
        buildNumber: '56',
        buildSignature: '',
      );
      expect(await loadAppVersion(), '2.3.4');
    },
  );

  test('an empty platform version uses the pubspec version', () async {
    PackageInfo.setMockInitialValues(
      appName: 'Twince Alarm',
      packageName: 'com.twince.alarm',
      version: '',
      buildNumber: '1',
      buildSignature: '',
    );
    expect(await loadAppVersion(), '1.0.0');
  });
}
