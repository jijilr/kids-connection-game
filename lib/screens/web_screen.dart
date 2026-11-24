import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/engine_provider.dart';
import '../services/file_saver.dart';
import '../widgets/tile_card.dart';

const _ink = Color(0xFF2D3436);
const _amber = Color(0xFFFFC107);
const _leaf = Color(0xFF2E9E5B); // the end of a branch
const _edge = Color(0xFFFCE9F1); // the page, and the rim of the picture
const _branchColors = [
  Color(0xFF6C5CE7),
  Color(0xFF138A7C),
  Color(0xFFD08A1E),
  Color(0xFFC24E70),
  Color(0xFF2E86C1),
  Color(0xFF7D6608),
];

/// The web of what he has found so far (asked for by the owner on 24 Nov 2026; the
/// "mastery web" of his June design, "threads of light"). The first set is in the middle.
/// Every group he has found is a picture joined by a glowing thread to the set it was
/// found in, and what he found inside it grows outward from there. A picture is larger
/// the more often he has found the group, and its ring is whole when every find was
/// clean, partial otherwise. A small arrow marks the lines the app will follow next.
/// Nothing he has not met is shown: the web only grows.
///
/// "Your web grew": the knots he has not been shown before light up one by one when the
/// web opens. Faint rings count the steps from the middle, and one line for the grown-up
/// gives the owner's two measures: breadth (how many ends the web has) and depth (how
/// many steps to an end, on average and at the deepest). The button at the top saves
/// the web as a large picture, to print for the wall.
class WebScreen extends StatefulWidget {
  const WebScreen({super.key, this.thenNext = false});

  /// Opened by the game itself between two sets: one big button leads on.
  final bool thenNext;

  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> with TickerProviderStateMixin {
  late final AnimationController _grow; // the new knots coming in
  late final AnimationController _alive; // sparks along the threads, a soft glow that breathes
  late final List<String> _fresh; // the new knots, in the order they light up
  final _picture = GlobalKey();

  @override
  void initState() {
    super.initState();
    final g = context.read<EngineProvider>();
    _fresh = g.newKnots;
    _grow = AnimationController(
        vsync: this, duration: Duration(milliseconds: 600 + 450 * min(_fresh.length, 14)));
    _alive = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
    if (_fresh.isNotEmpty) _grow.forward();
    // he is being shown them now; the lighting up goes on from the list taken above
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) g.markWebSeen();
    });
  }

  @override
  void dispose() {
    _grow.dispose();
    _alive.dispose();
    super.dispose();
  }

  /// How far a knot has come in: 0 not yet, 1 there. A new knot springs in at its turn.
  double _in(String id) {
    final i = _fresh.indexOf(id);
    if (i < 0 || _fresh.isEmpty) return 1;
    final n = _fresh.length;
    final from = i / (n + 1), to = min(1.0, (i + 2) / (n + 1));
    return Interval(from, to, curve: Curves.elasticOut).transform(_grow.value);
  }

  /// The web as one large picture, for printing: about 3,000 dots across.
  Future<void> _save() async {
    final say = ScaffoldMessenger.of(context);
    try {
      final boundary = _picture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: (3000 / boundary.size.width).clamp(1.5, 4.0));
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final day = DateTime.now();
      final name = 'his_web_${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}.png';
      final saved = png != null && saveBytesFile(name, png.buffer.asUint8List(), 'image/png');
      say
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text(saved ? 'Saved as $name.' : 'This device cannot save a picture here.')));
    } catch (_) {
      say.showSnackBar(const SnackBar(content: Text('The picture could not be made.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodes = context.watch<EngineProvider>().web;
    final measure = measureWeb(nodes);
    return Scaffold(
      backgroundColor: _edge,
      appBar: AppBar(
        backgroundColor: const Color(0xFF6C5CE7),
        foregroundColor: Colors.white,
        toolbarHeight: 48,
        title: Text('What he has found',
            style: GoogleFonts.quicksand(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
        actions: [
          if (nodes.length > 1)
            IconButton(
              key: const ValueKey('web-save'),
              tooltip: 'Save it as a picture, to print',
              icon: const Icon(Icons.download_rounded),
              onPressed: _save,
            ),
        ],
      ),
      body: nodes.length <= 1
          ? Center(
              child: Text('Nothing found yet. When a group is found, it appears here.',
                  key: const ValueKey('web-empty'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 15, color: Colors.grey.shade700)),
            )
          : LayoutBuilder(builder: (context, box) {
              final layout = WebLayout(nodes, max(700.0, min(box.maxWidth, box.maxHeight)));
              return Column(
                children: [
                  if (_fresh.isNotEmpty) _grew(),
                  Expanded(
                    child: _WholeAtFirst(
                      side: layout.side,
                      child: RepaintBoundary(
                        key: _picture,
                        child: Container(
                          width: layout.side,
                          height: layout.side,
                          decoration: const BoxDecoration(
                            gradient: RadialGradient(
                              colors: [Color(0xFFFFFDF4), Color(0xFFFFF4DC), _edge],
                              stops: [0.0, 0.6, 1.0],
                            ),
                          ),
                          child: Stack(
                            children: [
                              // the rings, the threads of light and the glow behind each knot
                              Positioned.fill(
                                child: CustomPaint(
                                    painter: _Sky(layout, _in, Listenable.merge([_grow, _alive]), _alive)),
                              ),
                              AnimatedBuilder(
                                animation: _grow,
                                builder: (context, _) => Stack(children: [for (final n in nodes) _node(n, layout)]),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 16,
                                child: Text(_caption(measure),
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.quicksand(
                                        fontSize: 13, fontWeight: FontWeight.w700, color: _ink.withValues(alpha: 0.45))),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.thenNext)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ElevatedButton.icon(
                        key: const ValueKey('web-next'),
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text('Next'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _ink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                        ),
                      ),
                    ),
                  _measures(measure),
                  _legend(nodes),
                ],
              );
            }),
    );
  }

  /// The line at the foot of the picture, so that a printed web says what it is and when.
  String _caption(WebMeasure m) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final day = DateTime.now();
    return 'His web on ${day.day} ${months[day.month - 1]} ${day.year}   ·   '
        'breadth ${m.ends}   ·   depth ${m.averageDepth.toStringAsFixed(1)}, deepest ${m.deepest}';
  }

  /// "Your web grew", with how many new knots.
  Widget _grew() {
    return Container(
      key: const ValueKey('web-grew'),
      width: double.infinity,
      color: _amber.withValues(alpha: 0.28),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome_rounded, size: 20, color: Color(0xFFB4791A)),
          const SizedBox(width: 8),
          Flexible(
            child: Text('Your web grew: ${_fresh.length} new',
                textAlign: TextAlign.center,
                style: GoogleFonts.quicksand(fontWeight: FontWeight.w800, fontSize: 17, color: _ink)),
          ),
        ],
      ),
    );
  }

  /// The owner's two measures, for the grown-up.
  Widget _measures(WebMeasure m) {
    final steps = m.averageDepth.toStringAsFixed(1);
    return Container(
      key: const ValueKey('web-measure'),
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
      child: Column(
        children: [
          Text.rich(
            TextSpan(style: GoogleFonts.inter(fontSize: 13.5, color: _ink), children: [
              const TextSpan(text: 'Breadth: ', style: TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: '${m.ends} ${m.ends == 1 ? 'end' : 'ends'}'),
              const TextSpan(text: '     Depth: ', style: TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: '$steps steps on average, deepest ${m.deepest}'),
            ]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            'A step is one of this game\'s own questions. The numbers show how his web grows, not how much he knows.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 10.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _node(WebNode n, WebLayout layout) {
    final at = layout.at[n.id]!;
    final size = layout.sizeOf(n);
    final color = layout.colorOf(n);
    final t = _in(n.id);
    return Positioned(
      key: ValueKey('web-${n.id}'),
      left: at.dx - 85,
      top: at.dy - size / 2,
      width: 170,
      child: Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: t,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: n.isStart
                    ? 'Where the game begins'
                    : '${n.label}: found ${n.found} ${n.found == 1 ? 'time' : 'times'}, ${n.clean} of them clean'
                        '${n.end ? '. Nothing lies below it: the end of this branch' : ''}'
                        '${n.between.isEmpty ? '' : '. These have no single answer: they lie between the groups they are tied to'}'
                        '${n.also.isEmpty ? '' : '. More than one road leads here: it lies in each circle it is tied to'}',
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // the picture on a white disc, lifted a little off the page
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 12, offset: const Offset(0, 4)),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(size * 0.11),
                        child: ClipOval(
                          child: n.picture == null
                              ? Center(
                                  child: Icon(n.isStart ? Icons.star_rounded : Icons.circle,
                                      size: size * (n.isStart ? 0.56 : 0.22), color: n.isStart ? _amber : color))
                              : TilePicture(media: n.picture!),
                        ),
                      ),
                      // the ring: whole when every find was clean, a part of it otherwise
                      Positioned.fill(
                        child: CustomPaint(
                            painter: _Ring(color, n.isStart ? 1 : (n.found == 0 ? 0 : n.clean / n.found),
                                width: max(4.0, size * 0.07))),
                      ),
                      if (n.line)
                        Positioned(
                          right: -3,
                          top: -3,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: _amber,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: const Icon(Icons.arrow_forward_rounded, size: 13, color: _ink),
                          ),
                        ),
                      // a leaf: the end of a branch, nothing lies below
                      if (n.end)
                        Positioned(
                          key: ValueKey('web-end-${n.id}'),
                          left: -3,
                          top: -3,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: _leaf, width: 2),
                            ),
                            child: const Icon(Icons.eco_rounded, size: 13, color: _leaf),
                          ),
                        ),
                      if (n.found > 1)
                        Positioned(
                          right: -4,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Text('×${n.found}',
                                style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.white)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 5, offset: const Offset(0, 1))],
                ),
                child: Text(n.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.quicksand(
                        fontSize: n.isStart ? 16 : 14, height: 1.15, fontWeight: FontWeight.w800, color: _ink)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legend(List<WebNode> nodes) {
    Widget item(Widget mark, String text) => Text.rich(
          TextSpan(children: [
            WidgetSpan(alignment: PlaceholderAlignment.middle, child: mark),
            TextSpan(text: '  $text'),
          ]),
          style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade800),
        );
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Wrap(
        spacing: 18,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          item(const Icon(Icons.circle, size: 15, color: Color(0xFF6C5CE7)), 'bigger, and ×n: found more often'),
          item(const SizedBox(width: 16, height: 16, child: CustomPaint(painter: _Ring(Color(0xFF138A7C), 0.6, width: 3))),
              'whole ring: every find was clean'),
          item(
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: _amber, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_rounded, size: 11, color: _ink),
              ),
              'the app follows this next'),
          if (nodes.any((n) => n.end))
            item(const Icon(Icons.eco_rounded, size: 15, color: _leaf), 'a leaf: the end of a branch, nothing lies below'),
          if (nodes.any((n) => n.between.isNotEmpty))
            item(const Icon(Icons.more_horiz_rounded, size: 17, color: Colors.grey),
                'dotted threads: in between, tied to both sides'),
          if (nodes.any((n) => n.also.isNotEmpty))
            item(const Icon(Icons.more_horiz_rounded, size: 17, color: Colors.grey),
                'dotted threads: it lies in that circle too'),
          item(const Icon(Icons.radio_button_unchecked, size: 15, color: Colors.grey), 'faint rings: steps from the middle'),
          item(const Icon(Icons.pinch_rounded, size: 15, color: Colors.grey), 'pinch or scroll to zoom, drag to move'),
        ],
      ),
    );
  }
}

/// Shows the whole web, in the middle of the screen, when it opens; after that he may
/// zoom and move it as he likes.
class _WholeAtFirst extends StatefulWidget {
  const _WholeAtFirst({required this.side, required this.child});
  final double side;
  final Widget child;

  @override
  State<_WholeAtFirst> createState() => _WholeAtFirstState();
}

class _WholeAtFirstState extends State<_WholeAtFirst> {
  TransformationController? _view;
  double? _fittedFor;

  @override
  void dispose() {
    _view?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (_view == null || _fittedFor != widget.side) {
        // the web grew (or this is the first look): fit it again
        final scale = min(1.0, min(box.maxWidth, box.maxHeight) / widget.side);
        final matrix = Matrix4.identity()
          ..translateByDouble(
              (box.maxWidth - widget.side * scale) / 2, (box.maxHeight - widget.side * scale) / 2, 0, 1)
          ..scaleByDouble(scale, scale, 1, 1);
        _view?.dispose();
        _view = TransformationController(matrix);
        _fittedFor = widget.side;
      }
      return InteractiveViewer(
        transformationController: _view,
        constrained: false,
        minScale: 0.2,
        maxScale: 4,
        boundaryMargin: const EdgeInsets.all(500),
        child: widget.child,
      );
    });
  }
}

/// Where each knot of the web stands: the first set in the middle, each group on a ring
/// one step further out, inside the slice of the circle that belongs to its parent. A
/// ring lies far enough out that the knots on it have room beside one another.
class WebLayout {
  WebLayout(this.nodes, double least) {
    final children = <String, List<WebNode>>{};
    for (final n in nodes) {
      if (n.parent != null) children.putIfAbsent(n.parent!, () => []).add(n);
    }
    int leaves(String id) {
      final kids = children[id] ?? const [];
      return kids.isEmpty ? 1 : kids.map((k) => leaves(k.id)).reduce((a, b) => a + b);
    }

    // A group with much found inside it gets a wider slice, but not so wide that its
    // neighbours are squeezed onto one another.
    double share(String id) => 1 + 0.6 * (leaves(id) - 1);

    final start = nodes.firstWhere((n) => n.isStart);
    final span = <String, double>{};
    void slice(String id, double from, double to, int depth) {
      final kids = children[id] ?? const [];
      final all = kids.fold(0.0, (sum, k) => sum + share(k.id));
      var angle = from;
      for (int i = 0; i < kids.length; i++) {
        final k = kids[i];
        final width = (to - from) * share(k.id) / all;
        span[k.id] = width;
        angleOf[k.id] = angle + width / 2;
        step[k.id] = depth;
        branch[k.id] = depth == 1 ? i : branch[id]!;
        slice(k.id, angle, angle + width, depth + 1);
        angle += width;
      }
    }

    step[start.id] = 0;
    branch[start.id] = 0;
    slice(start.id, -pi / 2, 3 * pi / 2, 1);
    rings = step.values.fold(0, max);

    // each ring: at least a fixed stride beyond the one before, and further if its most
    // crowded knot would otherwise touch its neighbour
    _radius = [0];
    for (int d = 1; d <= rings; d++) {
      final tightest = [for (final e in step.entries) if (e.value == d) span[e.key]!].fold(2 * pi, min);
      final needed = _room / tightest;
      _radius.add(max(_radius[d - 1] + _stride, min(needed, _radius[d - 1] + 3 * _stride)));
    }
    side = max(least, 2 * (_radius.last + 150));
    centre = Offset(side / 2, side / 2);
    for (final n in nodes) {
      at[n.id] = n.isStart
          ? centre
          : centre + Offset(cos(angleOf[n.id]!), sin(angleOf[n.id]!)) * _radius[step[n.id]!];
    }
  }

  static const _stride = 190.0; // from one ring to the next, at least
  static const _room = 150.0; // along a ring, from one knot to the next, at least

  final List<WebNode> nodes;
  late final double side;
  late final Offset centre;

  /// How many rings the web has: one for each step from the middle.
  late final int rings;
  late final List<double> _radius;
  final at = <String, Offset>{};
  final angleOf = <String, double>{};
  final step = <String, int>{};
  final branch = <String, int>{};
  late final Map<String, WebNode> byId = {for (final n in nodes) n.id: n};

  double radiusOf(int ring) => _radius[ring];

  /// Larger the nearer the middle, and the more often he has found it (up to five finds).
  double sizeOf(WebNode n) {
    if (n.isStart) return 118;
    final base = switch (step[n.id] ?? 1) { 1 => 96.0, 2 => 82.0, _ => 72.0 };
    return base + 5.0 * min(n.found, 5);
  }

  Color colorOf(WebNode n) => n.isStart ? _amber : _branchColors[(branch[n.id] ?? 0) % _branchColors.length];
}

/// Behind the knots: the faint rings, the threads of light with a spark running along
/// each, and a soft glow under every knot that breathes slowly.
class _Sky extends CustomPainter {
  _Sky(this.layout, this.shown, Listenable repaint, this.alive) : super(repaint: repaint);
  final WebLayout layout;
  final double Function(String id) shown;
  final Animation<double> alive;

  @override
  void paint(Canvas canvas, Size size) {
    final beat = alive.value;
    // faint rings: one for each step from the middle, with its number
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _ink.withValues(alpha: 0.07);
    for (int ring = 1; ring <= layout.rings; ring++) {
      final radius = layout.radiusOf(ring);
      canvas.drawCircle(layout.centre, radius, faint);
      final label = TextPainter(
        text: TextSpan(
            text: ring == 1 ? '1 step' : '$ring steps',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: _ink.withValues(alpha: 0.30))),
        textDirection: TextDirection.ltr,
      )..layout();
      // just inside the ring, a little past its lowest point, where few knots stand
      const angle = pi / 2 + 0.12;
      label.paint(canvas,
          layout.centre + Offset(cos(angle), sin(angle)) * (radius - 5) - Offset(label.width, label.height));
    }

    // threads of light: each bends toward its knot, glows, and carries one small spark
    int i = 0;
    for (final n in layout.nodes) {
      i++;
      final from = layout.at[n.parent], to = layout.at[n.id];
      if (from == null || to == null) continue;
      final t = shown(n.id).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final color = layout.colorOf(n);
      final inner = layout.radiusOf((layout.step[n.id] ?? 1) - 1), outer = layout.radiusOf(layout.step[n.id] ?? 1);
      final angle = layout.angleOf[n.id] ?? 0;
      final bend = layout.centre + Offset(cos(angle), sin(angle)) * ((inner + outer) / 2);
      final whole = Path()
        ..moveTo(from.dx, from.dy)
        ..quadraticBezierTo(bend.dx, bend.dy, to.dx, to.dy);
      final metric = whole.computeMetrics().first;
      final path = t >= 1 ? whole : metric.extractPath(0, metric.length * t);
      final weight = 2.4 + min(n.found, 5) * 0.5;
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = weight + 9
            ..color = color.withValues(alpha: 0.13)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = weight
            ..color = color.withValues(alpha: 0.62));
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: 0.6));
      if (t >= 1) {
        final where = metric.getTangentForOffset(metric.length * ((beat + i * 0.137) % 1.0))?.position;
        if (where != null) {
          canvas.drawCircle(where, 5.5,
              Paint()..color = Colors.white.withValues(alpha: 0.55)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
          canvas.drawCircle(where, 2.2, Paint()..color = Colors.white);
        }
      }
    }

    // Dotted threads, each in the colour of the knot it reaches: from "in between" to the
    // groups it lies between, and from a place where circles cross to the other places it
    // lies inside. Such a knot is a bridge between branches.
    for (final n in layout.nodes) {
      final from = layout.at[n.id];
      final t = shown(n.id).clamp(0.0, 1.0);
      if (from == null || t <= 0) continue;
      for (final side in [...n.between, ...n.also]) {
        final to = layout.at[side];
        final other = layout.byId[side];
        if (to == null || other == null) continue;
        // bent a little toward the middle, so it does not lie on the ring
        final half = Offset.lerp(from, to, 0.5)!;
        final bend = Offset.lerp(half, layout.centre, 0.35)!;
        final whole = Path()
          ..moveTo(from.dx, from.dy)
          ..quadraticBezierTo(bend.dx, bend.dy, to.dx, to.dy);
        final metric = whole.computeMetrics().first;
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.6
          ..color = layout.colorOf(other).withValues(alpha: 0.55 * t);
        for (double d = 0; d < metric.length * t; d += 11) {
          canvas.drawPath(metric.extractPath(d, min(d + 1.5, metric.length)), paint);
        }
      }
    }

    // a soft glow under every knot, breathing slowly; brighter under one that has just come in
    i = 0;
    for (final n in layout.nodes) {
      i++;
      final at = layout.at[n.id];
      final t = shown(n.id).clamp(0.0, 1.3);
      if (at == null || t <= 0) continue;
      final breath = 0.5 + 0.5 * sin(2 * pi * (beat + i * 0.21));
      final arriving = t < 1.0 ? 1.0 : 0.0;
      canvas.drawCircle(
          at,
          layout.sizeOf(n) / 2 + 10 + 4 * breath + 10 * arriving,
          Paint()
            ..color = (arriving > 0 ? _amber : layout.colorOf(n)).withValues(alpha: 0.16 + 0.07 * breath + 0.35 * arriving)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    }
  }

  @override
  bool shouldRepaint(_Sky old) => old.layout != layout;
}

class _Ring extends CustomPainter {
  const _Ring(this.color, this.share, {this.width = 4});
  final Color color;
  final double share; // of the finds that were clean, 0 to 1
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final box = (Offset.zero & size).deflate(width / 2);
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color.withValues(alpha: 0.22);
    final full = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(box, 0, 2 * pi, false, faint);
    if (share > 0) canvas.drawArc(box, -pi / 2, 2 * pi * share.clamp(0.0, 1.0), false, full);
  }

  @override
  bool shouldRepaint(_Ring old) => old.color != color || old.share != share || old.width != width;
}

/// A small round picture of his own web, as it stands: the way into the web for a child,
/// who cannot read a button's name (the owner's word of 24 Nov 2026). It is drawn from
/// the same places as the web itself, so he sees his own shape grow, arm by arm.
class WebMiniature extends StatelessWidget {
  const WebMiniature({super.key, required this.nodes, this.size = 58});
  final List<WebNode> nodes;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(colors: [Color(0xFFFFFDF4), Color(0xFFFFF0D2), _edge], stops: [0, 0.6, 1]),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [BoxShadow(color: _ink.withValues(alpha: 0.22), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: ClipOval(child: CustomPaint(painter: _MiniWeb(nodes))),
    );
  }
}

class _MiniWeb extends CustomPainter {
  _MiniWeb(this.nodes);
  final List<WebNode> nodes;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.center(Offset.zero);
    if (nodes.length <= 1) {
      canvas.drawCircle(middle, size.width * 0.13, Paint()..color = _amber);
      return;
    }
    final layout = WebLayout(nodes, 700);
    // the whole web inside the round, with a little air at the rim
    final outermost = nodes.map((n) => (layout.at[n.id]! - layout.centre).distance).fold(1.0, max);
    final scale = size.width * 0.42 / outermost;
    Offset place(String id) => middle + (layout.at[id]! - layout.centre) * scale;
    for (final n in nodes) {
      if (n.parent == null) continue;
      canvas.drawLine(
          place(n.parent!),
          place(n.id),
          Paint()
            ..color = layout.colorOf(n).withValues(alpha: 0.75)
            ..strokeWidth = 1.4
            ..strokeCap = StrokeCap.round);
    }
    for (final n in nodes) {
      final step = layout.step[n.id] ?? 0;
      canvas.drawCircle(place(n.id), n.isStart ? 4.6 : max(1.8, 3.4 - 0.6 * step), Paint()..color = layout.colorOf(n));
    }
  }

  @override
  bool shouldRepaint(_MiniWeb old) => old.nodes.length != nodes.length;
}
