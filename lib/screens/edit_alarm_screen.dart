import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twince_alarm/models/alarm_item.dart';
import 'package:twince_alarm/screens/ringing_screen.dart';
import 'package:twince_alarm/services/alarm_bridge.dart';
import 'package:twince_alarm/theme/twince_theme.dart';
import 'package:twince_alarm/widgets/sound_picker.dart';

class EditAlarmScreen extends StatefulWidget {
  const EditAlarmScreen({super.key, this.alarm});

  final AlarmItem? alarm;

  @override
  State<EditAlarmScreen> createState() => _EditAlarmScreenState();
}

class _EditAlarmScreenState extends State<EditAlarmScreen> {
  final _bridge = AlarmBridge.instance;
  late int _hour;
  late int _minute;
  late bool _vibrate;
  late String _soundUri;
  late String _soundName;
  late List<int> _days;
  late final TextEditingController _label;
  late final TextEditingController _subtitle;
  List<AlarmSound> _sounds = const [AlarmSound(name: 'Default alarm', uri: '')];
  bool _saving = false;
  bool _wheelsReady = false;
  bool _use24 = true;

  @override
  void initState() {
    super.initState();
    final alarm = widget.alarm;
    final now = DateTime.now();
    _hour = alarm?.hour ?? now.hour;
    _minute = alarm?.minute ?? now.minute;
    _vibrate = alarm?.vibrate ?? true;
    _soundUri = alarm?.soundUri ?? '';
    _soundName = 'Default alarm';
    _days = [...?alarm?.repeatDays];
    _label = TextEditingController(text: alarm?.label ?? '');
    _subtitle = TextEditingController(
      text: alarm?.subtitle ?? 'Time to start your task',
    );
    _loadSounds();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    _wheelsReady = true;
  }

  @override
  void dispose() {
    _label.dispose();
    _subtitle.dispose();
    _bridge.stopPreview();
    super.dispose();
  }

  Future<void> _loadSounds() async {
    try {
      final sounds = await _bridge.listSounds();
      if (!mounted || sounds.isEmpty) return;
      setState(() {
        _sounds = sounds;
        final match = sounds.where((sound) => sound.uri == _soundUri);
        _soundName = match.isEmpty
            ? (_soundUri.isEmpty ? 'Default alarm' : 'Custom tone')
            : match.first.name;
      });
    } on PlatformException {
      // The default tone stays selected.
    }
  }

  Future<void> _pickSound() {
    return SoundPicker.open(
      context: context,
      sounds: _sounds,
      selectedUri: _soundUri,
      onSelected: (sound) {
        setState(() {
          _soundUri = sound.uri;
          _soundName = sound.name;
        });
      },
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final draft = AlarmItem(
      id: widget.alarm?.id ?? 0,
      hour: _hour,
      minute: _minute,
      label: _label.text.trim().isEmpty ? 'Alarm' : _label.text.trim(),
      subtitle: _subtitle.text.trim().isEmpty
          ? 'Time to start your task'
          : _subtitle.text.trim(),
      enabled: widget.alarm?.enabled ?? true,
      vibrate: _vibrate,
      soundUri: _soundUri,
      repeatDays: _days,
      weekTags: widget.alarm?.weekTags ?? const [],
    );
    try {
      final saved = await _bridge.upsert(draft);
      if (!mounted) return;
      if (saved.scheduleError.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Saved. Allow exact alarms so it can fire on time.'),
          ),
        );
      }
      Navigator.pop(context, true);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Could not save the alarm')),
      );
    }
  }

  Future<void> _delete() async {
    final alarm = widget.alarm;
    if (alarm == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete alarm?'),
          content: Text(alarm.label),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    try {
      await _bridge.delete(alarm.id);
      if (mounted) Navigator.pop(context, true);
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Could not delete the alarm')),
      );
    }
  }

  void _toggleDay(int day) {
    setState(() {
      if (_days.contains(day)) {
        _days = _days.where((item) => item != day).toList();
      } else {
        _days = [..._days, day]..sort();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.alarm != null;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TwinceBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: Text(
                        editing ? 'Edit alarm' : 'Add alarm',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (editing)
                      IconButton(
                        onPressed: _delete,
                        icon: const Icon(
                          Icons.delete_outline,
                          color: TwinceColors.muted,
                        ),
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    if (_wheelsReady)
                      _TimeWheels(
                        hour: _hour,
                        minute: _minute,
                        use24: _use24,
                        onHour: (value) => setState(() => _hour = value),
                        onMinute: (value) => setState(() => _minute = value),
                      ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        formatClock(_hour, _minute, use24: _use24),
                        style: const TextStyle(
                          color: TwinceColors.cyan,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _field(_label, 'Label', 'Morning workout'),
                    const SizedBox(height: 12),
                    _field(_subtitle, 'Message', 'Time to start your task'),
                    const SizedBox(height: 18),
                    const Text(
                      'Repeat',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (index) {
                        final day = index + 1;
                        const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                        final selected = _days.contains(day);
                        return GestureDetector(
                          onTap: () => _toggleDay(day),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: selected
                                  ? TwinceColors.cyan
                                  : Colors.transparent,
                              border: Border.all(
                                color: selected
                                    ? TwinceColors.cyan
                                    : TwinceColors.stroke,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: TwinceColors.cyan.withValues(
                                          alpha: 0.35,
                                        ),
                                        blurRadius: 10,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              letters[index],
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: selected
                                    ? const Color(0xFF041018)
                                    : TwinceColors.text,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      repeatLabel(_days),
                      style: const TextStyle(color: TwinceColors.muted),
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Sound'),
                      subtitle: Text(
                        _soundName,
                        style: const TextStyle(color: TwinceColors.muted),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: TwinceColors.muted,
                      ),
                      onTap: _pickSound,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Vibrate'),
                      value: _vibrate,
                      onChanged: (value) => setState(() => _vibrate = value),
                      thumbColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return TwinceColors.bg0;
                        }
                        return TwinceColors.muted;
                      }),
                      trackColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return TwinceColors.cyan;
                        }
                        return const Color(0xFF2A3148);
                      }),
                      trackOutlineColor: const WidgetStatePropertyAll(
                        Colors.transparent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            fullscreenDialog: true,
                            builder: (_) => RingingScreen(
                              hour: _hour,
                              minute: _minute,
                              title: _label.text.trim().isEmpty
                                  ? 'Alarm'
                                  : _label.text.trim(),
                              subtitle: _subtitle.text.trim().isEmpty
                                  ? 'Time to start your task'
                                  : _subtitle.text.trim(),
                              alarmId: widget.alarm?.id ?? 0,
                              vibrate: _vibrate,
                              soundUri: _soundUri,
                              preview: true,
                            ),
                          ),
                        );
                      },
                      child: const Text('Preview ringing screen'),
                    ),
                    const SizedBox(height: 12),
                    _SaveButton(saving: _saving, onPressed: _save),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, String hint) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: TwinceColors.text),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: TwinceColors.muted),
        hintStyle: const TextStyle(color: TwinceColors.stroke),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: TwinceColors.stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: TwinceColors.cyan),
        ),
      ),
    );
  }
}

class _TimeWheels extends StatelessWidget {
  const _TimeWheels({
    required this.hour,
    required this.minute,
    required this.use24,
    required this.onHour,
    required this.onMinute,
  });

  final int hour;
  final int minute;
  final bool use24;
  final ValueChanged<int> onHour;
  final ValueChanged<int> onMinute;

  @override
  Widget build(BuildContext context) {
    final hourLabels = use24
        ? [
            for (var value = 0; value < 24; value++)
              value.toString().padLeft(2, '0'),
          ]
        : [
            for (var value = 1; value <= 12; value++)
              value.toString().padLeft(2, '0'),
          ];
    final minuteLabels = [
      for (var value = 0; value < 60; value++) value.toString().padLeft(2, '0'),
    ];
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    final pm = hour >= 12;
    return SizedBox(
      height: 188,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 52,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: TwinceColors.cyan.withValues(alpha: 0.35),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _Drum(
                  labels: hourLabels,
                  initialIndex: use24 ? hour : hour12 - 1,
                  onChanged: (index) {
                    if (use24) {
                      onHour(index);
                    } else {
                      onHour(_to24(index + 1, pm));
                    }
                  },
                ),
              ),
              const Text(
                ':',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w300),
              ),
              Expanded(
                child: _Drum(
                  labels: minuteLabels,
                  initialIndex: minute,
                  onChanged: onMinute,
                ),
              ),
              if (!use24)
                SizedBox(
                  width: 72,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _PeriodChip(
                        label: 'AM',
                        selected: !pm,
                        onTap: () => onHour(_to24(hour12, false)),
                      ),
                      const SizedBox(height: 8),
                      _PeriodChip(
                        label: 'PM',
                        selected: pm,
                        onTap: () => onHour(_to24(hour12, true)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static int _to24(int hour12, bool pm) {
    if (pm) return hour12 == 12 ? 12 : hour12 + 12;
    return hour12 == 12 ? 0 : hour12;
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? TwinceColors.cyan : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? TwinceColors.cyan : TwinceColors.stroke,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: selected ? const Color(0xFF041018) : TwinceColors.text,
          ),
        ),
      ),
    );
  }
}

class _Drum extends StatefulWidget {
  const _Drum({
    required this.labels,
    required this.initialIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int initialIndex;
  final ValueChanged<int> onChanged;

  @override
  State<_Drum> createState() => _DrumState();
}

class _DrumState extends State<_Drum> {
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(initialItem: widget.initialIndex);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListWheelScrollView.useDelegate(
      controller: _controller,
      itemExtent: 52,
      diameterRatio: 1.5,
      perspective: 0.003,
      overAndUnderCenterOpacity: 0.4,
      physics: const FixedExtentScrollPhysics(),
      onSelectedItemChanged: (index) {
        final length = widget.labels.length;
        final normalized = ((index % length) + length) % length;
        widget.onChanged(normalized);
      },
      childDelegate: ListWheelChildLoopingListDelegate(
        children: [
          for (final label in widget.labels)
            Center(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w400,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saving, required this.onPressed});

  final bool saving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [TwinceColors.blue, TwinceColors.cyan],
        ),
        boxShadow: [
          BoxShadow(
            color: TwinceColors.cyan.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: saving ? null : onPressed,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 54,
            child: Center(
              child: saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF041018),
                      ),
                    )
                  : const Text(
                      'Save alarm',
                      style: TextStyle(
                        color: Color(0xFF041018),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
