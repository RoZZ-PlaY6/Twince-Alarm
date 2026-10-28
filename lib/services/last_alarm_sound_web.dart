import 'dart:convert';
import 'dart:js_interop';

import 'package:twince_alarm/services/last_alarm_sound_api.dart';

@JS('localStorage.getItem')
external JSString? _getLastSound(JSString key);

@JS('localStorage.setItem')
external void _setLastSound(JSString key, JSString value);

class _WebLastAlarmSoundStore implements LastAlarmSoundStore {
  static const _soundKey = 'twince_alarm_last_alarm_sound';
  static const _favoriteKey = 'twince_alarm_favorite_alarm_sounds';

  @override
  Future<String> read() async => _getLastSound(_soundKey.toJS)?.toDart ?? '';

  @override
  Future<void> write(String uri) async {
    _setLastSound(_soundKey.toJS, uri.toJS);
  }

  @override
  Future<List<String>> readFavorites() async {
    final raw = _getLastSound(_favoriteKey.toJS)?.toDart;
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((item) => item.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> writeFavorites(List<String> uris) async {
    _setLastSound(_favoriteKey.toJS, jsonEncode(uris).toJS);
  }
}

LastAlarmSoundStore createLastAlarmSoundStore() => _WebLastAlarmSoundStore();
