import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twince_alarm/models/alarm_item.dart';
import 'package:twince_alarm/services/alarm_bridge.dart';
import 'package:twince_alarm/services/last_alarm_sound.dart';
import 'package:twince_alarm/theme/twince_theme.dart';

/// Favorites keep their order from [sounds]. The last selected sound follows
/// that group unless it is already a favorite, and it is never listed twice.
List<AlarmSound> arrangeAlarmSounds(
  List<AlarmSound> sounds, {
  required Set<String> favoriteUris,
  required String pinnedUri,
}) {
  final seen = <String>{};
  final favorites = <AlarmSound>[];
  final rest = <AlarmSound>[];
  AlarmSound? pinned;
  for (final sound in sounds) {
    if (!seen.add(sound.uri)) continue;
    if (favoriteUris.contains(sound.uri)) {
      favorites.add(sound);
    } else if (sound.uri == pinnedUri) {
      pinned = sound;
    } else {
      rest.add(sound);
    }
  }
  return [...favorites, ?pinned, ...rest];
}

class SoundPicker {
  const SoundPicker._();

  static Future<void> open({
    required BuildContext context,
    required List<AlarmSound> sounds,
    required String selectedUri,
    required ValueChanged<AlarmSound> onSelected,
    String title = 'Alarm sound',
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121628),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return _SoundPickerSheet(
          sounds: sounds,
          selectedUri: selectedUri,
          title: title,
          onSelected: onSelected,
        );
      },
    );
    await AlarmBridge.instance.stopPreview();
  }
}

class _SoundPickerSheet extends StatefulWidget {
  const _SoundPickerSheet({
    required this.sounds,
    required this.selectedUri,
    required this.title,
    required this.onSelected,
  });

  final List<AlarmSound> sounds;
  final String selectedUri;
  final String title;
  final ValueChanged<AlarmSound> onSelected;

  @override
  State<_SoundPickerSheet> createState() => _SoundPickerSheetState();
}

class _SoundPickerSheetState extends State<_SoundPickerSheet> {
  final _bridge = AlarmBridge.instance;
  final _preferences = createLastAlarmSoundStore();
  late String _selectedUri = widget.selectedUri;
  List<String> _favoriteUris = const [];
  String _pinnedUri = '';
  bool _preferencesReady = false;
  bool _pinChosenHere = false;
  int _previewToken = 0;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    _previewToken++;
    _bridge.stopPreview();
    super.dispose();
  }

  Future<void> _loadPreferences() async {
    try {
      final favorites = await _preferences.readFavorites();
      final last = await _preferences.read();
      if (!mounted) return;
      setState(() {
        _favoriteUris = favorites;
        if (!_pinChosenHere) _pinnedUri = last;
        _preferencesReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _preferencesReady = true);
    }
  }

  Future<void> _toggleFavorite(AlarmSound sound) async {
    final next = [..._favoriteUris];
    if (next.contains(sound.uri)) {
      next.remove(sound.uri);
    } else {
      next.add(sound.uri);
    }
    setState(() => _favoriteUris = next);
    try {
      await _preferences.writeFavorites(next);
    } catch (_) {
      // The heart still reflects the tap if saving the preference fails.
    }
  }

  Future<void> _preview(AlarmSound sound) async {
    final token = ++_previewToken;
    try {
      await _bridge.previewSound(sound.uri);
    } on PlatformException {
      if (!mounted || token != _previewToken) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not play that sound')),
      );
    }
  }

  List<AlarmSound> get _visibleSounds {
    if (!_preferencesReady) return widget.sounds;
    return arrangeAlarmSounds(
      widget.sounds,
      favoriteUris: _favoriteUris.toSet(),
      pinnedUri: _pinnedUri,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              children: [
                for (final sound in _visibleSounds)
                  ListTile(
                    title: Text(sound.name),
                    trailing: _SoundActions(
                      favorite: _favoriteUris.contains(sound.uri),
                      selected: sound.uri == _selectedUri,
                      onFavorite: () => _toggleFavorite(sound),
                    ),
                    onTap: () {
                      setState(() {
                        _selectedUri = sound.uri;
                        _pinnedUri = sound.uri;
                        _pinChosenHere = true;
                      });
                      widget.onSelected(sound);
                      _preview(sound);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SoundActions extends StatelessWidget {
  const _SoundActions({
    required this.favorite,
    required this.selected,
    required this.onFavorite,
  });

  final bool favorite;
  final bool selected;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: favorite ? 'Remove favorite' : 'Add favorite',
          onPressed: onFavorite,
          icon: Icon(
            favorite ? Icons.favorite : Icons.favorite_border,
            color: favorite ? Colors.red : null,
          ),
        ),
        if (selected)
          const Icon(Icons.check, color: TwinceColors.cyan)
        else
          const SizedBox(width: 24),
      ],
    );
  }
}
