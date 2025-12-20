import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'providers/game_provider.dart';
import 'screens/game_screen.dart';

void main() {
  runApp(const ConnectionsGameApp());
}

class ConnectionsGameApp extends StatelessWidget {
  const ConnectionsGameApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GameProvider()),
      ],
      child: MaterialApp(
        title: 'Connections Game',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          textTheme: GoogleFonts.interTextTheme(),
          useMaterial3: true,
        ),
        home: const ResponsiveWrapper(child: GameScreen()),
      ),
    );
  }
}

/// A smart wrapper that adapts to different screen sizes
/// - Mobile: Full screen
/// - Tablet: Centered with max width
/// - Desktop/Web: Centered with max width and decorations
class ResponsiveWrapper extends StatelessWidget {
  final Widget child;
  
  // Breakpoints
  static const double mobileMaxWidth = 600.0;
  static const double tabletMaxWidth = 900.0;
  static const double contentMaxWidth = 500.0; // Max width for game content
  
  const ResponsiveWrapper({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;
        
        // Mobile: Use full width
        if (screenWidth <= mobileMaxWidth) {
          return child;
        }
        
        // Tablet/Desktop: Center with max width
        // Calculate optimal width based on screen size
        double optimalWidth = contentMaxWidth;
        
        // On very wide screens, allow slightly wider
        if (screenWidth > tabletMaxWidth) {
          optimalWidth = (screenWidth * 0.4).clamp(contentMaxWidth, 600.0);
        }
        
        // Landscape mode on tablets: use more space
        if (screenWidth > screenHeight && screenWidth <= tabletMaxWidth) {
          optimalWidth = (screenWidth * 0.6).clamp(400.0, 600.0);
        }
        
        return Scaffold(
          backgroundColor: const Color(0xFF1a1a2e), // Dark background
          body: Center(
            child: Container(
              width: optimalWidth,
              constraints: BoxConstraints(
                maxHeight: screenHeight,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
                // Rounded corners on larger screens
                borderRadius: screenHeight > 700 
                    ? const BorderRadius.vertical(
                        top: Radius.circular(20),
                        bottom: Radius.circular(20),
                      )
                    : null,
              ),
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
