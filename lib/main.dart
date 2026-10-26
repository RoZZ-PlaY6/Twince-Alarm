import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twince_alarm/screens/app_shell.dart';
import 'package:twince_alarm/theme/twince_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: TwinceColors.bg3,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const TwinceAlarmApp());
}

class TwinceAlarmApp extends StatelessWidget {
  const TwinceAlarmApp({super.key, this.connectPlatform = true});

  final bool connectPlatform;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Twince Alarm',
      debugShowCheckedModeBanner: false,
      theme: TwinceTheme.dark(),
      home: AppShell(connectPlatform: connectPlatform),
    );
  }
}
