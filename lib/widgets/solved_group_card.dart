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
    // Parse color hex string to Color
    Color groupColor = Color(int.parse(group.colorHex));
    
    // Get screen width for responsive sizing
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Responsive sizes
    final titleFontSize = (screenWidth * 0.035).clamp(12.0, 18.0);
    final itemsFontSize = (screenWidth * 0.028).clamp(10.0, 14.0);
    final imageSize = (screenWidth * 0.1).clamp(30.0, 60.0);
    final padding = (screenWidth * 0.03).clamp(8.0, 16.0);
    final spacing = (screenWidth * 0.015).clamp(4.0, 12.0);
    final imageSpacing = (screenWidth * 0.008).clamp(2.0, 6.0);

    return FadeInDown(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: spacing),
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: groupColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Category name
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  group.displayName.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    fontSize: titleFontSize,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: spacing * 0.3),
              // Item names
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  group.items.map((i) => i.name.toUpperCase()).join(', '),
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w500,
                    fontSize: itemsFontSize,
                    color: Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: spacing),
              // Item images in a responsive row
              Wrap(
                alignment: WrapAlignment.center,
                spacing: imageSpacing,
                runSpacing: imageSpacing,
                children: group.items.map((item) {
                  return Container(
                    width: imageSize,
                    height: imageSize,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: EdgeInsets.all(imageSize * 0.08),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Image.asset(
                        item.imagePath,
                        errorBuilder: (context, error, stackTrace) => 
                            const Icon(Icons.image_not_supported, color: Colors.black54),
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
