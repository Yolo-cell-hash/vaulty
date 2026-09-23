import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Vaulty's own icon set. Every glyph is drawn on a 24-unit grid with a
/// 1.7-unit rounded stroke so the family reads as one hand-made set.
enum G {
  vault,
  radar,
  search,
  profile,
  plus,
  pen,
  scan,
  image,
  sparkle,
  document,
  repeat,
  ruler,
  box,
  person,
  people,
  hash,
  trash,
  archive,
  unarchive,
  copy,
  eye,
  eyeOff,
  upload,
  download,
  close,
  check,
  chevronRight,
  chevronLeft,
  chevronDown,
  arrowRight,
  arrowUpRight,
  more,
  bell,
  calendar,
  clock,
  cake,
  warning,
  lock,
  unlock,
  key,
  shield,
  fingerprint,
  faceId,
  sun,
  moon,
  phone,
  notes,
  flame,
  info,
  filter,
}

class VIcon extends StatelessWidget {
  const VIcon(this.glyph, {super.key, this.size = 22, this.color, this.stroke = 1.7, this.semanticLabel});

  final G glyph;
  final double size;
  final Color? color;
  final double stroke;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final painted = CustomPaint(
      size: Size.square(size),
      painter: _GlyphPainter(glyph, color ?? IconTheme.of(context).color ?? context.vc.ink, stroke),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: painted);
    return Semantics(label: semanticLabel, image: true, child: painted);
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.color, this.stroke);

  final G glyph;
  final Color color;
  final double stroke;

  late Canvas _c;
  late Paint _p;
  late Paint _f;

  void _line(double x1, double y1, double x2, double y2) => _c.drawLine(Offset(x1, y1), Offset(x2, y2), _p);
  void _circle(double x, double y, double r) => _c.drawCircle(Offset(x, y), r, _p);
  void _dot(double x, double y, [double r = 1.25]) => _c.drawCircle(Offset(x, y), r, _f);
  void _rrect(double l, double t, double r, double b, double rad) =>
      _c.drawRRect(RRect.fromLTRBR(l, t, r, b, Radius.circular(rad)), _p);
  void _path(Path p) => _c.drawPath(p, _p);

  /// Arc on a circle with an arrowhead at the end (angles in degrees).
  void _arrowArc(double cx, double cy, double r, double startDeg, double sweepDeg) {
    final start = startDeg * math.pi / 180, sweep = sweepDeg * math.pi / 180;
    _c.drawArc(Rect.fromCircle(center: Offset(cx, cy), radius: r), start, sweep, false, _p);
    final end = start + sweep;
    final tip = Offset(cx + r * math.cos(end), cy + r * math.sin(end));
    final dir = sweep > 0 ? 1.0 : -1.0;
    final tangent = Offset(-math.sin(end), math.cos(end)) * dir;
    final normal = Offset(math.cos(end), math.sin(end));
    const len = 3.2;
    _line(
      tip.dx,
      tip.dy,
      tip.dx - tangent.dx * len + normal.dx * len * .8,
      tip.dy - tangent.dy * len + normal.dy * len * .8,
    );
    _line(
      tip.dx,
      tip.dy,
      tip.dx - tangent.dx * len - normal.dx * len * .8,
      tip.dy - tangent.dy * len - normal.dy * len * .8,
    );
  }

  Path _sparklePath(double cx, double cy, double r) {
    final k = r * .22;
    return Path()
      ..moveTo(cx, cy - r)
      ..cubicTo(cx + k * .4, cy - k, cx + k, cy - k * .4, cx + r, cy)
      ..cubicTo(cx + k, cy + k * .4, cx + k * .4, cy + k, cx, cy + r)
      ..cubicTo(cx - k * .4, cy + k, cx - k, cy + k * .4, cx - r, cy)
      ..cubicTo(cx - k, cy - k * .4, cx - k * .4, cy - k, cx, cy - r)
      ..close();
  }

  void _personAt(double cx, double headY, double headR, double shoulderW, double baseY) {
    _circle(cx, headY, headR);
    final top = headY + headR + 2.4;
    _path(
      Path()
        ..moveTo(cx - shoulderW, baseY)
        ..cubicTo(cx - shoulderW, top + 1, cx - shoulderW * .45, top, cx, top)
        ..cubicTo(cx + shoulderW * .45, top, cx + shoulderW, top + 1, cx + shoulderW, baseY),
    );
  }

  void _tray() => _path(
    Path()
      ..moveTo(4, 14)
      ..lineTo(4, 17.5)
      ..quadraticBezierTo(4, 20, 6.5, 20)
      ..lineTo(17.5, 20)
      ..quadraticBezierTo(20, 20, 20, 17.5)
      ..lineTo(20, 14),
  );

  void _corners(double inset, double len, double rad) {
    final a = inset, b = 24 - inset;
    for (final (x, y, sx, sy) in [(a, a, 1.0, 1.0), (b, a, -1.0, 1.0), (a, b, 1.0, -1.0), (b, b, -1.0, -1.0)]) {
      _path(
        Path()
          ..moveTo(x, y + sy * len)
          ..lineTo(x, y + sy * rad)
          ..quadraticBezierTo(x, y, x + sx * rad, y)
          ..lineTo(x + sx * len, y),
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _c = canvas;
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    _p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _f = Paint()..color = color;

    switch (glyph) {
      case G.vault:
        _rrect(3.5, 3.5, 20.5, 19, 4.5);
        _circle(12, 11.25, 3.4);
        _dot(12, 11.25, 1.05);
        _line(7.5, 19, 7.5, 21);
        _line(16.5, 19, 16.5, 21);
      case G.radar:
        _circle(12, 12, 8.75);
        _c.drawArc(Rect.fromCircle(center: const Offset(12, 12), radius: 4.8), -math.pi * .9, math.pi * 1.2, false, _p);
        _line(12, 12, 17.6, 6.4);
        _dot(12, 12, 1.4);
      case G.search:
        _circle(10.75, 10.75, 6.5);
        _line(15.6, 15.6, 20, 20);
      case G.profile:
        _personAt(12, 8.25, 3.6, 7, 20);
      case G.plus:
        _line(12, 5, 12, 19);
        _line(5, 12, 19, 12);
      case G.pen:
        _path(
          Path()
            ..moveTo(4.5, 19.5)
            ..lineTo(5.3, 15.6)
            ..lineTo(15.6, 5.3)
            ..quadraticBezierTo(16.8, 4.1, 18, 5.3)
            ..lineTo(18.7, 6)
            ..quadraticBezierTo(19.9, 7.2, 18.7, 8.4)
            ..lineTo(8.4, 18.7)
            ..close(),
        );
        _line(13.8, 7.1, 16.9, 10.2);
      case G.scan:
        _corners(3.5, 4.5, 2.5);
        _circle(12, 12, 3.4);
      case G.image:
        _rrect(3, 4.5, 21, 19.5, 3.5);
        _circle(8.75, 9.5, 1.6);
        _path(
          Path()
            ..moveTo(3.5, 16.8)
            ..lineTo(8.3, 12.6)
            ..lineTo(12.2, 16)
            ..lineTo(15.3, 13.4)
            ..lineTo(20.5, 17.4),
        );
      case G.sparkle:
        _path(_sparklePath(11, 12.5, 7.5));
        _path(_sparklePath(18.5, 5.5, 2.5));
      case G.document:
        _rrect(2.75, 5, 21.25, 19, 3.5);
        _circle(8.5, 10.6, 1.9);
        _path(
          Path()
            ..moveTo(5.6, 16)
            ..quadraticBezierTo(8.5, 12.8, 11.4, 16),
        );
        _line(14, 10, 18.5, 10);
        _line(14, 13.5, 17, 13.5);
      case G.repeat:
        _arrowArc(12, 12, 7, 200, 125);
        _arrowArc(12, 12, 7, 20, 125);
      case G.ruler:
        _c.save();
        _c.translate(12, 12);
        _c.rotate(-math.pi / 4);
        _c.drawRRect(RRect.fromLTRBR(-9.5, -3.6, 9.5, 3.6, const Radius.circular(1.8)), _p);
        for (var i = -1; i <= 2; i++) {
          final x = -6.3 + i * 3.4;
          _c.drawLine(Offset(x, -3.6), Offset(x, i.isEven ? -.6 : -1.6), _p);
        }
        _c.restore();
      case G.box:
        _path(
          Path()
            ..moveTo(12, 3.5)
            ..lineTo(19.8, 7.6)
            ..lineTo(19.8, 16.4)
            ..lineTo(12, 20.5)
            ..lineTo(4.2, 16.4)
            ..lineTo(4.2, 7.6)
            ..close(),
        );
        _path(
          Path()
            ..moveTo(4.4, 7.7)
            ..lineTo(12, 11.7)
            ..lineTo(19.6, 7.7),
        );
        _line(12, 11.7, 12, 20.3);
      case G.person:
        _personAt(12, 8.5, 3.4, 6.5, 19.5);
      case G.people:
        _personAt(9.3, 8.4, 3.1, 5.6, 19);
        _path(
          Path()..addArc(Rect.fromCircle(center: const Offset(16.4, 8.9), radius: 2.6), -math.pi * .55, math.pi * 1.35),
        );
        _path(
          Path()
            ..moveTo(16.8, 13.9)
            ..cubicTo(19.2, 14.1, 20.8, 15.6, 20.8, 18.6),
        );
      case G.hash:
        _line(9.6, 4, 7.8, 20);
        _line(16.2, 4, 14.4, 20);
        _line(4.5, 9, 19.8, 9);
        _line(4, 15, 19.3, 15);
      case G.trash:
        _line(4, 6.8, 20, 6.8);
        _path(
          Path()
            ..moveTo(9, 6.8)
            ..lineTo(9, 5.2)
            ..quadraticBezierTo(9, 4, 10.2, 4)
            ..lineTo(13.8, 4)
            ..quadraticBezierTo(15, 4, 15, 5.2)
            ..lineTo(15, 6.8),
        );
        _path(
          Path()
            ..moveTo(6, 6.8)
            ..lineTo(6.9, 18.6)
            ..quadraticBezierTo(7.1, 20, 8.5, 20)
            ..lineTo(15.5, 20)
            ..quadraticBezierTo(16.9, 20, 17.1, 18.6)
            ..lineTo(18, 6.8),
        );
        _line(10.2, 10.5, 10.2, 16.2);
        _line(13.8, 10.5, 13.8, 16.2);
      case G.archive:
      case G.unarchive:
        _rrect(3, 4, 21, 8.5, 1.8);
        _path(
          Path()
            ..moveTo(4.6, 8.5)
            ..lineTo(4.6, 17.8)
            ..quadraticBezierTo(4.6, 20, 6.8, 20)
            ..lineTo(17.2, 20)
            ..quadraticBezierTo(19.4, 20, 19.4, 17.8)
            ..lineTo(19.4, 8.5),
        );
        if (glyph == G.archive) {
          _line(9.8, 12.6, 14.2, 12.6);
        } else {
          _line(12, 17, 12, 11.6);
          _path(
            Path()
              ..moveTo(9.8, 13.6)
              ..lineTo(12, 11.4)
              ..lineTo(14.2, 13.6),
          );
        }
      case G.copy:
        _rrect(8.5, 8.5, 20, 20, 3);
        _path(
          Path()
            ..moveTo(15.5, 8.5)
            ..lineTo(15.5, 6.5)
            ..quadraticBezierTo(15.5, 4, 13, 4)
            ..lineTo(6.5, 4)
            ..quadraticBezierTo(4, 4, 4, 6.5)
            ..lineTo(4, 13)
            ..quadraticBezierTo(4, 15.5, 6.5, 15.5)
            ..lineTo(8.5, 15.5),
        );
      case G.eye:
      case G.eyeOff:
        _path(
          Path()
            ..moveTo(2.5, 12)
            ..cubicTo(5, 7.2, 8.3, 5.2, 12, 5.2)
            ..cubicTo(15.7, 5.2, 19, 7.2, 21.5, 12)
            ..cubicTo(19, 16.8, 15.7, 18.8, 12, 18.8)
            ..cubicTo(8.3, 18.8, 5, 16.8, 2.5, 12)
            ..close(),
        );
        _circle(12, 12, 3);
        if (glyph == G.eyeOff) _line(4.5, 4.5, 19.5, 19.5);
      case G.upload:
        _line(12, 15, 12, 4.2);
        _path(
          Path()
            ..moveTo(7.8, 8.4)
            ..lineTo(12, 4.2)
            ..lineTo(16.2, 8.4),
        );
        _tray();
      case G.download:
        _line(12, 4, 12, 14.8);
        _path(
          Path()
            ..moveTo(7.8, 10.6)
            ..lineTo(12, 14.8)
            ..lineTo(16.2, 10.6),
        );
        _tray();
      case G.close:
        _line(6.5, 6.5, 17.5, 17.5);
        _line(17.5, 6.5, 6.5, 17.5);
      case G.check:
        _path(
          Path()
            ..moveTo(5, 12.6)
            ..lineTo(9.7, 17.2)
            ..lineTo(19, 7.4),
        );
      case G.chevronRight:
        _path(
          Path()
            ..moveTo(9.5, 5.5)
            ..lineTo(16, 12)
            ..lineTo(9.5, 18.5),
        );
      case G.chevronLeft:
        _path(
          Path()
            ..moveTo(14.5, 5.5)
            ..lineTo(8, 12)
            ..lineTo(14.5, 18.5),
        );
      case G.chevronDown:
        _path(
          Path()
            ..moveTo(5.5, 9.5)
            ..lineTo(12, 16)
            ..lineTo(18.5, 9.5),
        );
      case G.arrowRight:
        _line(4.5, 12, 19, 12);
        _path(
          Path()
            ..moveTo(13.5, 6.5)
            ..lineTo(19, 12)
            ..lineTo(13.5, 17.5),
        );
      case G.arrowUpRight:
        _line(6.5, 17.5, 17.5, 6.5);
        _path(
          Path()
            ..moveTo(8.5, 6.5)
            ..lineTo(17.5, 6.5)
            ..lineTo(17.5, 15.5),
        );
      case G.more:
        _dot(5.5, 12, 1.6);
        _dot(12, 12, 1.6);
        _dot(18.5, 12, 1.6);
      case G.bell:
        _path(
          Path()
            ..moveTo(6, 16.5)
            ..lineTo(6, 11)
            ..cubicTo(6, 7.4, 8.6, 5.2, 12, 5.2)
            ..cubicTo(15.4, 5.2, 18, 7.4, 18, 11)
            ..lineTo(18, 16.5)
            ..lineTo(19.6, 18.2)
            ..lineTo(4.4, 18.2)
            ..close(),
        );
        _path(
          Path()
            ..moveTo(10, 20.6)
            ..quadraticBezierTo(12, 22, 14, 20.6),
        );
        _line(12, 5.2, 12, 3.4);
      case G.calendar:
        _rrect(3.5, 5, 20.5, 20, 3.5);
        _line(3.5, 9.8, 20.5, 9.8);
        _line(8, 3.2, 8, 6.6);
        _line(16, 3.2, 16, 6.6);
        _dot(12, 14.8, 1.35);
      case G.clock:
        _circle(12, 12, 8.6);
        _path(
          Path()
            ..moveTo(12, 7.4)
            ..lineTo(12, 12)
            ..lineTo(15, 14),
        );
      case G.cake:
        _path(
          Path()
            ..moveTo(5.2, 20)
            ..lineTo(5.2, 14.2)
            ..quadraticBezierTo(5.2, 12, 7.4, 12)
            ..lineTo(16.6, 12)
            ..quadraticBezierTo(18.8, 12, 18.8, 14.2)
            ..lineTo(18.8, 20),
        );
        _line(3.8, 20, 20.2, 20);
        _path(
          Path()
            ..moveTo(5.2, 15.6)
            ..quadraticBezierTo(7.5, 17.4, 9.7, 15.6)
            ..quadraticBezierTo(12, 13.8, 14.3, 15.6)
            ..quadraticBezierTo(16.5, 17.4, 18.8, 15.6),
        );
        _line(12, 12, 12, 8.6);
        _c.drawPath(
          Path()
            ..moveTo(12, 3.6)
            ..quadraticBezierTo(13.7, 5.6, 12, 6.9)
            ..quadraticBezierTo(10.3, 5.6, 12, 3.6)
            ..close(),
          _f,
        );
      case G.warning:
        _path(
          Path()
            ..moveTo(10.3, 4.9)
            ..quadraticBezierTo(12, 2.2, 13.7, 4.9)
            ..lineTo(20.6, 16.9)
            ..quadraticBezierTo(22.1, 19.6, 19, 19.6)
            ..lineTo(5, 19.6)
            ..quadraticBezierTo(1.9, 19.6, 3.4, 16.9)
            ..close(),
        );
        _line(12, 9.4, 12, 13.4);
        _dot(12, 16.3, 1.15);
      case G.lock:
      case G.unlock:
        _rrect(5, 10.5, 19, 20.5, 3);
        _path(
          glyph == G.lock
              ? (Path()
                  ..moveTo(8, 10.5)
                  ..lineTo(8, 8)
                  ..cubicTo(8, 5.4, 9.7, 3.8, 12, 3.8)
                  ..cubicTo(14.3, 3.8, 16, 5.4, 16, 8)
                  ..lineTo(16, 10.5))
              : (Path()
                  ..moveTo(8, 10.5)
                  ..lineTo(8, 8)
                  ..cubicTo(8, 5.4, 9.7, 3.8, 12, 3.8)
                  ..cubicTo(14, 3.8, 15.5, 5, 15.9, 7)),
        );
        _dot(12, 14.6, 1.4);
        _line(12, 15.4, 12, 17.3);
      case G.key:
        _circle(8, 15.6, 4.1);
        _line(10.9, 12.7, 19.6, 4);
        _line(16.6, 7, 19, 9.4);
        _line(14.3, 9.3, 16.2, 11.2);
      case G.shield:
        _path(
          Path()
            ..moveTo(12, 3.4)
            ..lineTo(19.2, 6.3)
            ..lineTo(19.2, 11.4)
            ..cubicTo(19.2, 15.8, 16.2, 19, 12, 20.6)
            ..cubicTo(7.8, 19, 4.8, 15.8, 4.8, 11.4)
            ..lineTo(4.8, 6.3)
            ..close(),
        );
        _path(
          Path()
            ..moveTo(9, 12)
            ..lineTo(11.2, 14.2)
            ..lineTo(15.2, 10),
        );
      case G.fingerprint:
        _path(
          Path()
            ..moveTo(5.2, 16.2)
            ..cubicTo(4.6, 14.9, 4.4, 13.5, 4.4, 12)
            ..cubicTo(4.4, 7.6, 7.8, 4.4, 12, 4.4)
            ..cubicTo(16.2, 4.4, 19.6, 7.6, 19.6, 12),
        );
        _path(
          Path()
            ..moveTo(8.8, 19.6)
            ..cubicTo(8.2, 17.6, 7.9, 15.2, 7.9, 12.4)
            ..cubicTo(7.9, 9.9, 9.7, 8, 12, 8)
            ..cubicTo(14.3, 8, 16.1, 9.9, 16.1, 12.4)
            ..lineTo(16.1, 13.2),
        );
        _path(
          Path()
            ..moveTo(12, 11.8)
            ..lineTo(12, 14.4)
            ..cubicTo(12, 16.6, 12.8, 18.5, 14.2, 20),
        );
        _path(
          Path()
            ..moveTo(19.3, 15.6)
            ..cubicTo(19, 17, 18.5, 18.3, 17.8, 19.4),
        );
      case G.faceId:
        _corners(3.5, 4.2, 2.6);
        _line(9, 9.4, 9, 10.8);
        _line(15, 9.4, 15, 10.8);
        _path(
          Path()
            ..moveTo(12.2, 9.4)
            ..lineTo(12.2, 13)
            ..lineTo(11.2, 13),
        );
        _path(
          Path()
            ..moveTo(9, 15.6)
            ..quadraticBezierTo(12, 17.8, 15, 15.6),
        );
      case G.sun:
        _circle(12, 12, 3.8);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          _line(12 + 6.4 * math.cos(a), 12 + 6.4 * math.sin(a), 12 + 8.4 * math.cos(a), 12 + 8.4 * math.sin(a));
        }
      case G.moon:
        _path(
          Path()
            ..moveTo(19.2, 14.6)
            ..arcToPoint(const Offset(9.4, 4.8), radius: const Radius.circular(8), largeArc: true)
            ..arcToPoint(const Offset(19.2, 14.6), radius: const Radius.circular(6.6), clockwise: false),
        );
      case G.phone:
        _rrect(6.8, 3, 17.2, 21, 3);
        _line(10.6, 17.8, 13.4, 17.8);
      case G.notes:
        _rrect(4.5, 3.5, 19.5, 20.5, 3);
        _line(8, 8.5, 16, 8.5);
        _line(8, 12, 16, 12);
        _line(8, 15.5, 12.5, 15.5);
      case G.flame:
        _path(
          Path()
            ..moveTo(12, 20.8)
            ..cubicTo(8.4, 20.8, 6, 18.3, 6, 15)
            ..cubicTo(6, 11.6, 8.6, 9.6, 9.8, 7.2)
            ..cubicTo(10.4, 8.8, 11.2, 9.8, 12.2, 10.2)
            ..cubicTo(12.2, 7, 13.6, 4.8, 15.6, 3.4)
            ..cubicTo(15.6, 7.2, 18, 9.8, 18, 14.6)
            ..cubicTo(18, 18.3, 15.6, 20.8, 12, 20.8)
            ..close(),
        );
      case G.info:
        _circle(12, 12, 8.6);
        _line(12, 11, 12, 16.2);
        _dot(12, 7.9, 1.15);
      case G.filter:
        _line(4, 7, 20, 7);
        _line(7, 12, 17, 12);
        _line(10, 17, 14, 17);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color || old.stroke != stroke;
}
