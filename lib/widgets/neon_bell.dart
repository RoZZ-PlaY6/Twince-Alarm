import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:twince_alarm/theme/twince_theme.dart';

class NeonBell extends StatefulWidget {
  const NeonBell({super.key, this.size = 200});

  final double size;

  @override
  State<NeonBell> createState() => _NeonBellState();
}

class _NeonBellState extends State<NeonBell> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _BellPainter(_controller.value),
          );
        },
      ),
    );
  }
}

class _BellPainter extends CustomPainter {
  _BellPainter(this.phase);

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 6;
    final halo = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x663DDCFF), Color(0x22315CFF), Color(0x00000000)],
        stops: [0.05, 0.42, 1],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: 108));
    canvas.drawCircle(Offset(cx, cy), 108, halo);

    for (final side in const [-1.0, 1.0]) {
      for (var index = 0; index < 3; index++) {
        final progress = (phase + index * 0.28) % 1;
        final spread = 14 + progress * 38;
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..color = Color.fromARGB(((1 - progress) * 220).round(), 125, 230, 255);
        final anchorX = cx + side * 50;
        final oval = Rect.fromCenter(
          center: Offset(anchorX, cy),
          width: spread * 2,
          height: spread * 1.65,
        );
        final start = side < 0 ? 118 * math.pi / 180 : -58 * math.pi / 180;
        canvas.drawArc(oval, start, 74 * math.pi / 180, false, paint);
      }
    }

    final radius = 32.0;
    final top = cy - 36;
    final bottom = cy + 20;
    final body = Path()
      ..addArc(Rect.fromLTWH(cx - radius, top, radius * 2, radius * 2.15), 206 * math.pi / 180, 128 * math.pi / 180)
      ..lineTo(cx + radius + 10, bottom)
      ..lineTo(cx - radius - 10, bottom)
      ..close();

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF7EEBFF);
    for (var layer = 8; layer >= 1; layer--) {
      glow.strokeWidth = layer * 2.1;
      glow.color = const Color(0xFF7EEBFF).withValues(alpha: (16 + layer) / 255);
      canvas.drawPath(body, glow);
    }
    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Color(0xFFB8F4FF), TwinceColors.blue],
        stops: [0, 0.42, 1],
      ).createShader(Rect.fromLTWH(cx - radius, top, radius * 2, bottom - top + 8));
    canvas.drawPath(body, fill);

    final metal = Paint()..color = const Color(0xFFE8FBFF);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(cx - 3.2, top - 9, cx + 3.2, top + 8), const Radius.circular(3)),
      metal,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(cx - radius - 10, bottom - 3, cx + radius + 10, bottom + 7),
        const Radius.circular(6),
      ),
      metal,
    );
    canvas.drawCircle(Offset(cx, bottom + 16), 5.5, Paint()..color = const Color(0xFF7EEBFF));
  }

  @override
  bool shouldRepaint(covariant _BellPainter oldDelegate) => oldDelegate.phase != phase;
}

class GlowActionButton extends StatelessWidget {
  const GlowActionButton({
    super.key,
    required this.color,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Color color;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 112,
        height: 112,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 28, spreadRadius: 1),
          ],
        ),
        child: Material(
          color: const Color(0xFF101426),
          shape: CircleBorder(side: BorderSide(color: color, width: 2)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 84,
              height: 84,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
      ),
    );
  }
}

class SnoozePill extends StatelessWidget {
  const SnoozePill({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: const Color(0xE6121828),
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: TwinceColors.cyan.withValues(alpha: 0.33)),
            ),
            child: Text(
              label,
              style: const TextStyle(
                color: TwinceColors.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
