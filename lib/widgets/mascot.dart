import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum MascotMood { happy, grin, wink, sleepy, wow }

enum MascotProp { none, key, magnifier, sparkles, zzz, heart, check }

/// "Vo", Vaulty's squishy keyhole blob. Drawn in code so it scales to any
/// size, themes with the palette and costs zero asset bytes.
class Mascot extends StatefulWidget {
  const Mascot({
    super.key,
    this.size = 160,
    this.mood = MascotMood.happy,
    this.prop = MascotProp.none,
    this.wave = false,
    this.animate = true,
  });

  final double size;
  final MascotMood mood;
  final MascotProp prop;
  final bool wave;
  final bool animate;

  @override
  State<Mascot> createState() => _MascotState();
}

class _MascotState extends State<Mascot> with TickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  bool _alive = true;

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      _bob.repeat();
      _scheduleBlink();
    }
  }

  Future<void> _scheduleBlink() async {
    final rnd = math.Random();
    while (_alive) {
      await Future<void>.delayed(Duration(milliseconds: 2200 + rnd.nextInt(2600)));
      if (!_alive || !mounted) return;
      await _blink.forward();
      if (!_alive || !mounted) return;
      await _blink.reverse();
    }
  }

  @override
  void dispose() {
    _alive = false;
    _bob.dispose();
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.vc;
    // Align keeps Vo square even when a parent (e.g. a ListView) forces
    // full-width constraints; otherwise he gets stretched.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: 1,
      heightFactor: 1,
      child: Semantics(
        label: 'Vaulty mascot',
        image: true,
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: Listenable.merge([_bob, _blink]),
            builder: (context, _) => CustomPaint(
              painter: _MascotPainter(
                colors: c,
                bob: widget.animate ? math.sin(_bob.value * 2 * math.pi) : 0,
                blink: _blink.value,
                mood: widget.mood,
                prop: widget.prop,
                wave: widget.wave,
                phase: _bob.value,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MascotPainter extends CustomPainter {
  _MascotPainter({
    required this.colors,
    required this.bob,
    required this.blink,
    required this.mood,
    required this.prop,
    required this.wave,
    required this.phase,
  });

  final VaultyColors colors;
  final double bob;
  final double blink;
  final MascotMood mood;
  final MascotProp prop;
  final bool wave;
  final double phase;

  static const _ink = Color(0xFF2A1B5C);
  static const _gold = Color(0xFFFFC94D);
  static const _goldDeep = Color(0xFFE8A92E);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final lift = bob * h * 0.025;

    // Ground shadow shrinks as Vo floats up.
    final shadowScale = 1 - bob * 0.08;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * .5, h * .95), width: w * .5 * shadowScale, height: h * .06),
      Paint()..color = colors.mascotShade.withValues(alpha: 0.18),
    );

    canvas.save();
    canvas.translate(0, -lift);
    // Gentle squash & stretch.
    canvas.translate(w * .5, h * .9);
    canvas.scale(1 + bob * 0.015, 1 - bob * 0.015);
    canvas.translate(-w * .5, -h * .9);

    _arms(canvas, w, h, behind: true);
    _body(canvas, w, h);
    _face(canvas, w, h);
    _keyhole(canvas, w, h);
    _arms(canvas, w, h, behind: false);
    canvas.restore();

    _prop(canvas, w, h, lift);
  }

  void _body(Canvas canvas, double w, double h) {
    final body = Path()
      ..moveTo(w * .5, h * .14)
      ..cubicTo(w * .80, h * .14, w * .88, h * .40, w * .86, h * .62)
      ..cubicTo(w * .85, h * .78, w * .84, h * .86, w * .78, h * .88)
      ..quadraticBezierTo(w * .72, h * .93, w * .66, h * .875)
      ..quadraticBezierTo(w * .58, h * .935, w * .50, h * .875)
      ..quadraticBezierTo(w * .42, h * .935, w * .34, h * .875)
      ..quadraticBezierTo(w * .28, h * .93, w * .22, h * .88)
      ..cubicTo(w * .16, h * .86, w * .15, h * .78, w * .14, h * .62)
      ..cubicTo(w * .12, h * .40, w * .20, h * .14, w * .5, h * .14)
      ..close();
    final rect = Rect.fromLTWH(0, h * .14, w, h * .8);
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(colors.mascot, Colors.white, .12)!, colors.mascotShade],
        ).createShader(rect),
    );
    // Glossy highlight.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * .33, h * .27), width: w * .16, height: h * .09),
      Paint()..color = Colors.white.withValues(alpha: .28),
    );
    canvas.drawCircle(Offset(w * .42, h * .22), w * .018, Paint()..color = Colors.white.withValues(alpha: .35));
    // Cute freckles like a little plush.
    final freckle = Paint()..color = colors.mascotShade.withValues(alpha: .55);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * .70, h * .28), width: w * .03, height: h * .04), freckle);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * .74, h * .33), width: w * .022, height: h * .03), freckle);
  }

  void _face(Canvas canvas, double w, double h) {
    final ink = Paint()..color = _ink;
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = w * .022;

    void openEye(Offset c) {
      final squash = 1 - blink * .9;
      canvas.drawOval(Rect.fromCenter(center: c, width: w * .105, height: h * .125 * squash), ink);
      if (squash > .4) {
        canvas.drawCircle(c + Offset(-w * .018, -h * .026 * squash), w * .022, Paint()..color = Colors.white);
        canvas.drawCircle(c + Offset(w * .02, h * .02 * squash), w * .01, Paint()..color = Colors.white);
      }
    }

    void closedEye(Offset c, {bool happy = true}) {
      final r = Rect.fromCenter(center: c, width: w * .1, height: h * .08);
      canvas.drawArc(r, happy ? math.pi : 0, math.pi, false, stroke);
    }

    final left = Offset(w * .385, h * .46);
    final right = Offset(w * .615, h * .46);
    switch (mood) {
      case MascotMood.sleepy:
        closedEye(left, happy: false);
        closedEye(right, happy: false);
      case MascotMood.wink:
        openEye(left);
        closedEye(right);
      case MascotMood.grin:
        closedEye(left);
        closedEye(right);
      case MascotMood.happy || MascotMood.wow:
        openEye(left);
        openEye(right);
    }

    // Blush.
    final blush = Paint()..color = const Color(0xFFFF8FB8).withValues(alpha: .55);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * .29, h * .56), width: w * .1, height: h * .05), blush);
    canvas.drawOval(Rect.fromCenter(center: Offset(w * .71, h * .56), width: w * .1, height: h * .05), blush);

    // Mouth.
    final mouthC = Offset(w * .5, h * .565);
    switch (mood) {
      case MascotMood.wow:
        canvas.drawOval(Rect.fromCenter(center: mouthC + Offset(0, h * .01), width: w * .06, height: h * .07), ink);
      case MascotMood.sleepy:
        canvas.drawArc(
          Rect.fromCenter(center: mouthC, width: w * .06, height: h * .035),
          0,
          math.pi,
          false,
          stroke..strokeWidth = w * .016,
        );
      case MascotMood.grin || MascotMood.happy || MascotMood.wink:
        final mouth = Path()
          ..moveTo(mouthC.dx - w * .055, mouthC.dy - h * .012)
          ..quadraticBezierTo(mouthC.dx, mouthC.dy + h * .075, mouthC.dx + w * .055, mouthC.dy - h * .012)
          ..close();
        canvas.drawPath(mouth, ink);
        canvas.drawOval(
          Rect.fromCenter(center: mouthC + Offset(0, h * .026), width: w * .045, height: h * .025),
          Paint()..color = const Color(0xFFFF7A9C),
        );
    }
  }

  void _keyhole(Canvas canvas, double w, double h) {
    final c = Offset(w * .5, h * .72);
    canvas.drawCircle(c, w * .075, Paint()..color = _gold);
    canvas.drawCircle(
      c,
      w * .075,
      Paint()
        ..color = _goldDeep
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * .012,
    );
    final hole = Paint()..color = _ink.withValues(alpha: .85);
    canvas.drawCircle(c + Offset(0, -h * .012), w * .02, hole);
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - w * .013, c.dy - h * .008)
        ..lineTo(c.dx + w * .013, c.dy - h * .008)
        ..lineTo(c.dx + w * .02, c.dy + h * .035)
        ..lineTo(c.dx - w * .02, c.dy + h * .035)
        ..close(),
      hole,
    );
  }

  void _arms(Canvas canvas, double w, double h, {required bool behind}) {
    final paint = Paint()..color = colors.mascotShade;
    void arm(Offset center, double angle) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: w * .1, height: h * .17), paint);
      canvas.restore();
    }

    if (behind) {
      arm(Offset(w * .14, h * .66), .6);
      if (!wave) arm(Offset(w * .86, h * .66), -.6);
    } else if (wave) {
      final swing = math.sin(phase * 4 * math.pi) * .25;
      arm(Offset(w * .9, h * .44), -2.5 + swing);
    }
  }

  void _prop(Canvas canvas, double w, double h, double lift) {
    switch (prop) {
      case MascotProp.none:
        return;
      case MascotProp.sparkles:
        final t = phase * 2 * math.pi;
        _sparkle(canvas, Offset(w * .12, h * .2), w * (.05 + .015 * math.sin(t)), _gold);
        _sparkle(canvas, Offset(w * .9, h * .16), w * (.04 + .015 * math.cos(t)), colors.rose);
        _sparkle(canvas, Offset(w * .94, h * .52), w * (.03 + .01 * math.sin(t + 1)), colors.teal);
      case MascotProp.zzz:
        final tp = TextPainter(
          text: TextSpan(
            text: 'z Z',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w800,
              fontSize: w * .12,
              color: colors.brand.withValues(alpha: .7),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(w * .74, h * .06 - lift * 2 - phase * h * .03));
      case MascotProp.heart:
        _heart(canvas, Offset(w * .82, h * .14 - lift * 1.5), w * .12, colors.rose);
      case MascotProp.check:
        final c = Offset(w * .84, h * .2 - lift);
        canvas.drawCircle(c, w * .09, Paint()..color = colors.ok);
        canvas.drawPath(
          Path()
            ..moveTo(c.dx - w * .04, c.dy)
            ..lineTo(c.dx - w * .01, c.dy + h * .03)
            ..lineTo(c.dx + w * .045, c.dy - h * .03),
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = w * .022,
        );
      case MascotProp.magnifier:
        final c = Offset(w * .86, h * .38 - lift);
        canvas.drawLine(
          c + Offset(w * .05, h * .05),
          c + Offset(w * .12, h * .13),
          Paint()
            ..color = _ink
            ..strokeWidth = w * .035
            ..strokeCap = StrokeCap.round,
        );
        canvas.drawCircle(c, w * .08, Paint()..color = colors.sunken.withValues(alpha: .85));
        canvas.drawCircle(
          c,
          w * .08,
          Paint()
            ..color = _ink
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * .025,
        );
        canvas.drawCircle(c + Offset(-w * .025, -h * .025), w * .018, Paint()..color = Colors.white);
      case MascotProp.key:
        canvas.save();
        canvas.translate(w * .86, h * .5 - lift);
        canvas.rotate(-.7 + math.sin(phase * 2 * math.pi) * .12);
        final gold = Paint()..color = _gold;
        final edge = Paint()
          ..color = _goldDeep
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .012;
        canvas.drawCircle(Offset(0, -h * .1), w * .055, gold);
        canvas.drawCircle(Offset(0, -h * .1), w * .055, edge);
        canvas.drawCircle(Offset(0, -h * .1), w * .02, Paint()..color = colors.bg);
        final shaft = RRect.fromRectAndRadius(
          Rect.fromLTWH(-w * .015, -h * .05, w * .03, h * .16),
          Radius.circular(w * .01),
        );
        canvas.drawRRect(shaft, gold);
        canvas.drawRect(Rect.fromLTWH(w * .015, h * .06, w * .035, h * .022), gold);
        canvas.drawRect(Rect.fromLTWH(w * .015, h * .095, w * .025, h * .02), gold);
        canvas.restore();
    }
  }

  void _sparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  void _heart(Canvas canvas, Offset c, double s, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy + s * .35)
      ..cubicTo(c.dx - s * .9, c.dy - s * .2, c.dx - s * .35, c.dy - s * .75, c.dx, c.dy - s * .3)
      ..cubicTo(c.dx + s * .35, c.dy - s * .75, c.dx + s * .9, c.dy - s * .2, c.dx, c.dy + s * .35)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MascotPainter old) =>
      old.bob != bob ||
      old.blink != blink ||
      old.mood != mood ||
      old.prop != prop ||
      old.wave != wave ||
      old.phase != phase ||
      old.colors != colors;
}
