import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:twince_alarm/services/app_version.dart';
import 'package:twince_alarm/theme/twince_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.loadVersion = loadAppVersion});

  final Future<String> Function() loadVersion;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = 'Version …';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final version = await widget.loadVersion();
      if (!mounted) return;
      setState(() => _version = 'Version $version');
    } catch (_) {
      if (!mounted) return;
      setState(() => _version = 'Version unavailable');
    }
  }

  @override
  Widget build(BuildContext context) {
    return TwinceBackground(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final padH = (width * 0.05).clamp(16.0, 48.0);
            final padV = (height * 0.04).clamp(16.0, 40.0);
            final innerWidth = math.max(0.0, width - padH * 2);
            final innerHeight = math.max(0.0, height - padV * 2);
            final cardWidth = math.min(innerWidth, 640.0);
            final scale = (math.min(width, height) / 560)
                .clamp(1.0, 1.5)
                .toDouble();
            final contentHeight = 240.0 * scale;
            final targetHeight = (innerHeight * 0.5).clamp(
              contentHeight,
              480.0,
            );
            final cardHeight = innerHeight >= contentHeight
                ? math.min(targetHeight, innerHeight)
                : contentHeight;
            final cardPadH = width < 360
                ? 16.0
                : 24.0 * math.min(scale, 1.25);
            final cardPadV = math.min(
              32.0 * math.min(scale, 1.25),
              cardHeight * 0.14,
            );

            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: innerHeight),
                child: Center(
                  child: SizedBox(
                    key: const Key('settings-card'),
                    width: cardWidth,
                    height: cardHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: TwinceColors.cyan.withValues(alpha: 0.7),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: TwinceColors.cyan.withValues(alpha: 0.14),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: cardPadH,
                          vertical: cardPadV,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.settings_rounded,
                              color: TwinceColors.cyan,
                              size: 46 * scale,
                            ),
                            SizedBox(height: 12 * scale),
                            Text(
                              'Settings',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22 * scale,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                            SizedBox(height: 16 * scale),
                            Text(
                              _version,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14 * scale),
                            ),
                            SizedBox(height: 8 * scale),
                            Text(
                              '© 2026. All rights reserved.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.54),
                                fontSize: 12.5 * scale,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
