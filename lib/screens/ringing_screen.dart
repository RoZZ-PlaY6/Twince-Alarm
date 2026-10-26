import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twince_alarm/models/alarm_item.dart';
import 'package:twince_alarm/services/alarm_bridge.dart';
import 'package:twince_alarm/theme/twince_theme.dart';
import 'package:twince_alarm/widgets/neon_bell.dart';

class RingingScreen extends StatefulWidget {
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
    this.durationLabel,
    this.statusLabel = 'Alarm',
    this.playSoundOnOpen = false,
  });

  final int hour;
  final int minute;
  final String title;
  final String subtitle;
  final int alarmId;
  final bool vibrate;
  final String soundUri;
  final bool preview;
  final String? durationLabel;
  final String statusLabel;
  final bool playSoundOnOpen;

  @override
  State<RingingScreen> createState() => _RingingScreenState();
}

class _RingingScreenState extends State<RingingScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.playSoundOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playSelectedSound();
      });
    }
  }

  @override
  void dispose() {
    if (widget.playSoundOnOpen) {
      AlarmBridge.instance.stopPreview();
    }
    super.dispose();
  }

  Future<void> _playSelectedSound() async {
    try {
      await AlarmBridge.instance.previewSound(widget.soundUri, loop: true);
    } on PlatformException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Could not play the timer sound')),
      );
    }
  }

  Future<void> _finish(BuildContext context, String message) async {
    if (widget.playSoundOnOpen) {
      try {
        await AlarmBridge.instance.stopPreview();
      } on PlatformException {
        // Closing still dismisses the screen when playback is already gone.
      }
    }
    if (!context.mounted) return;
    Navigator.of(context).pop(message);
  }

  Future<void> _testLockScreen(BuildContext context) async {
    try {
      await AlarmBridge.instance.previewRing(
        id: widget.alarmId,
        hour: widget.hour,
        minute: widget.minute,
        label: widget.title,
        subtitle: widget.subtitle,
        vibrate: widget.vibrate,
        soundUri: widget.soundUri,
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
    final durationLabel = widget.durationLabel;
    final period = durationLabel == null ? ringPeriod(widget.hour, use24: use24) : null;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TwinceBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final metrics = _RingingMetrics.fit(
                maxHeight: constraints.maxHeight,
                // Two extra pixels cover font rounding so the column cannot
                // paint a pixel past the safe area.
                fixedHeight: _fixedHeight(context, constraints.maxWidth, use24, period) + 2,
              );
              final body = _content(context, metrics, use24, period);
              final padding = EdgeInsets.fromLTRB(24, metrics.topPad, 24, metrics.bottomPad);
              if (metrics.scroll) {
                return SingleChildScrollView(padding: padding, child: body);
              }
              return Padding(padding: padding, child: body);
            },
          ),
        ),
      ),
    );
  }

  double _fixedHeight(BuildContext context, double maxWidth, bool use24, String? period) {
    final textWidth = math.max(0.0, maxWidth - 48);
    final timeStyle = const TextStyle(
      fontSize: 76,
      fontWeight: FontWeight.w300,
      height: 1,
      letterSpacing: -1,
      fontFeatures: [FontFeature.tabularFigures()],
    );
    final timeHeight = _textHeight(
      context,
      widget.durationLabel ?? formatRingTime(widget.hour, widget.minute, use24: use24),
      timeStyle,
      textWidth,
    );
    final periodHeight = period == null
        ? 0.0
        : _textHeight(context, period, const TextStyle(color: TwinceColors.muted, fontSize: 18), textWidth);
    // TextButton keeps a 48px padded tap target, plus the 8px gap above it.
    final testButton = widget.preview ? 8.0 + 48.0 : 0.0;
    return _textHeight(
          context,
          'TWINCE',
          const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 8),
          textWidth,
        ) +
        math.max(timeHeight, periodHeight) +
        4 +
        _textHeight(
          context,
          widget.statusLabel,
          const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 2),
          textWidth,
        ) +
        _textHeight(
          context,
          widget.title,
          const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          textWidth,
          maxLines: 2,
        ) +
        6 +
        _textHeight(context, widget.subtitle, const TextStyle(color: TwinceColors.muted, fontSize: 15), textWidth) +
        112 +
        52 +
        testButton;
  }

  Widget _content(BuildContext context, _RingingMetrics metrics, bool use24, String? period) {
    final durationLabel = widget.durationLabel;
    return Column(
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
        SizedBox(height: metrics.topGap),
        if (durationLabel != null)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              durationLabel,
              style: const TextStyle(
                fontSize: 76,
                fontWeight: FontWeight.w300,
                height: 1,
                letterSpacing: -1,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                formatRingTime(widget.hour, widget.minute, use24: use24),
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
        Text(
          widget.statusLabel,
          style: const TextStyle(
            color: TwinceColors.muted,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            letterSpacing: 2,
          ),
        ),
        if (metrics.bell > 0) NeonBell(size: metrics.bell),
        Text(
          widget.title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          widget.subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: TwinceColors.muted, fontSize: 15),
        ),
        SizedBox(height: metrics.spacer),
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
        SizedBox(height: metrics.actionGap),
        Row(
          children: [
            SnoozePill(label: 'Snooze 5min', onPressed: () => _finish(context, 'Snoozed 5 min')),
            const SizedBox(width: 12),
            SnoozePill(label: 'Snooze 10min', onPressed: () => _finish(context, 'Snoozed 10 min')),
          ],
        ),
        if (widget.preview) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _testLockScreen(context),
            child: const Text('Test on lock screen'),
          ),
        ],
      ],
    );
  }
}

double _textHeight(BuildContext context, String text, TextStyle style, double maxWidth, {int? maxLines}) {
  final effective = DefaultTextStyle.of(context).style.merge(style);
  final painter = TextPainter(
    text: TextSpan(text: text, style: effective),
    textAlign: TextAlign.center,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: maxLines,
    ellipsis: maxLines == null ? null : '\u2026',
  )..layout(maxWidth: math.max(1, maxWidth));
  final height = painter.height.ceilToDouble();
  painter.dispose();
  return height;
}

/// Full-size spacing on a tall screen. On a short screen the extra gaps shrink
/// first, then the bell, so the snooze actions stay on screen.
class _RingingMetrics {
  const _RingingMetrics({
    required this.topPad,
    required this.bottomPad,
    required this.topGap,
    required this.actionGap,
    required this.bell,
    required this.spacer,
    required this.scroll,
  });

  final double topPad;
  final double bottomPad;
  final double topGap;
  final double actionGap;
  final double bell;
  final double spacer;
  final bool scroll;

  static const _topPadMax = 28.0;
  static const _bottomPadMax = 20.0;
  static const _topGapMax = 36.0;
  static const _actionGapMax = 32.0;
  static const _bellMax = 200.0;
  static const _topPadMin = 12.0;
  static const _bottomPadMin = 8.0;
  static const _gapMin = 8.0;
  static const _bellMin = 72.0;

  static _RingingMetrics fit({required double maxHeight, required double fixedHeight}) {
    var topPad = _topPadMax;
    var bottomPad = _bottomPadMax;
    var topGap = _topGapMax;
    var actionGap = _actionGapMax;
    var bell = _bellMax;
    var overflow = fixedHeight + topPad + bottomPad + topGap + actionGap + bell - maxHeight;

    double reduce(double value, double min) {
      if (overflow <= 0 || value <= min) return value;
      final next = math.max(min, value - overflow);
      overflow -= value - next;
      return next;
    }

    actionGap = reduce(actionGap, _gapMin);
    topGap = reduce(topGap, _gapMin);
    topPad = reduce(topPad, _topPadMin);
    bottomPad = reduce(bottomPad, _bottomPadMin);
    bell = reduce(bell, _bellMin);
    final used = fixedHeight + topPad + bottomPad + topGap + actionGap + bell;
    return _RingingMetrics(
      topPad: topPad,
      bottomPad: bottomPad,
      topGap: topGap,
      actionGap: actionGap,
      bell: bell,
      spacer: overflow > 0 ? 0 : math.max(0, maxHeight - used),
      scroll: overflow > 0,
    );
  }
}
