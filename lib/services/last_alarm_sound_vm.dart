import 'package:twince_alarm/services/alarm_bridge.dart';
import 'package:twince_alarm/services/last_alarm_sound_api.dart';

class BridgeLastAlarmSoundStore implements LastAlarmSoundStore {
  @override
  Future<String> read() => AlarmBridge.instance.loadLastAlarmSound();

  @override
  Future<void> write(String uri) =>
      AlarmBridge.instance.saveLastAlarmSound(uri);

  @override
  Future<List<String>> readFavorites() =>
      AlarmBridge.instance.loadFavoriteAlarmSounds();

  @override
  Future<void> writeFavorites(List<String> uris) =>
      AlarmBridge.instance.saveFavoriteAlarmSounds(uris);
}

LastAlarmSoundStore createLastAlarmSoundStore() => BridgeLastAlarmSoundStore();
