/// Remembers the alarm tone chosen for the next new alarm, and favorite tones.
abstract class LastAlarmSoundStore {
  Future<String> read();

  Future<void> write(String uri);

  Future<List<String>> readFavorites();

  Future<void> writeFavorites(List<String> uris);
}
