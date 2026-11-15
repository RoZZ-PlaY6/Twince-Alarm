import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
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

  void _setParts({int? hours, int? minutes, int? seconds}) {
    final current = _session.selected;
    setState(
      () => _session.setDuration(
        Duration(
          hours: hours ?? current.inHours,
          minutes: minutes ?? current.inMinutes.remainder(60),
          seconds: seconds ?? current.inSeconds.remainder(60),
        ),
      ),
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
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 24,
                  ),
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
                        onHours: (value) => _setParts(hours: value),
                        onMinutes: (value) => _setParts(minutes: value),
                        onSeconds: (value) => _setParts(seconds: value),
                        onPreset: (duration) =>
                            setState(() => _session.setDuration(duration)),
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
    required this.onHours,
    required this.onMinutes,
    required this.onSeconds,
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
  final ValueChanged<int> onHours;
  final ValueChanged<int> onMinutes;
  final ValueChanged<int> onSeconds;
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
          const Text(
            'Timer',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          if (!idle)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF10182C),
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: TwinceColors.cyan, width: 1.6),
                  boxShadow: [
                    BoxShadow(
                      color: TwinceColors.cyan.withValues(alpha: 0.18),
                      blurRadius: 18,
                    ),
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
          if (!idle) const SizedBox(height: 18),
          if (idle) ...[
            _DurationWheels(
              hours: hours,
              minutes: minutes,
              seconds: seconds,
              onHours: onHours,
              onMinutes: onMinutes,
              onSeconds: onSeconds,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _QuickChip(
                    label: '00:10:00',
                    onTap: () => onPreset(const Duration(minutes: 10)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickChip(
                    label: '00:15:00',
                    onTap: () => onPreset(const Duration(minutes: 15)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickChip(
                    label: '00:30:00',
                    onTap: () => onPreset(const Duration(minutes: 30)),
                  ),
                ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: TwinceColors.stroke),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.notifications_active_outlined,
                        color: TwinceColors.cyan,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Sound',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              soundName,
                              style: const TextStyle(
                                color: TwinceColors.muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: TwinceColors.muted,
                      ),
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

class _DurationWheels extends StatelessWidget {
  const _DurationWheels({
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.onHours,
    required this.onMinutes,
    required this.onSeconds,
  });
  final int hours, minutes, seconds;
  final ValueChanged<int> onHours, onMinutes, onSeconds;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          children: [
            Expanded(
              child: Center(
                child: Text(
                  'Hours',
                  style: TextStyle(color: TwinceColors.muted),
                ),
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Center(
                child: Text(
                  'Minutes',
                  style: TextStyle(color: TwinceColors.muted),
                ),
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Center(
                child: Text(
                  'Seconds',
                  style: TextStyle(color: TwinceColors.muted),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 150,
          child: Row(
            children: [
              Expanded(
                child: _NumberWheel(
                  label: 'Hours',
                  value: hours,
                  max: TimerSession.maxHours,
                  onChanged: onHours,
                ),
              ),
              const _WheelColon(),
              Expanded(
                child: _NumberWheel(
                  label: 'Minutes',
                  value: minutes,
                  max: 59,
                  onChanged: onMinutes,
                ),
              ),
              const _WheelColon(),
              Expanded(
                child: _NumberWheel(
                  label: 'Seconds',
                  value: seconds,
                  max: 59,
                  onChanged: onSeconds,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WheelColon extends StatelessWidget {
  const _WheelColon();
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 14,
    child: Center(
      child: Text(
        ':',
        style: TextStyle(fontSize: 30, height: 1, color: TwinceColors.cyan),
      ),
    ),
  );
}

class _NumberWheel extends StatefulWidget {
  const _NumberWheel({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });
  final String label;
  final int value, max;
  final ValueChanged<int> onChanged;
  @override
  State<_NumberWheel> createState() => _NumberWheelState();
}

class _NumberWheelState extends State<_NumberWheel> {
  bool _synchronizing = false;
  int? _mouseTarget;
  int _mouseGeneration = 0;
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(initialItem: widget.value);

  @override
  void didUpdateWidget(_NumberWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value &&
        _controller.hasClients &&
        _controller.selectedItem != widget.value) {
      _synchronizing = true;
      try {
        _controller.jumpToItem(widget.value);
      } finally {
        _synchronizing = false;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _select(int value) {
    _mouseTarget = null;
    _mouseGeneration++;
    final next = value.clamp(0, widget.max);
    if (_controller.hasClients) {
      _controller.animateToItem(
        next,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  void _mouseNotch(int direction) {
    if (!_controller.hasClients) return;
    final target = ((_mouseTarget ?? _controller.selectedItem) + direction)
        .clamp(0, widget.max);
    _mouseTarget = target;
    final generation = ++_mouseGeneration;
    _controller
        .animateToItem(
          target,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        )
        .whenComplete(() {
          if (mounted && generation == _mouseGeneration) _mouseTarget = null;
        });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      value: widget.value.toString().padLeft(2, '0'),
      increasedValue: (widget.value + 1)
          .clamp(0, widget.max)
          .toString()
          .padLeft(2, '0'),
      decreasedValue: (widget.value - 1)
          .clamp(0, widget.max)
          .toString()
          .padLeft(2, '0'),
      onIncrease: () => _select(widget.value + 1),
      onDecrease: () => _select(widget.value - 1),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _select(widget.value - 1);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _select(widget.value + 1);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(
          children: [
            ExcludeSemantics(
              child: ListWheelScrollView.useDelegate(
                key: ValueKey('wheel-${widget.label.toLowerCase()}'),
                controller: _controller,
                itemExtent: 50,
                physics: const _TimerWheelPhysics(
                  parent: ClampingScrollPhysics(),
                ),
                diameterRatio: 2.5,
                perspective: 0.002,
                onSelectedItemChanged: (value) {
                  if (!_synchronizing) widget.onChanged(value);
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: widget.max + 1,
                  builder: (context, index) {
                    final selected = index == widget.value;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _select(index),
                      child: Center(
                        child: Text(
                          index.toString().padLeft(2, '0'),
                          key: ValueKey('${widget.label.toLowerCase()}-$index'),
                          style: TextStyle(
                            fontSize: selected ? 32 : 20,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: selected
                                ? TwinceColors.text
                                : TwinceColors.muted,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerSignal: (event) {
                  // Discrete wheel notches commonly arrive as 100 to 120 pixels on
                  // desktop. Small/high-resolution deltas and trackpad gestures
                  // go directly to Flutter's scrollable for continuous movement.
                  if (event is PointerScrollEvent &&
                      event.kind == PointerDeviceKind.mouse &&
                      event.scrollDelta.dy.abs() >= 40) {
                    GestureBinding.instance.pointerSignalResolver.register(
                      event,
                      (_) {
                        _mouseNotch(event.scrollDelta.dy > 0 ? 1 : -1);
                        event.respond(allowPlatformDefault: false);
                      },
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerWheelPhysics extends FixedExtentScrollPhysics {
  const _TimerWheelPhysics({super.parent});

  @override
  _TimerWheelPhysics applyTo(ScrollPhysics? ancestor) =>
      _TimerWheelPhysics(parent: buildParent(ancestor));

  @override
  Tolerance toleranceFor(ScrollMetrics metrics) {
    final base = super.toleranceFor(metrics);
    return Tolerance(distance: 0.001, velocity: base.velocity, time: base.time);
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
            border: Border.all(
              color: TwinceColors.cyan.withValues(alpha: 0.55),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
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
          gradient: const LinearGradient(
            colors: [TwinceColors.blue, TwinceColors.cyan],
          ),
          boxShadow: [
            BoxShadow(
              color: TwinceColors.cyan.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
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
                  Icon(
                    Icons.play_arrow_rounded,
                    color: Color(0xFF041018),
                    size: 26,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Start',
                    style: TextStyle(
                      color: Color(0xFF041018),
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
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
  const _ControlButton({
    required this.label,
    required this.filled,
    required this.onPressed,
  });

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
            border: Border.all(
              color: filled ? TwinceColors.cyan : TwinceColors.stroke,
            ),
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
