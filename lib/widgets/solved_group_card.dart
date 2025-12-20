import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:animate_do/animate_do.dart';
import '../models/game_item.dart';

class SolvedGroupCard extends StatelessWidget {
  final GameGroup group;
  final VoidCallback? onTap;

  const SolvedGroupCard({Key? key, required this.group, this.onTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color groupColor = Color(int.parse(group.colorHex));
    
    // Create a lighter version for gradient
    Color lightColor = Color.lerp(groupColor, Colors.white, 0.3)!;
    
    final screenWidth = MediaQuery.of(context).size.width;
    final titleFontSize = (screenWidth * 0.04).clamp(14.0, 18.0);
    final itemsFontSize = (screenWidth * 0.028).clamp(10.0, 13.0);
    final imageSize = (screenWidth * 0.1).clamp(35.0, 50.0);
    final padding = (screenWidth * 0.03).clamp(10.0, 16.0);

    return BounceInDown(
      duration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 8),
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [lightColor, groupColor],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: groupColor.withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Category name with fun styling
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      group.displayName.toUpperCase(),
                      style: GoogleFonts.quicksand(
                        fontWeight: FontWeight.w800,
                        fontSize: titleFontSize,
                        color: Colors.white,
                        letterSpacing: 1.2,
                        shadows: [
                          Shadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(1, 1),
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.star, color: Colors.white, size: 18),
                ],
              ),
              const SizedBox(height: 4),
              // Item names
              Text(
                group.items.map((i) => i.name).join(' • '),
                style: GoogleFonts.quicksand(
                  fontWeight: FontWeight.w600,
                  fontSize: itemsFontSize,
                  color: Colors.white.withOpacity(0.9),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              // Item images in cute bubbles
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: group.items.map((item) {
                  return Container(
                    width: imageSize,
                    height: imageSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        item.imagePath,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => 
                            const Icon(Icons.image, color: Colors.grey),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
