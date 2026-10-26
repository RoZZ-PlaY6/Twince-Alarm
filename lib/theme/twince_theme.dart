import 'package:flutter/material.dart';

class TwinceColors {
  const TwinceColors._();

  static const bg0 = Color(0xFF070B18);
  static const bg1 = Color(0xFF141238);
  static const bg2 = Color(0xFF1A1033);
  static const bg3 = Color(0xFF05060C);
  static const cyan = Color(0xFF3DDCFF);
  static const blue = Color(0xFF3D8BFF);
  static const purple = Color(0xFFC084FC);
  static const text = Color(0xFFF4F7FF);
  static const muted = Color(0xFF9AA4C7);
  static const card = Color(0xFF101426);
  static const stroke = Color(0xFF24304F);
}

class TwinceTheme {
  const TwinceTheme._();

  static ThemeData dark() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: TwinceColors.bg0,
      canvasColor: TwinceColors.bg0,
      colorScheme: const ColorScheme.dark(
        surface: TwinceColors.bg0,
        primary: TwinceColors.cyan,
        secondary: TwinceColors.purple,
        onSurface: TwinceColors.text,
      ),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: TwinceColors.text,
        displayColor: TwinceColors.text,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFF1A2238),
        contentTextStyle: TextStyle(color: TwinceColors.text),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Color(0xFF14182A),
      ),
    );
  }
}

class TwinceBackground extends StatelessWidget {
  const TwinceBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            TwinceColors.bg0,
            TwinceColors.bg1,
            TwinceColors.bg2,
            TwinceColors.bg3,
          ],
          stops: [0, 0.38, 0.7, 1],
        ),
      ),
      child: child,
    );
  }
}
