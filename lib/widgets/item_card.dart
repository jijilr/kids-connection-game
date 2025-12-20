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
    // Fun colors for selected state
    final selectedGradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF6C5CE7), Color(0xFFA29BFE)],
    );
    
    final normalGradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Colors.white, Color(0xFFF8F9FA)],
    );
    
    final revealedGradient = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFFE66D), Color(0xFFFFD93D)],
    );

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        transform: item.isSelected 
            ? (Matrix4.identity()..scale(0.95))
            : Matrix4.identity(),
        decoration: BoxDecoration(
          gradient: item.isSelected 
              ? selectedGradient 
              : isRevealed 
                  ? revealedGradient 
                  : normalGradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: item.isSelected 
                  ? const Color(0xFF6C5CE7).withOpacity(0.4)
                  : isRevealed
                      ? const Color(0xFFFFD93D).withOpacity(0.5)
                      : Colors.black.withOpacity(0.08),
              blurRadius: item.isSelected || isRevealed ? 12 : 6,
              offset: const Offset(0, 4),
              spreadRadius: item.isSelected || isRevealed ? 2 : 0,
            ),
          ],
          border: Border.all(
            color: item.isSelected 
                ? Colors.white.withOpacity(0.5)
                : isRevealed
                    ? const Color(0xFFFF9F43)
                    : Colors.grey.withOpacity(0.1),
            width: item.isSelected || isRevealed ? 3 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image with nice padding
              Padding(
                padding: const EdgeInsets.all(8),
                child: Image.asset(
                  item.imagePath,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Icon(
                        Icons.image_not_supported_rounded,
                        size: 32,
                        color: Colors.grey.shade400,
                      ),
                    );
                  },
                ),
              ),
              // Sparkle overlay for revealed items
              if (isRevealed)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B6B),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6B6B).withOpacity(0.5),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              // Selection checkmark
              if (item.isSelected)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Color(0xFF6C5CE7),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
