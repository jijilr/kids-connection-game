import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/entity.dart';

/// A text tile — same card DNA as the picture game (rounded, springy, purple when
/// selected), but showing the entity's name instead of an image (BUILD_PLAN P1).
class TileCard extends StatelessWidget {
  final Entity entity;
  final bool selected;
  final VoidCallback onTap;

  const TileCard({
    super.key,
    required this.entity,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        transform:
            selected ? (Matrix4.identity()..scale(0.96)) : Matrix4.identity(),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: selected
                ? const [Color(0xFF6C5CE7), Color(0xFFA29BFE)]
                : const [Colors.white, Color(0xFFF8F9FA)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? Colors.white.withOpacity(0.6)
                : Colors.grey.withOpacity(0.15),
            width: selected ? 2.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? const Color(0xFF6C5CE7).withOpacity(0.35)
                  : Colors.black.withOpacity(0.06),
              blurRadius: selected ? 12 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(6),
        child: Center(
          child: Text(
            entity.name,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.quicksand(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              height: 1.05,
              color: selected ? Colors.white : const Color(0xFF2D3436),
            ),
          ),
        ),
      ),
    );
  }
}
