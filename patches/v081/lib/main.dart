import 'package:flutter/material.dart';

import 'ui/launch_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DreamPulseApp());
}

class DreamPulseApp extends StatelessWidget {
  const DreamPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFFF6A16);
    const surface = Color(0xFF0C0F14);
    final scheme = const ColorScheme.dark(
      primary: accent,
      secondary: Color(0xFFFF9A52),
      surface: surface,
      error: Color(0xFFFF695E),
    );

    final square = RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
      side: const BorderSide(color: Color(0xFF3A414C)),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dream Pulse',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF07090D),
        colorScheme: scheme,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF090C11),
          foregroundColor: Color(0xFFF4F4F5),
          elevation: 0,
          centerTitle: false,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: square,
            backgroundColor: accent,
            foregroundColor: Colors.black,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: square,
            side: const BorderSide(color: Color(0xFF6E3B21)),
            foregroundColor: const Color(0xFFFFA267),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF0E1117),
          border: OutlineInputBorder(borderRadius: BorderRadius.zero),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: Color(0xFF343A45)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: accent, width: 1.2),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: square,
          backgroundColor: const Color(0xFF10131A),
          selectedColor: const Color(0xFF3A2013),
          side: const BorderSide(color: Color(0xFF353B46)),
        ),
        cardTheme: CardThemeData(
          color: surface,
          shape: square,
          elevation: 0,
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF090C11),
          indicatorColor: const Color(0xFF3A2013),
          indicatorShape: square,
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 11, letterSpacing: 0.4),
          ),
        ),
      ),
      home: const LaunchGate(),
    );
  }
}
