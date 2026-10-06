import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/entity.dart';
import '../services/media.dart';
import 'tile_card.dart';

/// The coloured bar a solved group turns into: the group's name, and under it the
/// four pictures as thumbnails, centred and sized to the bar. The first child cannot read yet, so the things
/// are shown, not listed, and tapping a thumbnail says its name. Only a board with no
/// pictures at all falls back to the names as text.
const double thumbnailGap = 8;

/// How large each thumbnail of a solved group is. It fills the bar's width, shared
/// between the pictures, unless that would be taller than the screen can spare: four
/// solved bars must fit one above another under the heading, with room to scroll less.
double thumbnailSize(double barWidth, double screenHeight, int count) {
  final byWidth = (barWidth - thumbnailGap * (count - 1)) / count;
  final byHeight = (screenHeight - 230) / 4 - 56; // 230: headings and buttons; 56: a bar's name and padding
  final size = byWidth < byHeight ? byWidth : byHeight;
  return size.clamp(40.0, 160.0);
}

class SolvedGroupBar extends StatelessWidget {
  final String label;
  final List<Entity> items;
  final EntityMedia Function(Entity) mediaFor;
  final Color color;
  final void Function(Entity) onSay;
  final VoidCallback? onDescend;

  const SolvedGroupBar({
    super.key,
    required this.label,
    required this.items,
    required this.mediaFor,
    required this.color,
    required this.onSay,
    this.onDescend,
  });

  @override
  Widget build(BuildContext context) {
    final pictured = items.every((e) => mediaFor(e).hasPicture);
    return GestureDetector(
      onTap: onDescend,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.35), blurRadius: 8, offset: const Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: GoogleFonts.quicksand(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: Colors.white,
                        letterSpacing: 0.5),
                  ),
                ),
                if (onDescend != null) _digDeeper(),
              ],
            ),
            const SizedBox(height: 8),
            if (pictured)
              // Centred, and as large as the bar allows: the width is shared between the
              // four, and the height is what a screen can spare when all four groups are
              // solved and their bars stand one above another.
              LayoutBuilder(
                builder: (context, bar) {
                  final size = thumbnailSize(bar.maxWidth, MediaQuery.of(context).size.height, items.length);
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (int i = 0; i < items.length; i++) ...[
                        if (i > 0) const SizedBox(width: thumbnailGap),
                        SizedBox(width: size, height: size, child: _thumbnail(items[i])),
                      ],
                    ],
                  );
                },
              )
            else
              Text(
                items.map((e) => e.label).join('  ·  '),
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withOpacity(0.92)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Widget _thumbnail(Entity e) {
    return Semantics(
      button: true,
      label: e.label,
      child: GestureDetector(
        key: ValueKey('solved-${e.id}'),
        onTap: () => onSay(e),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: TilePicture(media: mediaFor(e)),
        ),
      ),
    );
  }

  Widget _digDeeper() {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.22),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Dig deeper',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          SizedBox(width: 4),
          Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 16),
        ],
      ),
    );
  }
}
