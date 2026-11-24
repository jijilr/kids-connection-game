import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/engine_provider.dart';
import '../widgets/tile_card.dart';

const _ink = Color(0xFF2D3436);
const _branchColors = [
  Color(0xFF6C5CE7),
  Color(0xFF138A7C),
  Color(0xFFB4791A),
  Color(0xFFC24E70),
  Color(0xFF2E86C1),
  Color(0xFF7D6608),
];

/// The web of what he has found so far (asked for by the owner on 24 Nov 2026; the
/// "mastery web" of his June design). The first set is in the middle. Every group he has
/// found is a picture joined to the set it was found in, and what he found inside it
/// grows outward from there. A picture is larger the more often he has found the group,
/// and its ring is whole when every find was clean, partial otherwise. A small arrow
/// marks the lines the app will follow next. Nothing he has not met is shown: the web
/// only grows.
class WebScreen extends StatelessWidget {
  const WebScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final nodes = context.watch<EngineProvider>().web;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF6C5CE7),
        foregroundColor: Colors.white,
        toolbarHeight: 48,
        title: Text('What he has found',
            style: GoogleFonts.quicksand(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white)),
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
                  Expanded(
                    child: _WholeAtFirst(
                      side: layout.side,
                      child: SizedBox(
                        width: layout.side,
                        height: layout.side,
                        child: Stack(
                          children: [
                            Positioned.fill(child: CustomPaint(painter: _Threads(layout))),
                            for (final n in nodes) _node(n, layout),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _legend(),
                ],
              );
            }),
    );
  }

  Widget _node(WebNode n, WebLayout layout) {
    final at = layout.at[n.id]!;
    final size = layout.sizeOf(n);
    final color = layout.colorOf(n);
    return Positioned(
      key: ValueKey('web-${n.id}'),
      left: at.dx - 60,
      top: at.dy - size / 2,
      width: 120,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // the ring: whole when every find was clean, a part of it otherwise
                Positioned.fill(
                  child: CustomPaint(painter: _Ring(color, n.found == 0 ? 0 : n.clean / n.found)),
                ),
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: ClipOval(
                    child: Container(
                      color: Colors.white,
                      child: n.picture == null
                          ? Center(
                              child: Text(n.isStart ? '★' : '•',
                                  style: TextStyle(fontSize: size / 2.6, color: color)))
                          : TilePicture(media: n.picture!),
                    ),
                  ),
                ),
                if (n.line)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: Color(0xFFFFC107), shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_forward_rounded, size: 13, color: _ink),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(n.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 11, height: 1.15, fontWeight: FontWeight.w700, color: _ink)),
          if (n.found > 0)
            Text('found ${n.found}, clean ${n.clean}',
                style: GoogleFonts.inter(fontSize: 9.5, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _legend() {
    Widget item(Widget mark, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          mark,
          const SizedBox(width: 5),
          Text(text, style: GoogleFonts.inter(fontSize: 11.5, color: Colors.grey.shade800)),
        ]);
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Wrap(
        spacing: 18,
        runSpacing: 6,
        alignment: WrapAlignment.center,
        children: [
          item(const Icon(Icons.circle, size: 15, color: Color(0xFF6C5CE7)), 'bigger: found more often'),
          item(const SizedBox(width: 16, height: 16, child: CustomPaint(painter: _Ring(Color(0xFF138A7C), 0.6))),
              'whole ring: every find was clean'),
          item(
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Color(0xFFFFC107), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_rounded, size: 11, color: _ink),
              ),
              'the app follows this next'),
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
        minScale: 0.3,
        maxScale: 3,
        boundaryMargin: const EdgeInsets.all(400),
        child: widget.child,
      );
    });
  }
}

/// Where each node of the web stands: the first set in the middle, each group on a ring
/// one step further out, inside the slice of the circle that belongs to its parent.
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

    int depthOf(String id) => 1 + (children[id] ?? const []).fold(0, (m, k) => max(m, depthOf(k.id)));
    final start = nodes.firstWhere((n) => n.isStart);
    final rings = depthOf(start.id) - 1;
    // room for the pictures: a ring is wide enough for its most crowded slice
    side = max(least, 2 * (rings * 150.0 + 90));
    final ring = (side / 2 - 80) / max(1, rings);
    final centre = Offset(side / 2, side / 2);
    at[start.id] = centre;
    branch[start.id] = 0;

    // A group with much found inside it gets a wider slice, but not so wide that its
    // neighbours are squeezed onto one another.
    double share(String id) => 1 + 0.6 * (leaves(id) - 1);

    void place(String id, double from, double to, int depth) {
      final kids = children[id] ?? const [];
      final all = kids.fold(0.0, (sum, k) => sum + share(k.id));
      var angle = from;
      for (int i = 0; i < kids.length; i++) {
        final k = kids[i];
        final span = (to - from) * share(k.id) / all;
        final mid = angle + span / 2;
        at[k.id] = centre + Offset(cos(mid), sin(mid)) * (ring * depth);
        branch[k.id] = depth == 1 ? i : branch[id]!;
        place(k.id, angle, angle + span, depth + 1);
        angle += span;
      }
    }

    place(start.id, -pi / 2, 3 * pi / 2, 1);
  }

  final List<WebNode> nodes;
  late final double side;
  final at = <String, Offset>{};
  final branch = <String, int>{};

  /// Larger the more often he has found it, up to six finds.
  double sizeOf(WebNode n) => n.isStart ? 76 : 46 + 6.0 * min(n.found, 6);

  Color colorOf(WebNode n) => n.isStart ? _ink : _branchColors[(branch[n.id] ?? 0) % _branchColors.length];
}

class _Threads extends CustomPainter {
  _Threads(this.layout);
  final WebLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    for (final n in layout.nodes) {
      final from = layout.at[n.parent], to = layout.at[n.id];
      if (from == null || to == null) continue;
      canvas.drawLine(
          from,
          to,
          Paint()
            ..color = layout.colorOf(n).withValues(alpha: 0.45)
            ..strokeWidth = 2 + min(n.found, 6) * 0.5
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_Threads old) => old.layout != layout;
}

class _Ring extends CustomPainter {
  const _Ring(this.color, this.share);
  final Color color;
  final double share; // of the finds that were clean, 0 to 1

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = color.withValues(alpha: 0.22);
    final full = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(box.deflate(2), 0, 2 * pi, false, faint);
    if (share > 0) canvas.drawArc(box.deflate(2), -pi / 2, 2 * pi * share.clamp(0.0, 1.0), false, full);
  }

  @override
  bool shouldRepaint(_Ring old) => old.color != color || old.share != share;
}
