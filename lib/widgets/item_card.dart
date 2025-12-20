import 'package:flutter/material.dart';
import '../models/game_item.dart';

class ItemCard extends StatelessWidget {
  final GameItem item;
  final VoidCallback onTap;
  final bool isRevealed;

  const ItemCard({
    Key? key,
    required this.item,
    required this.onTap,
    this.isRevealed = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: item.isSelected ? const Color(0xFF5A5A5A) : const Color(0xFFEFEFEF),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            if (!item.isSelected && !isRevealed)
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            // Glowing effect for revealed items
            if (isRevealed)
              BoxShadow(
                color: Colors.amber.withOpacity(0.6),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            if (isRevealed)
              BoxShadow(
                color: Colors.amber.withOpacity(0.3),
                blurRadius: 20,
                spreadRadius: 4,
              ),
          ],
          border: item.isSelected
              ? Border.all(color: Colors.white, width: 2)
              : isRevealed
                  ? Border.all(color: Colors.amber, width: 3)
                  : null,
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Image.asset(
                item.imagePath,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.image_not_supported, size: 40, color: Colors.grey);
                },
              ),
            ),
            // Sparkle indicator for revealed items
            if (isRevealed)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.star,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
