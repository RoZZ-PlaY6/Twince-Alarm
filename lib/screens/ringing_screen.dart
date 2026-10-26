import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twince_alarm/models/alarm_item.dart';
import 'package:twince_alarm/services/alarm_bridge.dart';
import 'package:twince_alarm/theme/twince_theme.dart';
import 'package:twince_alarm/widgets/neon_bell.dart';

class RingingScreen extends StatelessWidget {
  const RingingScreen({
    super.key,
    required this.hour,
    required this.minute,
    required this.title,
    required this.subtitle,
    this.alarmId = 0,
    this.vibrate = true,
    this.soundUri = '',
    this.preview = false,
  });

  final int hour;
  final int minute;
  final String title;
  final String subtitle;
  final int alarmId;
  final bool vibrate;
  final String soundUri;
  final bool preview;

  Future<void> _finish(BuildContext context, String message) async {
    Navigator.of(context).pop(message);
  }

  Future<void> _testLockScreen(BuildContext context) async {
    try {
      await AlarmBridge.instance.previewRing(
        id: alarmId,
        hour: hour,
        minute: minute,
        label: title,
        subtitle: subtitle,
        vibrate: vibrate,
        soundUri: soundUri,
      );
    } on PlatformException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Could not open the lock-screen alarm')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final use24 = MediaQuery.alwaysUse24HourFormatOf(context);
    final period = ringPeriod(hour, use24: use24);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TwinceBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              children: [
                const Text(
                  'TWINCE',
                  style: TextStyle(
                    color: Color(0xFFD7F7FF),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 8,
                    shadows: [
                      Shadow(color: TwinceColors.cyan, blurRadius: 16),
                      Shadow(color: Color(0x663DDCFF), blurRadius: 32),
                    ],
                  ),
                ),
                const SizedBox(height: 36),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      formatRingTime(hour, minute, use24: use24),
                      style: const TextStyle(
                        fontSize: 76,
                        fontWeight: FontWeight.w300,
                        height: 1,
                        letterSpacing: -1,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (period != null) ...[
                      const SizedBox(width: 8),
                      Text(period, style: const TextStyle(color: TwinceColors.muted, fontSize: 18)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Alarm',
                  style: TextStyle(
                    color: TwinceColors.muted,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 2,
                  ),
                ),
                const NeonBell(size: 200),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: TwinceColors.muted, fontSize: 15),
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GlowActionButton(
                      color: TwinceColors.blue,
                      icon: Icons.close,
                      tooltip: 'Dismiss',
                      onPressed: () => _finish(context, 'Alarm dismissed'),
                    ),
                    const SizedBox(width: 36),
                    GlowActionButton(
                      color: TwinceColors.purple,
                      icon: Icons.replay,
                      tooltip: 'Restart',
                      onPressed: () => _finish(context, 'Alarm restarted'),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    SnoozePill(label: 'Snooze 5min', onPressed: () => _finish(context, 'Snoozed 5 min')),
                    const SizedBox(width: 12),
                    SnoozePill(label: 'Snooze 10min', onPressed: () => _finish(context, 'Snoozed 10 min')),
                  ],
                ),
                if (preview) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => _testLockScreen(context),
                    child: const Text('Test on lock screen'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
