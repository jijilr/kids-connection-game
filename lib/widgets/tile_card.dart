import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/entity.dart';
import '../services/media.dart';

const _purple = Color(0xFF6C5CE7);
const _ink = Color(0xFF2D3436);

/// One animal tile: a photo or emoji with the name underneath (or just the name,
/// big, when there's no picture). Same card DNA as the original picture game —
/// rounded, springy, purple when selected.
class TileCard extends StatelessWidget {
  final Entity entity;
  final EntityMedia media;
  final bool selected;
  final VoidCallback onTap;

  const TileCard({
    super.key,
    required this.entity,
    required this.media,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: entity.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 0.93 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? _purple : Colors.grey.withOpacity(0.18),
                width: selected ? 3 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: selected
                      ? _purple.withOpacity(0.35)
                      : Colors.black.withOpacity(0.07),
                  blurRadius: selected ? 12 : 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  media.hasPicture ? _pictureWithName() : _nameOnly(),
                  if (selected)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: _purple,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_rounded,
                            size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pictureWithName() {
    return Column(
      children: [
        Expanded(child: _picture()),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          color: selected ? _purple : const Color(0xFFF4F2FD),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              entity.label,
              maxLines: 1,
              style: GoogleFonts.quicksand(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: selected ? Colors.white : _ink,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _picture() {
    final art = media.art;
    if (art != null) {
      // Drawn on white with its own margin, so it is shown whole rather than cropped.
      return Padding(
        padding: const EdgeInsets.all(2),
        child: Image.asset(
          art,
          fit: BoxFit.contain,
          width: double.infinity,
          errorBuilder: (_, __, ___) => _emojiOr(),
        ),
      );
    }
    final image = media.image;
    if (image != null) {
      return Image.asset(
        image,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => _emojiOr(),
      );
    }
    return _emojiOr();
  }

  Widget _emojiOr() {
    final emoji = media.emoji;
    if (emoji == null) return const SizedBox.shrink();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: FittedBox(
          child: Text(emoji, style: const TextStyle(fontSize: 44)),
        ),
      ),
    );
  }

  Widget _nameOnly() {
    return Container(
      color: selected ? _purple.withOpacity(0.08) : null,
      padding: const EdgeInsets.all(6),
      alignment: Alignment.center,
      child: Text(
        entity.label,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.quicksand(
          fontWeight: FontWeight.w800,
          fontSize: 14,
          height: 1.1,
          color: selected ? _purple : _ink,
        ),
      ),
    );
  }
}
