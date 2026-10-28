import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Short application version, without the build number.
///
/// The platform package is checked first. Web builds often have no
/// `version.json`, and the plugin then reports an empty version. The
/// `version:` field in the bundled `pubspec.yaml` is the configured source
/// in that case.
Future<String> loadAppVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    final version = _shortVersion(info.version);
    if (version.isNotEmpty) return version;
  } catch (_) {
    // The plugin is absent or the platform metadata could not be read.
  }
  return _versionFromPubspec();
}

String _shortVersion(String version) {
  return version.split('+').first.trim();
}

Future<String> _versionFromPubspec() async {
  final pubspec = await rootBundle.loadString('pubspec.yaml');
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec);
  final version = _shortVersion(match?.group(1) ?? '');
  if (version.isEmpty) {
    throw const FormatException('Package version is empty.');
  }
  return version;
}
