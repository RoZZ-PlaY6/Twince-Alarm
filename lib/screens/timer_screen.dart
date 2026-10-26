import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twince_alarm/models/alarm_item.dart';
import 'package:twince_alarm/models/timer_session.dart';
import 'package:twince_alarm/screens/ringing_screen.dart';
import 'package:twince_alarm/services/alarm_bridge.dart';
import 'package:twince_alarm/theme/twince_theme.dart';
import 'package:twince_alarm/widgets/sound_picker.dart';

class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key});

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  final _bridge = AlarmBridge.instance;
  final _session = TimerSession();
  List<AlarmSound> _sounds = const [AlarmSound(name: 'Default alarm', uri: '')];
  Timer? _ticker;
  bool _ringing = false;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _armTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _onTick() {
    final finished = _session.tick();
    if (!mounted) return;
    setState(() {});
    if (finished) {
      _ticker?.cancel();
      _openCompletion();
    }
  }

  Future<void> _openCompletion() async {
    if (_ringing || !mounted) return;
    _ringing = true;
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => RingingScreen(
          hour: 0,
          minute: 0,
          title: 'Timer',
          subtitle: 'Time is up',
          soundUri: _session.soundUri,
          durationLabel: formatTimerDuration(Duration.zero),
          statusLabel: 'Timer',
          playSoundOnOpen: true,
        ),
      ),
    );
    _ringing = false;
    if (!mounted) return;
    setState(() {
      if (result == 'Snoozed 5 min') {
        _session.startFor(const Duration(minutes: 5));
      } else if (result == 'Snoozed 10 min') {
        _session.startFor(const Duration(minutes: 10));
      } else if (result == 'Alarm restarted') {
        _session.start();
      } else {
        _session.reset();
      }
    });
    if (_session.running) _armTicker();
  }

  Future<void> _pickSound() async {
    try {
      final loaded = await _bridge.listSounds();
      if (loaded.isNotEmpty) _sounds = loaded;
    } on PlatformException {
      // Keep the sounds already available, including the default tone.
    }
    if (!mounted) return;
    await SoundPicker.open(
      context: context,
      sounds: _sounds,
      selectedUri: _session.soundUri,
      title: 'Timer sound',
      onSelected: (sound) {
        setState(() {
          _session.selectSound(name: sound.name, uri: sound.uri);
        });
      },
    );
  }

  void _start() {
    if (!_session.start()) return;
    setState(() {});
    _armTicker();
  }

  void _pause() {
    setState(_session.pause);
    _ticker?.cancel();
  }

  void _resume() {
    setState(_session.resume);
    if (_session.running) _armTicker();
  }

  void _reset() {
    _ticker?.cancel();
    setState(_session.reset);
  }

  @override
  Widget build(BuildContext context) {
    final idle = !_session.running && !_session.paused;
    final label = formatTimerDuration(_session.shown);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TwinceBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight - 24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _TimerPanel(
                        label: label,
                        idle: idle,
                        paused: _session.paused,
                        canStart: _session.canStart,
                        soundName: _session.soundName,
                        hours: _session.selected.inHours,
                        minutes: _session.selected.inMinutes.remainder(60),
                        seconds: _session.selected.inSeconds.remainder(60),
                        onAddHour: () => setState(() => _session.change(hours: 1)),
                        onRemoveHour: () => setState(() => _session.change(hours: -1)),
                        onAddMinute: () => setState(() => _session.change(minutes: 1)),
                        onRemoveMinute: () => setState(() => _session.change(minutes: -1)),
                        onAddSecond: () => setState(() => _session.change(seconds: 1)),
                        onRemoveSecond: () => setState(() => _session.change(seconds: -1)),
                        onPreset: (duration) => setState(() => _session.setDuration(duration)),
                        onSound: _pickSound,
                        onStart: _start,
                        onPause: _pause,
                        onResume: _resume,
                        onReset: _reset,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TimerPanel extends StatelessWidget {
  const _TimerPanel({
    required this.label,
    required this.idle,
    required this.paused,
    required this.canStart,
    required this.soundName,
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.onAddHour,
    required this.onRemoveHour,
    required this.onAddMinute,
    required this.onRemoveMinute,
    required this.onAddSecond,
    required this.onRemoveSecond,
    required this.onPreset,
    required this.onSound,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onReset,
  });

  final String label;
  final bool idle;
  final bool paused;
  final bool canStart;
  final String soundName;
  final int hours;
  final int minutes;
  final int seconds;
  final VoidCallback onAddHour;
  final VoidCallback onRemoveHour;
  final VoidCallback onAddMinute;
  final VoidCallback onRemoveMinute;
  final VoidCallback onAddSecond;
  final VoidCallback onRemoveSecond;
  final ValueChanged<Duration> onPreset;
  final VoidCallback onSound;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: const Color(0xCC070B18),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: TwinceColors.cyan.withValues(alpha: 0.38)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Timer', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF10182C),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: TwinceColors.cyan, width: 1.6),
                boxShadow: [
                  BoxShadow(color: TwinceColors.cyan.withValues(alpha: 0.18), blurRadius: 18),
                ],
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w300,
                    height: 1,
                    letterSpacing: 1,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (idle) ...[
            Row(
              children: [
                Expanded(
                  child: _DialCard(
                    icon: Icons.schedule,
                    label: 'Hours',
                    value: hours,
                    addTip: 'Add hour',
                    removeTip: 'Remove hour',
                    onAdd: onAddHour,
                    onRemove: onRemoveHour,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DialCard(
                    icon: Icons.timelapse,
                    label: 'Minutes',
                    value: minutes,
                    addTip: 'Add minute',
                    removeTip: 'Remove minute',
                    onAdd: onAddMinute,
                    onRemove: onRemoveMinute,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DialCard(
                    icon: Icons.timer_outlined,
                    label: 'Seconds',
                    value: seconds,
                    addTip: 'Add second',
                    removeTip: 'Remove second',
                    onAdd: onAddSecond,
                    onRemove: onRemoveSecond,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _QuickChip(label: '00:10:00', onTap: () => onPreset(const Duration(minutes: 10)))),
                const SizedBox(width: 8),
                Expanded(child: _QuickChip(label: '00:15:00', onTap: () => onPreset(const Duration(minutes: 15)))),
                const SizedBox(width: 8),
                Expanded(child: _QuickChip(label: '00:30:00', onTap: () => onPreset(const Duration(minutes: 30)))),
              ],
            ),
            const SizedBox(height: 12),
            Material(
              color: const Color(0xFF161B2E),
              elevation: 3,
              shadowColor: Colors.black,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: onSound,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: TwinceColors.stroke),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active_outlined, color: TwinceColors.cyan),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Sound', style: TextStyle(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(soundName, style: const TextStyle(color: TwinceColors.muted, fontSize: 13)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: TwinceColors.muted),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _StartButton(enabled: canStart, onPressed: onStart),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _ControlButton(
                    label: paused ? 'Resume' : 'Pause',
                    filled: true,
                    onPressed: paused ? onResume : onPause,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ControlButton(
                    label: 'Reset',
                    filled: false,
                    onPressed: onReset,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DialCard extends StatelessWidget {
  const _DialCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.addTip,
    required this.removeTip,
    required this.onAdd,
    required this.onRemove,
  });

  final IconData icon;
  final String label;
  final int value;
  final String addTip;
  final String removeTip;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF101426),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TwinceColors.cyan.withValues(alpha: 0.32)),
      ),
      child: Column(
        children: [
          Icon(icon, color: TwinceColors.cyan, size: 20),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: TwinceColors.muted, fontSize: 12)),
          IconButton(
            tooltip: addTip,
            visualDensity: VisualDensity.compact,
            onPressed: onAdd,
            icon: const Icon(Icons.add, color: TwinceColors.cyan),
          ),
          Text(
            value.toString().padLeft(2, '0'),
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, fontFeatures: [
              FontFeature.tabularFigures(),
            ]),
          ),
          IconButton(
            tooltip: removeTip,
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: const Icon(Icons.remove, color: TwinceColors.cyan),
          ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF12182A),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: TwinceColors.cyan.withValues(alpha: 0.55)),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(colors: [TwinceColors.blue, TwinceColors.cyan]),
          boxShadow: [
            BoxShadow(color: TwinceColors.cyan.withValues(alpha: 0.28), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(18),
            child: const SizedBox(
              height: 56,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow_rounded, color: Color(0xFF041018), size: 26),
                  SizedBox(width: 6),
                  Text(
                    'Start',
                    style: TextStyle(color: Color(0xFF041018), fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.label, required this.filled, required this.onPressed});

  final String label;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? TwinceColors.cyan : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: filled ? TwinceColors.cyan : TwinceColors.stroke),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: filled ? const Color(0xFF041018) : TwinceColors.text,
            ),
          ),
        ),
      ),
    );
  }
}
