import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'engine.dart';
import 'goal.dart';
import 'gps.dart';
import 'painters.dart';
import 'phone.dart';
import 'store.dart';
import 'style.dart';

const holdMs = 3000;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle.dark.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: C.paper,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(
    MaterialApp(
      title: 'run laps',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: C.paper,
        fontFamily: 'RedHatMono',
        colorScheme: const ColorScheme.light(primary: C.ink, onPrimary: C.paper, surface: C.paper, onSurface: C.ink),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: C.ink,
          selectionColor: C.line,
          selectionHandleColor: C.ink,
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: C.wash,
      ),
      home: const Home(),
    ),
  );
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;

String hms(num? ms) {
  if (ms == null || !ms.isFinite) return '—';
  final s = ms ~/ 1000, h = s ~/ 3600, m = (s ~/ 60) % 60, x = s % 60;
  String p(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${p(m)}:${p(x)}' : '$m:${p(x)}';
}

String f1(num? v) => v == null ? '—' : v.toStringAsFixed(1);
String miles(num metres) => '${trim2(metres / mile)} mi';

String whenOf(int id, {bool long = false}) {
  final d = DateTime.fromMillisecondsSinceEpoch(id);
  const mo = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
  const wd = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final time = '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'am' : 'pm'}';
  return '${long ? '${wd[d.weekday - 1]}, ' : ''}${mo[d.month - 1]} ${d.day} · $time';
}

/// One screen-reader node for a control.
Widget a11y(String label, Widget child, {bool button = true, bool? selected}) =>
    Semantics(container: true, excludeSemantics: true, button: button, selected: selected, label: label, child: child);

Widget tap(String label, VoidCallback onTap, Widget child, {bool? selected}) => a11y(
  label,
  GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: child),
  selected: selected,
);

Widget label(String t) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 26, 0, 10),
  child: Text(t, style: mono(12)),
);

Widget link(String t, VoidCallback onTap) => tap(
  t,
  onTap,
  Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 0, 12),
    child: Text(t, style: mono(13, underline: true)),
  ),
);

/// A page with a top bar and a scrolling column.
Widget page(Widget left, Widget right, List<Widget> children) => Scaffold(
  body: SafeArea(
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(height: 48, child: Row(children: [left, const Spacer(), right])),
        ),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: children),
        ),
      ],
    ),
  ),
);

/// A link that asks for a second tap within 3 s.
class Confirm extends StatefulWidget {
  final String text;
  final VoidCallback onConfirm;
  final EdgeInsets pad;
  const Confirm(this.text, this.onConfirm, {super.key, required this.pad});
  @override
  State<Confirm> createState() => _ConfirmState();
}

class _ConfirmState extends State<Confirm> {
  int armed = 0;
  @override
  Widget build(BuildContext context) {
    final on = nowMs() - armed <= 3000;
    return tap(
      widget.text,
      () {
        setState(() => armed = on ? 0 : nowMs());
        if (on) widget.onConfirm();
      },
      Padding(
        padding: widget.pad,
        child: Text(
          on ? 'tap again to ${widget.text.split(' ').first}' : widget.text,
          style: mono(13, color: on ? C.ran : C.ink, underline: true),
        ),
      ),
    );
  }
}

class _Hold {
  final int pressT, snapN;
  final Frac snapFrac;
  final double snapOff;
  final sw = Stopwatch()..start();
  bool confirmed = false;
  _Hold(this.pressT, this.snapN, this.snapFrac, this.snapOff);
}

/* ---------- the run screen ---------- */

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final goal = Goal.fromJson((Store.get('laps.settings') as Map?)?.cast<String, dynamic>());
  late final gps = Gps(_onFix, () {
    if (mounted) setState(() {});
  });
  late final Ticker _ticker = createTicker(_tick); // only while the stop is held: the ring fills smoothly
  late final Timer _second;
  String phase = 'ready'; // ready | running | done
  Run? run;
  int? finalT;
  Frac? finalFrac;
  int lastSave = 0, fixes = 0;
  _Hold? hold;
  Timer? hintTimer;
  bool hint = false, offPrev = false, gpsShown = Store.get('laps.gpsShown') == true;
  String sensePrev = 'default';
  List<Pt?> traceOnOval = const [];
  Object? traceKey, routeKey;
  RouteShape? route;

  @override
  void initState() {
    super.initState();
    final saved = (Store.get('laps.run') as Map?)?.cast<String, dynamic>();
    if (saved != null && const ['running', 'done'].contains(saved['phase'])) {
      try {
        run = Run.fromJson((saved['run'] as Map).cast<String, dynamic>());
        phase = saved['phase'] as String;
        finalT = (saved['finalT'] as num?)?.toInt();
        finalFrac = saved['finalFrac'] == null ? null : Frac.fromJson(saved['finalFrac'] as List);
        sensePrev = run!.sense;
        offPrev = run!.off;
        debugPrint('LAPS restored $phase run at ${hms(activeMs(run!, finalT ?? nowMs()))}');
      } catch (e) {
        debugPrint('LAPS restore failed $e');
        run = null;
        phase = 'ready';
      }
    }
    gps.init().then((_) {
      if (phase == 'running') gps.start(foreground: true);
    });
    _second = Timer.periodic(const Duration(seconds: 1), (_) => _everySecond());
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _second.cancel();
    gps.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      // permission may have changed in system settings: restart GPS unless it is delivering
      if (gps.state != GpsState.ok) gps.start(foreground: phase == 'running');
      setState(() {});
    } else if (s == AppLifecycleState.paused) {
      _save();
    }
  }

  void _tick(Duration d) {
    if (hold != null && !hold!.confirmed && hold!.sw.elapsedMilliseconds >= holdMs) _confirmStop();
    setState(() {});
  }

  void _everySecond() {
    if (phase != 'running' || !mounted) return;
    if (nowMs() - lastSave > 15000) _save();
    setState(() {});
  }

  void _onFix(Fix f) {
    final r = run;
    if (phase != 'running' || r == null) return;
    final n = feed(r, f);
    if (++fixes % 10 == 0) {
      debugPrint(
        'LAPS fix acc=${f.acc.toStringAsFixed(1)} spd=${f.spd?.toStringAsFixed(2)} laps=${r.laps.length} since=${r.since.round()}',
      );
    }
    if (n > 0) {
      HapticFeedback.mediumImpact();
      if (Store.get('laps.bell') == true) ringBell();
      _save();
      debugPrint('LAPS lap ${r.laps.length} at ${hms(activeMs(r, r.laps.last))} top=${f1(r.top * mpsToMph)}mph');
    }
    if (r.sense != sensePrev) {
      debugPrint(
        'LAPS track ${r.sense} at ${hms(activeMs(r, f.t))}: ${r.dir == 1 ? 'counter-clockwise' : 'clockwise'}, '
        '${r.oval.standard ? 'standard' : '${r.L.round()} m'} track, start ${r.uStart?.toStringAsFixed(3)}'
        '${r.sensedAt == f.t ? ' (redrawn)' : ''}',
      );
      sensePrev = r.sense;
      if (r.sense == 'refined') _saveTrack();
    }
    if (r.off != offPrev) {
      offPrev = r.off;
      if (r.off) HapticFeedback.heavyImpact();
      final s = stats(r, f.t, fracs(r));
      debugPrint('LAPS ${r.off ? 'off the track' : 'back on the track'} at ${hms(s.el)}, ${s.metres.round()} m');
    }
  }

  void _saveTrack() {
    final t = trackOf(run!, nowMs());
    if (t != null) Store.saveTracks(withTrack(Store.tracks(), t));
  }

  /// Your path in the drawing's frame: on the track once it is known, else as assumed.
  List<Pt?> _trace() {
    final r = run, g = r == null ? null : drawGeo(r);
    if (g == null) return const [];
    final key = (g.c, g.s, g.tx, g.ty, r!.trace.length);
    if (key != traceKey) {
      traceKey = key;
      traceOnOval = [for (final q in r.trace) q == null ? null : g.apply(q)];
    }
    return traceOnOval;
  }

  RouteShape _route(double aspect) {
    final key = (run!.trace.length, aspect);
    if (route == null || key != routeKey) {
      route = RouteShape(run!.trace, aspect: aspect, prev: route);
      routeKey = key;
    }
    return route!;
  }

  void _save() {
    lastSave = nowMs();
    if (run != null) {
      Store.set('laps.run', {'phase': phase, 'run': run!.toJson(), 'finalT': finalT, 'finalFrac': finalFrac?.toJson()});
    }
  }

  /// Battery mode: the phone's battery saver on for the run, and back off after if we turned it on.
  Future<void> _saver(bool on) async {
    if (on) {
      if (Store.get('laps.battery') != false && await batterySaver(true)) Store.set('laps.saverOn', true);
    } else if (Store.get('laps.saverOn') == true) {
      Store.set('laps.saverOn', null);
      await batterySaver(false);
    }
  }

  Future<void> _start() async {
    if (!Store.flag('laps.asked')) {
      await unrestrict();
      await Store.setFlag('laps.asked');
    }
    final t0 = nowMs(), l = gps.last;
    setState(() {
      run = Run(goal.lane, t0, dir: Store.defaultDir(), tracks: Store.tracks());
      if (l != null && t0 - l.t < 4000) feed(run!, Fix(l.lat, l.lon, l.acc, t0, spd: l.spd, spdAcc: l.spdAcc));
      sensePrev = run!.sense;
      offPrev = false;
      traceKey = null;
      route = null;
      phase = 'running';
      finalT = null;
      finalFrac = null;
    });
    await gps.start(foreground: true);
    _saver(true);
    _save();
    debugPrint('LAPS start lane=${goal.lane} L=${run!.L.toStringAsFixed(2)}');
  }

  void _beginHold() {
    if (phase != 'running' || hold != null) return;
    setState(() => hold = _Hold(nowMs(), run!.laps.length, fracs(run!), run!.offM));
    if (!_ticker.isActive) _ticker.start();
    debugPrint('LAPS hold pressed at ${hms(activeMs(run!, hold!.pressT))}');
  }

  void _endHold() {
    if (hold == null) return;
    if (!hold!.confirmed) {
      debugPrint('LAPS hold released early');
      hint = true;
      hintTimer?.cancel();
      hintTimer = Timer(const Duration(milliseconds: 1800), () {
        if (mounted) setState(() => hint = false);
      });
    }
    if (_ticker.isActive) _ticker.stop();
    setState(() => hold = null);
  }

  void _confirmStop() {
    final r = run!, t = hold!.pressT;
    stopAt(r, t); // the stop counts from the moment you pressed
    r.offM = math.min(r.offM, hold!.snapOff);
    finalT = t;
    finalFrac = r.laps.length > hold!.snapN ? Frac.zero : hold!.snapFrac;
    phase = 'done';
    hold!.confirmed = true;
    HapticFeedback.heavyImpact();
    _saveTrack();
    _saveHistory();
    _save();
    _saver(false);
    gps.start(foreground: false);
    debugPrint('LAPS stop at ${hms(activeMs(r, t))} (held until ${hms(activeMs(r, nowMs()))}) laps=${r.laps.length}');
  }

  void _saveHistory() {
    final e = historyEntry(run!, finalT!, finalFrac, goal.label);
    if ((e['el'] as int) < 60000 && (e['metres'] as int) < 100) return; // a start and stop by accident
    Store.saveHistory([e, ...Store.history().where((x) => x['id'] != e['id'])]);
  }

  Future<void> _continue() async {
    setState(() {
      resumeRun(run!, finalT!, nowMs());
      finalT = null;
      finalFrac = null;
      phase = 'running';
    });
    await gps.start(foreground: true);
    _saver(true);
    _save();
    debugPrint('LAPS continue at ${hms(activeMs(run!, nowMs()))}');
  }

  void _reset() {
    setState(() {
      phase = 'ready';
      run = null;
      finalT = null;
      finalFrac = null;
      traceKey = null;
      route = null;
    });
    Store.set('laps.run', null);
  }

  Stats? _stats() => switch (phase) {
    'running' => stats(run!, nowMs(), fracs(run!)),
    'done' => stats(run!, finalT!, finalFrac ?? Frac.zero),
    _ => null,
  };

  Future<void> _openProfile() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilePage(
          goal: goal,
          running: phase == 'running',
          onChanged: () {
            Store.set('laps.settings', goal.toJson());
            run?.reachedEl = null;
            setState(() {});
          },
        ),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats(), r = run, h = MediaQuery.sizeOf(context).height;
    if (s != null && phase == 'running' && r!.reachedEl == null && s.metres >= goal.metres) r.reachedEl = s.el;
    final reached = r?.reachedEl != null && s != null && r!.reachedEl! <= s.el;
    final dim = phase == 'running' && Store.get('laps.battery') != false;
    return Stack(
      children: [
        Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  SizedBox(
                    height: 48,
                    child: Row(
                      children: [
                        _gpsCorner(),
                        const Spacer(),
                        a11y(
                          'Profile',
                          InkResponse(
                            onTap: _openProfile,
                            radius: 24,
                            child: const SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: CustomPaint(size: Size(24, 24), painter: PersonIcon()),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  r != null && r.off ? _offView(h) : _trackView(h, s?.show ?? 0),
                  const SizedBox(height: 12),
                  Expanded(child: _ledger(s, reached)),
                  SizedBox(height: 20, child: _sensedNote()),
                  SizedBox(height: 80, child: _controls()),
                  SizedBox(
                    height: 18,
                    child: AnimatedOpacity(
                      opacity: hint ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Text('hold 3 s to stop', style: mono(12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // battery mode: a little dimmer while you run (darker pixels cost less on an OLED screen)
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(duration: const Duration(milliseconds: 600), color: Color(dim ? 0x26000000 : 0)),
          ),
        ),
      ],
    );
  }

  Widget _trackView(double h, double shown) {
    final r = run, o = r?.oval ?? Oval.lane(goal.lane);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: h * 0.27),
      child: AspectRatio(
        aspectRatio: trackAspect,
        child: CustomPaint(
          painter: TrackPainter(
            oval: o,
            trace: _trace(),
            uStart: r == null ? o.uFinish : uStartShown(r),
            shown: shown,
            dir: r?.dir ?? Store.defaultDir(),
          ),
        ),
      ),
    );
  }

  /// Off the track: the words on the left, your route up the right, with a ruler in miles.
  Widget _offView(double h) {
    final box = Size((MediaQuery.sizeOf(context).width - 32) * 0.4, h * 0.3), rt = _route(routeAspect(box));
    return SizedBox(
      height: box.height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, right: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Run Forrest run!', style: mono(28, weight: 300, height: 1.15)),
                  const SizedBox(height: 6),
                  Text('You are off the reservation.', style: mono(13)),
                ],
              ),
            ),
          ),
          a11y(
            'your route, ${miles(rt.h)} end to end',
            CustomPaint(size: box, painter: RoutePainter(rt)),
            button: false,
          ),
        ],
      ),
    );
  }

  Widget _sensedNote() {
    final r = run;
    final on = phase == 'running' && r != null && !r.off && r.sensedAt != null && nowMs() - r.sensedAt! < 20000;
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedOpacity(
        opacity: on ? 1 : 0,
        duration: const Duration(milliseconds: 400),
        child: Text('track shape sensed', style: mono(12)),
      ),
    );
  }

  /// Empty, unless GPS needs you (red, tap for settings) or a tap here turned the reading on.
  Widget _gpsCorner() {
    final acc = gps.last?.acc ?? 0;
    final (t, bad) = switch (gps.state) {
      GpsState.waiting => ('gps …', false),
      GpsState.ok => ('gps ${acc.round()} m', acc > 30),
      GpsState.denied => ('no gps · allow', true),
      GpsState.off => ('gps off · turn on', true),
      GpsState.approx => ('gps approx · allow precise', true),
      GpsState.lost => ('gps lost', true),
    };
    if (!bad) {
      return GestureDetector(
        onTap: () {
          setState(() => gpsShown = !gpsShown);
          Store.set('laps.gpsShown', gpsShown);
        },
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        child: SizedBox(
          width: 150,
          height: 48,
          child: Align(
            alignment: Alignment.centerLeft,
            child: gpsShown ? Text(t, style: mono(13)) : null,
          ),
        ),
      );
    }
    final text = Text(t, style: mono(13, color: C.ran));
    return gps.state == GpsState.lost
        ? a11y('GPS status: $t', text, button: false)
        : tap(
            'GPS status: $t',
            gps.openSettings,
            Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: text),
          );
  }

  Widget _ledger(Stats? s, bool reached) {
    final rows = <(String, String, String?)>[
      ('laps', '${s?.n ?? 0}', '/${lapsTxt(goal.metres / (run?.L ?? goal.lapM))}'),
      ('completed', '${s == null ? 0 : (s.metres / goal.metres * 100).floor()}%', null),
      ('time', hms(s?.el ?? 0), null),
      ('avg lap', hms(s?.avgLap), null),
      ('mph', f1(s?.mph), null),
      ('top mph', f1(s?.topMph), null),
      reached
          ? ('finished', hms(run!.reachedEl), null)
          : ('finish', s != null && s.metres >= 100 ? hms(s.el * goal.metres / s.metres) : '—', null),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final rowH = math.min(62.0, c.maxHeight / rows.length), fs = math.min(36.0, rowH * 0.56);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final (i, (k, v, of)) in rows.indexed)
              Container(
                height: rowH,
                decoration: BoxDecoration(
                  border: Border(
                    top: i == 0 ? const BorderSide(color: C.rule) : BorderSide.none,
                    bottom: const BorderSide(color: C.rule),
                  ),
                ),
                child: Row(
                  children: [
                    Text(k, style: mono(13)),
                    const Spacer(),
                    Semantics(
                      container: true,
                      excludeSemantics: true,
                      label: k,
                      value: of == null ? v : '$v of ${of.substring(1)}',
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: v, style: mono(fs, weight: 300, height: 1)),
                            if (of != null) TextSpan(text: ' $of', style: mono(fs * 0.5, weight: 300)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _iconButton(String label, CustomPainter p, double size, VoidCallback onTap) => a11y(
    label,
    InkResponse(
      onTap: onTap,
      radius: 34,
      child: SizedBox(
        width: 68,
        height: 68,
        child: Center(
          child: CustomPaint(size: Size(size, size), painter: p),
        ),
      ),
    ),
  );

  Widget _controls() => switch (phase) {
    'running' => Center(
      child: a11y(
        'Stop, hold for 3 seconds',
        Listener(
          onPointerDown: (_) => _beginHold(),
          onPointerUp: (_) => _endHold(),
          onPointerCancel: (_) => _endHold(),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 72,
            height: 72,
            child: Center(
              child: CustomPaint(
                size: const Size(52, 52),
                painter: StopIcon(
                  hold != null && !hold!.confirmed ? math.min(1.0, hold!.sw.elapsedMilliseconds / holdMs) : 0,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    'done' => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _iconButton('Reset', const ResetIcon(), 28, _reset),
        const SizedBox(width: 56),
        _iconButton('Continue', const PlayIcon(), 30, _continue),
      ],
    ),
    _ => Center(child: _iconButton('Start', const PlayIcon(), 30, _start)),
  };
}

/* ---------- profile: settings and history ---------- */

class ProfilePage extends StatefulWidget {
  final Goal goal;
  final bool running;
  final VoidCallback onChanged;
  const ProfilePage({super.key, required this.goal, required this.running, required this.onChanged});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final amount = TextEditingController(text: g.fieldText);
  final focus = FocusNode();
  bool bad = false, adv = false, saverOk = false;
  Goal get g => widget.goal;

  @override
  void initState() {
    super.initState();
    focus.addListener(() {
      if (focus.hasFocus) {
        amount.selection = TextSelection(baseOffset: 0, extentOffset: amount.text.length);
      } else {
        setState(_sync);
      }
    });
    canSetSaver().then((v) {
      if (mounted) setState(() => saverOk = v);
    });
  }

  void _sync() {
    amount.text = g.fieldText;
    bad = false;
  }

  void _changed() {
    widget.onChanged();
    setState(() {});
  }

  Widget _note(String t, {Color color = C.ink}) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 0, 0),
    child: Text(t, style: mono(12, color: color)),
  );

  @override
  Widget build(BuildContext context) {
    final runs = Store.history();
    return page(Text('run laps', style: mono(13, weight: 500)), link('done', () => Navigator.of(context).pop()), [
      label('distance'),
      _box(
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: g.preset,
            isExpanded: true,
            icon: const Icon(Icons.expand_more, color: C.ink, size: 22),
            style: mono(17),
            borderRadius: BorderRadius.circular(16),
            dropdownColor: C.paper,
            items: [
              for (final p in presets) DropdownMenuItem(value: p.k, child: Text(p.label)),
              const DropdownMenuItem(value: '', child: Text('custom')),
            ],
            onChanged: (k) {
              g.pickPreset(k ?? '');
              _sync();
              _changed();
              if ((k ?? '').isEmpty) focus.requestFocus();
            },
          ),
        ),
      ),
      const SizedBox(height: 10),
      _box(
        padRight: 6,
        focused: focus.hasFocus,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: amount,
                focusNode: focus,
                style: mono(17),
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  hintText: 'or type 5k, 40 laps',
                  hintStyle: mono(17, color: C.ink.withValues(alpha: 0.35)),
                ),
                onChanged: (t) {
                  bad = t.trim().isNotEmpty && !g.takeTyped(t);
                  _changed();
                },
                onSubmitted: (_) => focus.unfocus(),
              ),
            ),
            _pills(const ['mi', 'laps'], g.unit, (u) {
              g.setUnit(u);
              _sync();
              _changed();
            }, height: 40),
          ],
        ),
      ),
      _note(
        bad ? 'type miles, 5k, or 40 laps' : '= ${miles(g.metres)} · ${lapsTxt(g.laps)} laps',
        color: bad ? C.ran : C.ink,
      ),
      label('lane'),
      Opacity(
        opacity: widget.running ? 0.4 : 1,
        child: IgnorePointer(
          ignoring: widget.running,
          child: _pills([for (var i = 1; i <= 8; i++) '$i'], '${g.lane}', (l) {
            g.setLane(int.parse(l));
            _sync();
            _changed();
          }),
        ),
      ),
      _note(
        'lane ${g.lane} · ${laneLength(g.lane).toStringAsFixed(2)} m a lap · 4 laps = ${miles(4 * laneLength(g.lane))}'
        '${widget.running ? ' · after this run' : ''}',
      ),
      _advanced(),
      label('history'),
      if (runs.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: card,
          child: Text('no runs yet. stop a run and it shows up here.', style: mono(13)),
        ),
      for (final e in runs) _card(e),
    ]);
  }

  Widget _card(Map<String, dynamic> e) {
    final n = e['n'] as int, when = whenOf(e['id'] as int);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: a11y(
        'Run $when',
        InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            final deleted = await Navigator.of(context)
                .push<bool>(MaterialPageRoute(builder: (_) => RunPage(entry: e)));
            if (deleted == true) setState(() {});
          },
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
            decoration: card,
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  height: 72 / trackAspect,
                  child: CustomPaint(painter: entrySketch(e, ruler: false)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(miles(e['metres'] as num), style: mono(18, weight: 300)),
                          const Spacer(),
                          Text(hms(e['el'] as num), style: mono(18, weight: 300)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$when · $n ${n == 1 ? 'lap' : 'laps'} · lane ${e['lane'] ?? 1}',
                        style: mono(12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The track as sensed (its shape, where you last started, which way round), battery mode, the bell.
  Widget _advanced() {
    final tracks = Store.tracks()..sort((a, b) => ((b['used'] as num?) ?? 0).compareTo((a['used'] as num?) ?? 0));
    final t = tracks.firstOrNull, o = trackOval(t, g.lane), std = t == null || (t['std'] as bool? ?? true);
    final dir = (t?['dir'] as num?)?.toInt() ?? Store.defaultDir(), u0 = (t?['u0'] as num?)?.toDouble() ?? o.uFinish;
    final way = dir == 1 ? 'counter-clockwise' : 'clockwise';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tap(
          adv ? 'Hide advanced' : 'Show advanced',
          () => setState(() => adv = !adv),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 26, 0, 10),
            child: Text('advanced ${adv ? '−' : '+'}', style: mono(12)),
          ),
        ),
        if (adv)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            decoration: card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                a11y(
                  'track picture: start tick, $way arrow',
                  AspectRatio(
                    aspectRatio: trackAspect,
                    child: CustomPaint(painter: TrackPicture(o, u0, dir)),
                  ),
                  button: false,
                ),
                const SizedBox(height: 14),
                Text(
                  t == null
                      ? 'no track sensed yet'
                      : (std ? 'standard 400 m track' : '${o.perim.round()} m track, as sensed'),
                  style: mono(13),
                ),
                const SizedBox(height: 4),
                Text(
                  t == null
                      ? 'until GPS sees your first bend: a standard track, started at the finish line'
                      : 'sensed ${whenOf((t['used'] as num).toInt())} · the tick is where you started',
                  style: mono(12),
                ),
                const SizedBox(height: 14),
                _pills(const ['counter-clockwise', 'clockwise'], way, (v) {
                  final d = v == 'clockwise' ? -1 : 1;
                  if (t == null) {
                    Store.setDefaultDir(d);
                  } else {
                    t['dir'] = d;
                    Store.saveTracks(tracks);
                  }
                  setState(() {});
                }, height: 40),
                if (t != null)
                  Confirm('forget this track', () {
                    Store.saveTracks(tracks.skip(1).toList());
                    setState(() {});
                  }, pad: const EdgeInsets.only(top: 14, bottom: 2)),
                Container(height: 1, color: C.rule, margin: const EdgeInsets.symmetric(vertical: 18)),
                _option(
                  'battery mode',
                  Store.get('laps.battery') != false,
                  (on) => Store.set('laps.battery', on ? null : false),
                ),
                Text(
                  saverOk
                      ? 'a bit dimmer while you run, with the phone on battery saver'
                      : 'a bit dimmer while you run',
                  style: mono(12),
                ),
                const SizedBox(height: 14),
                _option('lap bell', Store.get('laps.bell') == true, (on) {
                  Store.set('laps.bell', on ? true : null);
                  if (on) ringBell();
                }),
              ],
            ),
          ),
      ],
    );
  }

  Widget _option(String name, bool on, ValueChanged<bool> set) => Row(
    children: [
      Text(name, style: mono(13)),
      const Spacer(),
      _pills(const ['on', 'off'], on ? 'on' : 'off', (v) {
        set(v == 'on');
        setState(() {});
      }, height: 40),
    ],
  );

  Widget _box({required Widget child, double padRight = 18, bool focused = false}) => Container(
    height: 52,
    padding: EdgeInsets.only(left: 18, right: padRight),
    decoration: BoxDecoration(
      border: Border.all(color: focused ? C.ink : C.line),
      borderRadius: BorderRadius.circular(16),
      color: C.paper,
    ),
    alignment: Alignment.centerLeft,
    child: child,
  );

  Widget _pills(List<String> opts, String sel, ValueChanged<String> onPick, {double height = 44}) => Container(
    height: height,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(color: C.wash, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: opts.length > 2 ? MainAxisSize.max : MainAxisSize.min,
      children: [
        for (final o in opts)
          () {
            final pill = tap(
              o,
              () => onPick(o),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: o == sel ? C.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(o, style: mono(14, color: o == sel ? C.paper : C.ink)),
              ),
              selected: o == sel,
            );
            return opts.length > 2 ? Expanded(child: pill) : pill;
          }(),
      ],
    ),
  );
}

/// A finished run: the track and your laps, or your route if it was off the track.
CustomPainter entrySketch(Map<String, dynamic> e, {bool ruler = true}) {
  final pts = [for (final q in e['pts'] as List? ?? []) q == null ? null : Pt.fromJson(q as List)];
  if (e['route'] == true) return RoutePainter(RouteShape(pts, aspect: ruler ? 1.1 : 1.6), dot: false, ruler: ruler);
  final sh = e['shape'] as List?;
  return SketchPainter(
    sh == null ? Oval.lane(e['lane'] as int? ?? 1) : Oval((sh[0] as num).toDouble(), (sh[1] as num).toDouble()),
    pts,
  );
}

/* ---------- one run: every lap ---------- */

Widget _cols(List<Widget> c, {double v = 9}) => Container(
  padding: EdgeInsets.symmetric(vertical: v, horizontal: 4),
  decoration: const BoxDecoration(
    border: Border(bottom: BorderSide(color: C.rule)),
  ),
  child: Row(
    children: [
      SizedBox(width: 40, child: c[0]),
      SizedBox(width: 52, child: c[1]),
      Expanded(child: c[2]),
      SizedBox(width: 44, child: c[3]),
      SizedBox(width: 68, child: c[4]),
    ],
  ),
);

Widget _lapRow(String n, String split, double? bar, String top, String total, {bool best = false, bool stop = false}) =>
    _cols([
      Text(n, style: mono(14)),
      Text(split, style: mono(14, weight: best ? 500 : 400)),
      stop
          ? const CustomPaint(size: Size(double.infinity, 1), painter: DashPainter())
          : bar == null
          ? const SizedBox()
          : Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: bar,
                child: Container(height: best ? 2 : 1, color: best ? C.you : C.lead.withValues(alpha: 0.85)),
              ),
            ),
      Text(top, textAlign: TextAlign.right, style: mono(14)),
      Text(total, textAlign: TextAlign.right, style: mono(14)),
    ]);

class RunPage extends StatelessWidget {
  final Map<String, dynamic> entry;
  const RunPage({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final laps = [for (final x in e['laps'] as List? ?? []) (x as num).toInt()];
    final lapTop = [for (final x in e['lapTop'] as List? ?? []) (x as num).toDouble()];
    final lapM = (e['L'] as num?)?.toDouble() ?? laneLength(e['lane'] as int? ?? 1);
    double mph(int ms) => lapM / (ms / 1000) * mpsToMph;
    final fastest = laps.isEmpty ? null : laps.reduce(math.min), slowest = laps.isEmpty ? null : laps.reduce(math.max);
    final avg = laps.isEmpty ? null : laps.reduce((a, b) => a + b) / laps.length;
    final top = e['top'] as num?;
    // stops and stretches off the track, in order (off first when both start at once)
    final breaks = [
      for (final o in e['off'] as List? ?? [])
        ((o[0] as num).toInt(), 0, _lapRow('off', hms(o[1] as num), null, '', miles(o[2] as num), stop: true)),
      for (final p in e['pauses'] as List? ?? [])
        ((p[0] as num).toInt(), 1, _lapRow('stop', hms(p[1] as num), null, '', '', stop: true)),
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    final rows = <Widget>[];
    var cum = 0, bi = 0;
    void until(num end) {
      while (bi < breaks.length && breaks[bi].$1 < end) {
        rows.add(breaks[bi++].$3);
      }
    }

    for (final (i, ms) in laps.indexed) {
      until(cum + ms);
      cum += ms;
      rows.add(
        _lapRow(
          '${i + 1}',
          hms(ms),
          slowest! > fastest! ? 0.35 + 0.65 * (ms - fastest) / (slowest - fastest) : 1.0,
          i < lapTop.length && lapTop[i] > 0 ? f1(lapTop[i]) : '',
          hms(cum),
          best: ms == fastest,
        ),
      );
    }
    until(double.infinity);
    final tail = (e['tail'] as num? ?? 0).toInt(), tailFrac = (e['tailFrac'] as num? ?? 0).toDouble();
    if (tail > 5000 && tailFrac > 0) rows.add(_lapRow('+$tailFrac', hms(tail), null, '', hms(e['el'] as num)));

    return page(
      tap(
        'Back',
        () => Navigator.of(context).pop(),
        const SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: CustomPaint(size: Size(22, 22), painter: BackIcon()),
          ),
        ),
      ),
      link('done', () => Navigator.of(context).popUntil((r) => r.isFirst)),
      [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(whenOf(e['id'] as int, long: true), style: mono(13)),
        ),
        const SizedBox(height: 14),
        AspectRatio(
          aspectRatio: e['route'] == true ? 1.3 : trackAspect,
          child: CustomPaint(painter: entrySketch(e)),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: card,
          child: Wrap(
            runSpacing: 18,
            children: [
              for (final (k, v) in [
                ('distance', miles(e['metres'] as num)),
                ('time', hms(e['el'] as num)),
                ('laps', '${e['n']}'),
                ('avg lap', hms(avg)),
                ('mph', f1(e['mph'] as num?)),
                ('fastest', top == null ? '—' : '${f1(top)} mph'),
                ('best lap', hms(fastest)),
                ('lane', '${e['lane'] ?? 1}'),
              ])
                FractionallySizedBox(
                  widthFactor: 1 / 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v, style: mono(21, weight: 300)),
                      const SizedBox(height: 5),
                      Text(k, style: mono(12)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (laps.isNotEmpty) ...[
          label('mph per lap'),
          Semantics(
            container: true,
            label: 'mph per lap',
            value: 'best lap ${f1(mph(fastest!))} mph${top == null ? '' : ', peak ${f1(top)} mph'}',
            child: SizedBox(
              height: 150,
              child: CustomPaint(
                size: Size.infinite,
                painter: SpeedChart([for (final ms in laps) mph(ms)], lapTop, top?.toDouble()),
              ),
            ),
          ),
        ],
        label('every lap'),
        _cols([
          for (final (i, t) in ['lap', 'split', '', 'top', 'total'].indexed)
            Text(t, textAlign: i > 2 ? TextAlign.right : null, style: mono(11)),
        ], v: 6),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('no full laps', style: mono(13)),
          ),
        ...rows,
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: Confirm('delete run', () {
            Store.saveHistory(Store.history().where((x) => x['id'] != e['id']).toList());
            Navigator.of(context).pop(true);
          }, pad: const EdgeInsets.symmetric(vertical: 10, horizontal: 4)),
        ),
      ],
    );
  }
}
