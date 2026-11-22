import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'engine.dart';
import 'style.dart';

/// The pencil hand: a smooth, slightly-off-true offset round the oval (periodic, so the line closes).
final double Function(double) _wobble = () {
  final rnd = math.Random(11);
  const ks = [1, 2, 3, 5, 8, 13];
  final ph = [for (final _ in ks) rnd.nextDouble() * 2 * math.pi];
  final w = [for (final k in ks) (0.5 + rnd.nextDouble()) / math.sqrt(k)];
  return (double u) {
    var o = 0.0;
    for (var j = 0; j < ks.length; j++) {
      o += w[j] * math.sin(2 * math.pi * ks[j] * u + ph[j]);
    }
    return o * 0.45;
  };
}();

/// The oval in pencil from u0 for len of a lap (negative: the other way).
List<Pt> _pencil(Oval oval, double u0, double len) {
  final n = math.max(2, (len.abs() * 480).ceil());
  return [
    for (var i = 0; i <= n; i++)
      () {
        final u = u0 + len * i / n, o = _wobble(u), p = oval.along(u), nn = oval.normalAt(u);
        return Pt(p.x + nn.x * o, p.y + nn.y * o);
      }(),
  ];
}

/// The drawing box, in metres, wide enough for lane 8 so a lane change doesn't rescale it.
const double _hx = straight / 2 + 45.24 + 4, _hy = 45.24 + 4;
const double trackAspect = _hx / _hy;

class _Frame {
  final double s, cx, cy;
  _Frame._(this.s, this.cx, this.cy);
  // a standard track keeps one scale for every lane; another shape fills the box
  factory _Frame(Size size, Oval o) {
    final hx = o.standard ? _hx : o.h + o.r + 4, hy = o.standard ? _hy : o.r + 4;
    return _Frame._(math.min(size.width / (2 * hx), size.height / (2 * hy)), size.width / 2, size.height / 2);
  }
  // the engine's oval stands upright; on screen it lies on its side
  Offset o(Pt p) => Offset(cx - p.y * s, cy + p.x * s);
}

Path _path(Iterable<Pt?> pts, Offset Function(Pt) at, {bool close = false}) {
  final path = Path();
  var pen = false;
  for (final q in pts) {
    if (q == null) {
      pen = false;
      continue;
    }
    final o = at(q);
    pen ? path.lineTo(o.dx, o.dy) : path.moveTo(o.dx, o.dy);
    pen = true;
  }
  if (close) path.close();
  return path;
}

Paint _pen(Color c, double w) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

TextPainter _text(String t, [Color c = C.ink]) => TextPainter(
  text: TextSpan(
    text: t,
    style: mono(10, color: c),
  ),
  textDirection: TextDirection.ltr,
)..layout();

bool _same(Oval a, Oval b) => a.r == b.r && a.st == b.st;

void _drawOval(Canvas c, _Frame f, Oval o) =>
    c.drawPath(_path(_pencil(o, 0, 1), f.o, close: true), _pen(C.lead.withValues(alpha: 0.85), 1));

void _drawTick(Canvas c, _Frame f, Oval o, double u, double half, double width) {
  final m = o.along(u), n = o.normalAt(u);
  c.drawLine(
    f.o(Pt(m.x - n.x * half, m.y - n.y * half)),
    f.o(Pt(m.x + n.x * half, m.y + n.y * half)),
    _pen(C.lead, width),
  );
}

void _drawTrace(Canvas c, _Frame f, List<Pt?> pts, Rect clip) {
  if (pts.isEmpty) return;
  c.save();
  c.clipRect(clip);
  c.drawPath(_path(pts, f.o), _pen(C.trace, 1));
  c.restore();
}

/// The live track: your lane in pencil, your real GPS path in faint grey (a step off the track shows
/// off it, past the page edge if it goes that far), red from the start tick to the blue dot.
class TrackPainter extends CustomPainter {
  final Oval oval;
  final List<Pt?> trace; // in the oval's frame
  final double uStart, shown; // shown: how far round, 0..1, the way you run
  final int dir;
  TrackPainter({required this.oval, required this.trace, required this.uStart, required this.shown, this.dir = 1});

  @override
  void paint(Canvas canvas, Size size) {
    final f = _Frame(size, oval);
    _drawTrace(canvas, f, trace, Rect.fromLTRB(-40, -14, size.width + 40, size.height + 14));
    _drawOval(canvas, f, oval);
    if (shown > 0.0005) canvas.drawPath(_path(_pencil(oval, uStart, dir * shown), f.o), _pen(C.ran, 1.6));
    _drawTick(canvas, f, oval, uStart, 3, 0.8);
    canvas.drawCircle(f.o(oval.along(uStart + dir * shown)), 1.6 * f.s, Paint()..color = C.you);
  }

  @override
  bool shouldRepaint(TrackPainter old) =>
      old.shown != shown ||
      old.uStart != uStart ||
      old.dir != dir ||
      !identical(old.trace, trace) ||
      old.trace.length != trace.length ||
      !_same(old.oval, oval);
}

/// A finished run on a track: the track and every GPS lap.
class SketchPainter extends CustomPainter {
  final Oval oval;
  final List<Pt?> pts;
  SketchPainter(this.oval, this.pts);

  @override
  void paint(Canvas canvas, Size size) {
    final f = _Frame(size, oval);
    _drawTrace(canvas, f, pts, Offset.zero & size);
    _drawOval(canvas, f, oval);
  }

  @override
  bool shouldRepaint(SketchPainter old) => old.pts != pts || !_same(old.oval, oval);
}

/// A kept track: its shape, where you start (the tick) and which way round (the arrow).
class TrackPicture extends CustomPainter {
  final Oval oval;
  final double uStart;
  final int dir;
  TrackPicture(this.oval, this.uStart, this.dir);

  @override
  void paint(Canvas canvas, Size size) {
    final f = _Frame(size, oval);
    _drawOval(canvas, f, oval);
    _drawTick(canvas, f, oval, uStart, 4, 1);
    // the arrow: a short run of the way you go, on the straight next to the start
    final after = oval.along(uStart + dir * 0.06).y.abs() <= oval.h;
    final a0 = after ? 0.03 : -0.09, a1 = after ? 0.09 : -0.03;
    final p0 = oval.along(uStart + dir * a0),
        p1 = oval.along(uStart + dir * a1),
        nn = oval.normalAt(uStart + dir * (a0 + a1) / 2);
    final a = f.o(Pt(p0.x - nn.x * 9, p0.y - nn.y * 9)), b = f.o(Pt(p1.x - nn.x * 9, p1.y - nn.y * 9));
    final paint = _pen(C.ran, 1.4);
    canvas.drawLine(a, b, paint);
    final d = b - a, ux = d.dx / d.distance, uy = d.dy / d.distance;
    canvas.drawLine(b, b + Offset(-ux * 6 - uy * 4, -uy * 6 + ux * 4), paint);
    canvas.drawLine(b, b + Offset(-ux * 6 + uy * 4, -uy * 6 - ux * 4), paint);
  }

  @override
  bool shouldRepaint(TrackPicture old) => old.uStart != uStart || old.dir != dir || !_same(old.oval, oval);
}

/* ---------- off the track: your route, long ways up, with a ruler in miles ---------- */

const _pad = 10.0, _rulerW = 44.0;

/// Width over height of the space a route gets in a box of this size (the ruler takes a strip).
double routeAspect(Size box, {bool ruler = true}) =>
    math.max(0.1, box.width - 2 * _pad - (ruler ? _rulerW : 0)) / math.max(1.0, box.height - 2 * _pad);

/// The convex hull: enough to measure any turn of a set of points.
List<Pt> _hull(List<Pt> ps) {
  final p = [...ps]..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  if (p.length < 3) return p;
  double cross(Pt o, Pt a, Pt b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  List<Pt> half(Iterable<Pt> pts) {
    final h = <Pt>[];
    for (final q in pts) {
      while (h.length >= 2 && cross(h[h.length - 2], h.last, q) <= 0) {
        h.removeLast();
      }
      h.add(q);
    }
    return h..removeLast();
  }

  return [...half(p), ...half(p.reversed)];
}

/// Your route turned to be drawn as big as it can in its box (width:height = aspect), start at the
/// bottom, true to shape (turned, never stretched or mirrored). It keeps the turn it had (prev)
/// unless another draws it a fifth bigger, so it doesn't spin as you go, and shrinks as it grows.
class RouteShape {
  final List<Pt?> pts; // metres, x right, y down, from the top left of the route's box
  final Pt? start, end;
  final double w, h; // metres
  final double angle; // the ground direction (radians from east) that points up the page
  final bool flip; // turned half round
  final int n;
  RouteShape._(this.pts, this.start, this.end, this.w, this.h, this.angle, this.flip, this.n);

  /// How big this route can be drawn with `angle` up, in a box aspect wide and 1 high.
  static double fitAt(List<Pt> hull, double angle, double aspect) {
    final c = math.cos(angle), s = math.sin(angle);
    var a0 = double.infinity, a1 = -double.infinity, b0 = double.infinity, b1 = -double.infinity;
    for (final p in hull) {
      final a = p.x * c + p.y * s, b = -p.x * s + p.y * c;
      a0 = math.min(a0, a);
      a1 = math.max(a1, a);
      b0 = math.min(b0, b);
      b1 = math.max(b1, b);
    }
    return math.min(aspect / math.max(b1 - b0, 1), 1 / math.max(a1 - a0, 1));
  }

  factory RouteShape(List<Pt?> raw, {double aspect = 0.6, RouteShape? prev}) {
    final ps = raw.whereType<Pt>().toList();
    if (ps.length < 2) return RouteShape._(const [], null, null, 0, 0, math.pi / 2, false, ps.length);
    final hull = _hull(ps);
    // the turn that draws it biggest; the long axis up unless that is clearly smaller
    final long = longAxis(ps).angle, longFit = fitAt(hull, long, aspect);
    var best = long, bestFit = longFit;
    for (var i = 0; i < 90; i++) {
      final a = i * math.pi / 90, f = fitAt(hull, a, aspect);
      if (f > bestFit) {
        best = a;
        bestFit = f;
      }
    }
    var angle = bestFit > 1.15 * longFit ? best : long;
    final held = prev != null && prev.n >= 2;
    if (held && bestFit <= 1.2 * fitAt(hull, prev.angle, aspect)) angle = prev.angle;
    final c = math.cos(angle), s = math.sin(angle);
    var a0 = double.infinity, a1 = -double.infinity;
    for (final p in hull) {
      final a = p.x * c + p.y * s;
      a0 = math.min(a0, a);
      a1 = math.max(a1, a);
    }
    final st = ps.first.x * c + ps.first.y * s, en = ps.last.x * c + ps.last.y * s;
    final up = (st - a0) / math.max(a1 - a0, 1e-9); // 0 = the start at the bottom (unflipped)
    bool flip;
    if (!held) {
      // first drawn: where you are now above where you started
      flip = (en - st).abs() > 0.1 * (a1 - a0) ? en < st : up > 0.5;
    } else {
      // keep pointing the way it did; turn half round only once the start is well up the page
      final was = prev.angle + (prev.flip ? math.pi : 0);
      flip = math.cos(angle + math.pi - was) > math.cos(angle - was);
      if ((flip ? 1 - up : up) > 0.7) flip = !flip;
    }
    Pt turn(Pt p) {
      final a = p.x * c + p.y * s, b = -p.x * s + p.y * c;
      return flip ? Pt(b, a) : Pt(-b, -a); // a proper turn either way
    }

    final out = [for (final q in raw) q == null ? null : turn(q)];
    var x0 = double.infinity, x1 = -double.infinity, y0 = double.infinity, y1 = -double.infinity;
    for (final q in out.whereType<Pt>()) {
      x0 = math.min(x0, q.x);
      x1 = math.max(x1, q.x);
      y0 = math.min(y0, q.y);
      y1 = math.max(y1, q.y);
    }
    final moved = [for (final q in out) q == null ? null : Pt(q.x - x0, q.y - y0)];
    final real = moved.whereType<Pt>();
    return RouteShape._(moved, real.first, real.last, x1 - x0, y1 - y0, angle, flip, ps.length);
  }
}

/// Where the route goes in a box: the scale (px a metre) and the top left of the route.
({double s, double ox, double oy}) routeFrame(RouteShape r, Size size, {bool ruler = true}) {
  final rw = ruler ? _rulerW : 0.0;
  final avW = math.max(1.0, size.width - 2 * _pad - rw), avH = math.max(1.0, size.height - 2 * _pad);
  final s = math.min(3.0, math.min(avW / math.max(r.w, 1), avH / math.max(r.h, 1)));
  return (s: s, ox: _pad + rw + (avW - r.w * s) / 2, oy: _pad + (avH - r.h * s) / 2);
}

const _ticks = [0.05, 0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 20.0];

/// Your route in pencil grey, a short level line where you started, the blue dot where you are, and
/// a small ruler in miles on its left.
class RoutePainter extends CustomPainter {
  final RouteShape route;
  final bool dot, ruler;
  RoutePainter(this.route, {this.dot = true, this.ruler = true});

  @override
  void paint(Canvas canvas, Size size) {
    if (route.pts.isEmpty) return;
    final f = routeFrame(route, size, ruler: ruler);
    Offset at(Pt p) => Offset(f.ox + p.x * f.s, f.oy + p.y * f.s);
    canvas.drawPath(_path(route.pts, at), _pen(C.ink.withValues(alpha: 0.42), 1.2));
    final st = at(route.start!);
    canvas.drawLine(st.translate(-6, 0), st.translate(6, 0), _pen(C.lead, 1));
    if (dot) canvas.drawCircle(at(route.end!), 2.6, Paint()..color = C.you);
    if (!ruler) return;
    // the longest round number of miles that fits the route's height
    final len = _ticks.lastWhere((t) => t <= route.h / mile * 0.9, orElse: () => _ticks.first);
    final px = len * mile * f.s;
    if (px < 24) return;
    final rx = f.ox - 18, bottom = f.oy + route.h * f.s, p = _pen(C.lead, 1);
    canvas.drawLine(Offset(rx, bottom), Offset(rx, bottom - px), p);
    for (final (y, w) in [(bottom, 3.0), (bottom - px, 3.0), (bottom - px / 2, 2.0)]) {
      canvas.drawLine(Offset(rx - w, y), Offset(rx + w, y), p);
    }
    final top = _text(len >= 1 ? '${len.toStringAsFixed(0)} mi' : '${'$len'.replaceFirst('0.', '.')} mi'),
        zero = _text('0');
    final lx = rx - 6 - math.max(top.width, zero.width);
    top.paint(canvas, Offset(lx, bottom - px - top.height / 2));
    zero.paint(canvas, Offset(lx, bottom - zero.height / 2));
  }

  @override
  bool shouldRepaint(RoutePainter old) => old.route != route || old.dot != dot || old.ruler != ruler;
}

/* ---------- icons, drawn in a 24-unit box ---------- */

abstract class _Icon extends CustomPainter {
  const _Icon();
  void draw(Canvas c);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    draw(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class PersonIcon extends _Icon {
  const PersonIcon();
  @override
  void draw(Canvas c) {
    final p = _pen(C.lead, 1.8);
    c.drawCircle(const Offset(12, 8), 3.8, p);
    c.drawPath(
      Path()
        ..moveTo(4.5, 20.5)
        ..cubicTo(5.3, 16.5, 8.3, 14.2, 12, 14.2)
        ..cubicTo(15.7, 14.2, 18.7, 16.5, 19.5, 20.5),
      p,
    );
  }
}

class PlayIcon extends _Icon {
  const PlayIcon();
  @override
  void draw(Canvas c) => c.drawPath(
    Path()
      ..moveTo(6, 3.5)
      ..lineTo(6, 20.5)
      ..lineTo(20.5, 12)
      ..close(),
    Paint()..color = C.go,
  );
}

class ResetIcon extends _Icon {
  const ResetIcon();
  @override
  void draw(Canvas c) {
    final p = _pen(C.ink, 1.5);
    c.drawPath(
      Path()
        ..moveTo(1, 4)
        ..lineTo(1, 10)
        ..lineTo(7, 10),
      p,
    );
    c.drawPath(
      Path()
        ..moveTo(3.51, 15)
        ..arcToPoint(const Offset(5.64, 5.64), radius: const Radius.circular(9), largeArc: true, clockwise: false)
        ..lineTo(1, 10),
      p,
    );
  }
}

class BackIcon extends _Icon {
  const BackIcon();
  @override
  void draw(Canvas c) => c.drawPath(
    Path()
      ..moveTo(15, 5)
      ..lineTo(8, 12)
      ..lineTo(15, 19),
    _pen(C.lead, 1.8),
  );
}

/// Red square, with a thin ring that fills while you hold.
class StopIcon extends CustomPainter {
  final double progress;
  StopIcon(this.progress);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawRect(
      Rect.fromCenter(center: c, width: size.width * 0.32, height: size.width * 0.32),
      Paint()..color = C.ran,
    );
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: size.width / 2 - 1.5),
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        _pen(C.ran, 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(StopIcon old) => old.progress != progress;
}

/// A dashed hairline: a stop or a stretch off the track in the list of laps.
class DashPainter extends CustomPainter {
  const DashPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = C.rule
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, 0), Offset(math.min(x + 3, size.width), 0), p);
    }
  }

  @override
  bool shouldRepaint(DashPainter old) => false;
}

/// Speed per lap: each lap's average mph as a pencil line, a faint tick up to that lap's peak, the
/// best lap in blue and the run's peak labelled.
class SpeedChart extends CustomPainter {
  final List<double> avg; // mph per lap
  final List<double> peak; // mph, each lap's fastest moment (may be shorter or empty)
  final double? top;
  SpeedChart(this.avg, this.peak, this.top);

  @override
  void paint(Canvas canvas, Size size) {
    if (avg.isEmpty) return;
    final peaks = [for (var i = 0; i < avg.length; i++) i < peak.length && peak[i] > 0 ? peak[i] : null];
    final lo = (avg.reduce(math.min) - 0.5).floorToDouble();
    final hi = ([...avg, ...peaks.whereType<double>()].reduce(math.max) + 0.5).ceilToDouble();
    const left = 34.0, right = 8.0, topPad = 18.0, bottom = 20.0;
    final w = size.width - left - right, h = size.height - topPad - bottom;
    double x(int i) => left + (avg.length == 1 ? w / 2 : w * i / (avg.length - 1));
    double y(double v) => topPad + h * (1 - (v - lo) / (hi - lo));
    canvas.drawLine(Offset(left, topPad + h), Offset(left + w, topPad + h), _pen(C.rule, 1));
    _text(hi.toStringAsFixed(0)).paint(canvas, Offset(0, y(hi) - 6));
    _text(lo.toStringAsFixed(0)).paint(canvas, Offset(0, y(lo) - 6));
    _text('1').paint(canvas, Offset(x(0) - 3, topPad + h + 5));
    if (avg.length > 1) {
      final last = _text('${avg.length}');
      last.paint(canvas, Offset(x(avg.length - 1) - last.width, topPad + h + 5));
    }
    for (var i = 0; i < avg.length; i++) {
      final p = peaks[i];
      if (p != null && p > avg[i]) canvas.drawLine(Offset(x(i), y(avg[i])), Offset(x(i), y(p)), _pen(C.trace, 1.2));
    }
    canvas.drawPath(
      _path([for (var i = 0; i < avg.length; i++) Pt(x(i), y(avg[i]))], (p) => Offset(p.x, p.y)),
      _pen(C.lead.withValues(alpha: 0.85), 1.1),
    );
    var best = 0;
    for (var i = 0; i < avg.length; i++) {
      if (avg[i] > avg[best]) best = i;
      canvas.drawCircle(Offset(x(i), y(avg[i])), avg.length > 30 ? 1.2 : 1.8, Paint()..color = C.lead);
    }
    canvas.drawCircle(Offset(x(best), y(avg[best])), 3, Paint()..color = C.you);
    var pi = -1;
    for (var i = 0; i < peaks.length; i++) {
      if (peaks[i] != null && (pi < 0 || peaks[i]! > peaks[pi]!)) pi = i;
    }
    if (pi >= 0) {
      final py = y(peaks[pi]!), px = x(pi);
      canvas.drawLine(Offset(px - 4, py), Offset(px + 4, py), _pen(C.you, 1.4));
      final label = _text('peak ${peaks[pi]!.toStringAsFixed(1)}', C.you);
      label.paint(
        canvas,
        Offset(px + 6 + label.width > size.width ? px - 6 - label.width : px + 6, py - label.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(SpeedChart old) => old.avg != avg || old.peak != peak;
}
