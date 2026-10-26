import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twince_alarm/models/alarm_item.dart';
import 'package:twince_alarm/screens/edit_alarm_screen.dart';
import 'package:twince_alarm/screens/ringing_screen.dart';
import 'package:twince_alarm/services/alarm_bridge.dart';
import 'package:twince_alarm/theme/twince_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.connectPlatform = true});

  final bool connectPlatform;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _bridge = AlarmBridge.instance;
  Timer? _clock;
  StreamSubscription<AlarmEvent>? _events;
  DateTime _now = DateTime.now();
  List<AlarmItem> _alarms = const [];
  AlarmPermissions _permissions = AlarmPermissions.granted;
  bool _loading = true;
  bool _bootstrapped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
    if (!widget.connectPlatform) {
      _loading = false;
      return;
    }
    _events = _bridge.events.listen((event) {
      if (!mounted) return;
      _toast(event.message);
      _reload();
    }, onError: (_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _events?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.connectPlatform && _bootstrapped) {
      _reload();
      _drainEvents();
      _consumeClockIntent();
    }
  }

  Future<void> _bootstrap() async {
    await _reload();
    await _drainEvents();
    await _consumeClockIntent();
    if (!mounted) return;
    _bootstrapped = true;
    if (!_permissions.notifications) {
      try {
        await _bridge.requestNotifications();
      } on PlatformException {
        // The user can enable notifications from the banner.
      }
      await _reload();
    }
  }

  Future<void> _reload() async {
    try {
      final alarms = await _bridge.getAlarms();
      final permissions = await _bridge.permissions();
      if (!mounted) return;
      alarms.sort((a, b) {
        final byTime = (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
      setState(() {
        _alarms = alarms;
        _permissions = permissions;
        _loading = false;
        _now = DateTime.now();
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _toast(error.message ?? 'Could not load alarms');
    }
  }

  Future<void> _drainEvents() async {
    try {
      final events = await _bridge.consumeEvents();
      if (!mounted || events.isEmpty) return;
      _toast(events.last.message);
    } on PlatformException {
      // The live stream covers events while the UI is open.
    }
  }

  Future<void> _consumeClockIntent() async {
    try {
      final launch = await _bridge.consumeClockIntent();
      if (!mounted || launch == null || !launch.isSetAlarm) return;
      final hour = launch.hour >= 0 ? launch.hour : _now.hour;
      final minute = launch.minute >= 0 ? launch.minute : _now.minute;
      final draft = AlarmItem(
        id: 0,
        hour: hour,
        minute: minute,
        label: launch.label.isEmpty ? 'Alarm' : launch.label,
        subtitle: 'Time to start your task',
        enabled: true,
        vibrate: launch.vibrate,
        soundUri: launch.soundUri,
        repeatDays: launch.repeatDays,
      );
      if (launch.skipUi) {
        final saved = await _bridge.upsert(draft);
        if (!mounted) return;
        _toast(saved.scheduleError.isEmpty ? 'Alarm saved' : 'Allow exact alarms to schedule it');
        await _reload();
        return;
      }
      await _openEditor(draft);
    } on PlatformException catch (error) {
      if (!mounted) return;
      _toast(error.message ?? 'Could not open the alarm');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openEditor([AlarmItem? alarm]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EditAlarmScreen(alarm: alarm)),
    );
    if (changed == true) await _reload();
  }

  Future<void> _toggle(AlarmItem alarm, bool enabled) async {
    try {
      final saved = await _bridge.setEnabled(alarm.id, enabled);
      if (saved.scheduleError.isNotEmpty) {
        _toast('Allow exact alarms so this alarm can fire on time');
      }
      await _reload();
    } on PlatformException catch (error) {
      _toast(error.message ?? 'Could not update the alarm');
    }
  }

  Future<void> _openPreview() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const RingingScreen(
          hour: 7,
          minute: 30,
          title: 'Morning workout',
          subtitle: 'Time to start your task',
          preview: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final next = _soonest();
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TwinceBackground(
        child: SafeArea(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 108),
                children: [
                  Row(
                    children: [
                      const Text(
                        'TWINCE',
                        style: TextStyle(
                          color: Color(0xFFD7F7FF),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 6,
                          shadows: [Shadow(color: TwinceColors.cyan, blurRadius: 16)],
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Preview alarm screen',
                        onPressed: _openPreview,
                        icon: const Icon(Icons.notifications_active_outlined, color: TwinceColors.cyan),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatClock(_now.hour, _now.minute, use24: use24),
                    style: const TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w300,
                      height: 1,
                      letterSpacing: -1,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(formatDate(_now), style: const TextStyle(color: TwinceColors.muted, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text(_nextLine(next, use24), style: const TextStyle(color: TwinceColors.cyan, fontSize: 14)),
                  const SizedBox(height: 18),
                  if (!_permissions.exactAlarm)
                    _Banner(
                      title: 'Exact alarms are off',
                      body: 'Twince needs exact alarms so they still fire in Doze and on the lock screen.',
                      action: 'Allow',
                      onPressed: () => _bridge.openExactAlarmSettings(),
                    ),
                  if (!_permissions.notifications)
                    _Banner(
                      title: 'Notifications are off',
                      body: 'The full-screen alarm uses a high-priority notification to appear over the lock screen.',
                      action: 'Enable',
                      onPressed: () async {
                        final granted = await _bridge.requestNotifications();
                        if (!granted) _toast('Enable notifications for Twince Alarm in system settings');
                        await _reload();
                      },
                    ),
                  if (!_permissions.fullScreenIntent)
                    _Banner(
                      title: 'Full-screen alerts are off',
                      body: 'Allow full-screen notifications so the alarm can cover the lock screen.',
                      action: 'Allow',
                      onPressed: () => _bridge.openFullScreenIntentSettings(),
                    ),
                  Row(
                    children: [
                      const Text('Alarms', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Text('${_alarms.length}', style: const TextStyle(color: TwinceColors.muted)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 48),
                      child: Center(child: CircularProgressIndicator(color: TwinceColors.cyan)),
                    )
                  else if (_alarms.isEmpty)
                    const _EmptyAlarms()
                  else
                    ..._alarms.map((alarm) => _AlarmCard(
                          alarm: alarm,
                          use24: use24,
                          now: _now,
                          onTap: () => _openEditor(alarm),
                          onToggle: (value) => _toggle(alarm, value),
                        )),
                ],
              ),
              Positioned(
                right: 20,
                bottom: 20,
                child: _AddButton(onPressed: () => _openEditor()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  ({AlarmItem alarm, DateTime when})? _soonest() {
    ({AlarmItem alarm, DateTime when})? best;
    for (final alarm in _alarms) {
      final when = nextTrigger(alarm, _now);
      if (when == null) continue;
      if (best == null || when.isBefore(best.when)) best = (alarm: alarm, when: when);
    }
    return best;
  }

  String _nextLine(({AlarmItem alarm, DateTime when})? next, bool use24) {
    if (next == null) return 'No upcoming alarms';
    final time = formatClock(next.alarm.hour, next.alarm.minute, use24: use24);
    return 'Next · ${whenLabel(next.when, _now)} $time · ${next.alarm.label}';
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.title,
    required this.body,
    required this.action,
    required this.onPressed,
  });

  final String title;
  final String body;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: TwinceColors.card.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TwinceColors.cyan.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: TwinceColors.cyan),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(color: TwinceColors.muted, fontSize: 13)),
              ],
            ),
          ),
          TextButton(onPressed: onPressed, child: Text(action)),
        ],
      ),
    );
  }
}

class _EmptyAlarms extends StatelessWidget {
  const _EmptyAlarms();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 36),
      child: Column(
        children: [
          Icon(Icons.alarm_outlined, color: TwinceColors.cyan, size: 42),
          SizedBox(height: 12),
          Text('No alarms yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text(
            'Add an alarm that can reach you on the lock screen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: TwinceColors.muted),
          ),
        ],
      ),
    );
  }
}

class _AlarmCard extends StatelessWidget {
  const _AlarmCard({
    required this.alarm,
    required this.use24,
    required this.now,
    required this.onTap,
    required this.onToggle,
  });

  final AlarmItem alarm;
  final bool use24;
  final DateTime now;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final when = nextTrigger(alarm, now);
    final snoozed = alarm.snoozeUntil > now.millisecondsSinceEpoch;
    final meta = snoozed
        ? 'Snoozed'
        : when == null
            ? repeatLabel(alarm.repeatDays)
            : '${whenLabel(when, now)} · ${repeatLabel(alarm.repeatDays)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: TwinceColors.card.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: alarm.enabled ? TwinceColors.cyan.withValues(alpha: 0.35) : TwinceColors.stroke,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatClock(alarm.hour, alarm.minute, use24: use24),
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w300,
                          color: alarm.enabled ? TwinceColors.text : TwinceColors.muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(alarm.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(meta, style: const TextStyle(color: TwinceColors.muted, fontSize: 13)),
                    ],
                  ),
                ),
                Switch(
                  value: alarm.enabled,
                  onChanged: onToggle,
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return TwinceColors.bg0;
                    return TwinceColors.muted;
                  }),
                  trackColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return TwinceColors.cyan;
                    return const Color(0xFF2A3148);
                  }),
                  trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(colors: [TwinceColors.blue, TwinceColors.cyan]),
        boxShadow: [
          BoxShadow(color: TwinceColors.cyan.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: 64,
            height: 64,
            child: Icon(Icons.add, color: Color(0xFF041018), size: 32),
          ),
        ),
      ),
    );
  }
}
