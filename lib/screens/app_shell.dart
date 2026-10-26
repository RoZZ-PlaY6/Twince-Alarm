import 'package:flutter/material.dart';
import 'package:twince_alarm/screens/home_screen.dart';
import 'package:twince_alarm/screens/plan_screen.dart';
import 'package:twince_alarm/screens/timer_screen.dart';
import 'package:twince_alarm/theme/twince_theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, this.connectPlatform = true});

  final bool connectPlatform;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TwinceColors.bg0,
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(connectPlatform: widget.connectPlatform),
          const TimerScreen(),
          const PlanScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: TwinceColors.bg3,
          indicatorColor: TwinceColors.cyan.withValues(alpha: 0.28),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              color: selected ? TwinceColors.cyan : TwinceColors.muted,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? TwinceColors.cyan : TwinceColors.muted,
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.alarm_outlined),
              selectedIcon: Icon(Icons.alarm),
              label: 'Alarm',
            ),
            NavigationDestination(
              icon: Icon(Icons.timer_outlined),
              selectedIcon: Icon(Icons.timer),
              label: 'Timer',
            ),
            NavigationDestination(
              icon: Icon(Icons.event_note_outlined),
              selectedIcon: Icon(Icons.event_note),
              label: 'Plan',
            ),
          ],
          onDestinationSelected: (index) => setState(() => _index = index),
        ),
      ),
    );
  }
}
