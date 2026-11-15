import 'package:flutter/material.dart';
import 'package:twince_alarm/screens/home_screen.dart';
import 'package:twince_alarm/screens/plan_screen.dart';
import 'package:twince_alarm/screens/settings_screen.dart';
import 'package:twince_alarm/screens/timer_screen.dart';
import 'package:twince_alarm/services/plan_repository.dart';
import 'package:twince_alarm/theme/twince_theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.connectPlatform = true, this.plans});

  final bool connectPlatform;
  final PlanRepository? plans;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _alarmTab = 1;
  int _index = _alarmTab;
  int _restoreGeneration = 0;
  late final PlanRepository _plans = widget.plans ?? PlanRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TwinceColors.bg0,
      body: IndexedStack(
        index: _index,
        children: [
          const SettingsScreen(),
          HomeScreen(
            key: ValueKey('home-$_restoreGeneration'),
            connectPlatform: widget.connectPlatform,
            onRestored: () async {
              await _plans.load();
              if (mounted) setState(() => _restoreGeneration++);
            },
          ),
          const TimerScreen(),
          PlanScreen(
            key: ValueKey('plan-$_restoreGeneration'),
            repository: _plans,
            active: _index == 3,
          ),
        ],
      ),
      bottomNavigationBar: _ShellNav(
        index: _index,
        onSelected: (index) => setState(() => _index = index),
      ),
    );
  }
}

class _ShellDestination {
  const _ShellDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class _ShellNav extends StatelessWidget {
  const _ShellNav({required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  static const _destinations = [
    _ShellDestination(label: 'Settings', icon: Icons.settings_outlined),
    _ShellDestination(label: 'Alarm', icon: Icons.alarm_outlined),
    _ShellDestination(label: 'Timer', icon: Icons.timer_outlined),
    _ShellDestination(label: 'Plan', icon: Icons.event_note_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TwinceColors.bg0,
      child: SafeArea(
        top: false,
        child: SizedBox(
          key: const Key('shell-nav'),
          height: 64,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const pillWidth = 50.0;
              final itemWidth = constraints.maxWidth / _destinations.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    key: const Key('shell-nav-pill'),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOutCubic,
                    left: itemWidth * index + (itemWidth - pillWidth) / 2,
                    top: 6,
                    width: pillWidth,
                    height: 34,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFF145868),
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < _destinations.length; i++)
                        Expanded(
                          child: _NavButton(
                            destination: _destinations[i],
                            selected: index == i,
                            onTap: () => onSelected(i),
                          ),
                        ),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Row(
                        children: [
                          for (var i = 0; i < _destinations.length; i++)
                            Expanded(
                              child: Center(
                                child: Container(
                                  key: ValueKey(
                                    'nav-dot-${_destinations[i].label}',
                                  ),
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: index == i
                                        ? TwinceColors.cyan
                                        : TwinceColors.muted.withValues(
                                            alpha: 0.4,
                                          ),
                                    boxShadow: index == i
                                        ? [
                                            BoxShadow(
                                              color: TwinceColors.cyan
                                                  .withValues(alpha: 0.7),
                                              blurRadius: 5,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _ShellDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? TwinceColors.cyan : TwinceColors.muted;
    return Semantics(
      selected: selected,
      child: InkWell(
        onTap: onTap,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(begin: color, end: color),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          builder: (context, animatedColor, child) => Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Icon(destination.icon, size: 22, color: animatedColor),
              ),
              const SizedBox(height: 4),
              Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: animatedColor,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
