import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'providers/engine_provider.dart';
import 'screens/engine_screen.dart';
import 'services/progress.dart';

void main() {
  runApp(const ConnectionsGameApp());
}

// Fun, child-friendly color palette
class AppColors {
  // Primary gradient colors
  static const Color primaryPink = Color(0xFFFF6B9D);
  static const Color primaryPurple = Color(0xFF9B6DFF);
  static const Color primaryBlue = Color(0xFF4ECDC4);
  static const Color primaryYellow = Color(0xFFFFE66D);
  static const Color primaryOrange = Color(0xFFFF8C42);
  
  // Background colors
  static const Color backgroundStart = Color(0xFFE8F5FF);
  static const Color backgroundEnd = Color(0xFFFFF0F5);
  
  // Card colors
  static const Color cardBackground = Colors.white;
  static const Color cardSelected = Color(0xFF6C5CE7);
  
  // Text colors
  static const Color textPrimary = Color(0xFF2D3436);
  static const Color textLight = Colors.white;
  
  // Playful gradients
  static const LinearGradient funGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryPink, primaryPurple, primaryBlue],
  );
  
  static const LinearGradient sunshineGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF9E6), Color(0xFFFFE8F0)],
  );
}

class ConnectionsGameApp extends StatelessWidget {
  const ConnectionsGameApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => EngineProvider(progressStore: DeviceProgressStore())..init()),
      ],
      child: MaterialApp(
        title: 'Connections Game',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primaryColor: AppColors.primaryPurple,
          scaffoldBackgroundColor: AppColors.backgroundStart,
          textTheme: GoogleFonts.quicksandTextTheme().apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          ),
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.primaryPurple,
            brightness: Brightness.light,
          ),
        ),
        home: const ResponsiveWrapper(child: EngineScreen()),
      ),
    );
  }
}

/// A smart wrapper that adapts to different screen sizes with fun styling
class ResponsiveWrapper extends StatelessWidget {
  final Widget child;
  
  static const double mobileMaxWidth = 600.0;
  static const double contentMaxWidth = 480.0;
  
  const ResponsiveWrapper({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;
        
        // Mobile: Use full width with gradient background
        if (screenWidth <= mobileMaxWidth) {
          return Container(
            decoration: const BoxDecoration(
              gradient: AppColors.sunshineGradient,
            ),
            child: child,
          );
        }
        
        // Larger screens: Center with playful frame
        double optimalWidth = contentMaxWidth;
        if (screenWidth > 900) {
          optimalWidth = (screenWidth * 0.4).clamp(contentMaxWidth, 550.0);
        }
        
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF667eea),
                Color(0xFF764ba2),
                Color(0xFFf093fb),
              ],
            ),
          ),
          child: Center(
            child: Container(
              width: optimalWidth,
              constraints: BoxConstraints(maxHeight: screenHeight * 0.95),
              margin: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                gradient: AppColors.sunshineGradient,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
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
