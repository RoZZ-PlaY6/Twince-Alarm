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
  late final PlanRepository _plans = widget.plans ?? PlanRepository();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TwinceColors.bg0,
      body: IndexedStack(
        index: _index,
        children: [
          SettingsScreen(),
          HomeScreen(connectPlatform: widget.connectPlatform),
          const TimerScreen(),
          PlanScreen(repository: _plans, active: _index == 3),
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
          child: Row(
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

  static const _pill = Color(0xFF145868);

  @override
  Widget build(BuildContext context) {
    final color = selected ? TwinceColors.cyan : TwinceColors.muted;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? _pill : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Icon(destination.icon, size: 22, color: color),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            destination.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
