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

/// A wrapper that constrains the app to mobile dimensions on web/desktop
class ResponsiveWrapper extends StatelessWidget {
  final Widget child;
  
  // Maximum width for the mobile-like view
  static const double maxMobileWidth = 450.0;
  
  const ResponsiveWrapper({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Get the screen size
    final screenSize = MediaQuery.of(context).size;
    final isWideScreen = screenSize.width > maxMobileWidth;
    
    // If not a wide screen (mobile), just return the child directly
    if (!isWideScreen) {
      return child;
    }
    
    // For wide screens (web/desktop), center the app in a phone-like container
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e), // Dark background
      body: Center(
        child: Container(
          width: maxMobileWidth,
          height: screenSize.height,
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
            // Optional: Add rounded corners for a device-like look
            borderRadius: screenSize.height < 900 
                ? null // Full height on smaller screens
                : const BorderRadius.vertical(
                    top: Radius.circular(20),
                    bottom: Radius.circular(20),
                  ),
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}
