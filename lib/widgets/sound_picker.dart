import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twince_alarm/models/alarm_item.dart';
import 'package:twince_alarm/services/alarm_bridge.dart';
import 'package:twince_alarm/theme/twince_theme.dart';

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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
  late String _selectedUri = widget.selectedUri;
  int _previewToken = 0;

  @override
  void dispose() {
    _previewToken++;
    _bridge.stopPreview();
    super.dispose();
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
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              children: [
                for (final sound in widget.sounds)
                  ListTile(
                    title: Text(sound.name),
                    trailing: sound.uri == _selectedUri
                        ? const Icon(Icons.check, color: TwinceColors.cyan)
                        : null,
                    onTap: () {
                      setState(() => _selectedUri = sound.uri);
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
