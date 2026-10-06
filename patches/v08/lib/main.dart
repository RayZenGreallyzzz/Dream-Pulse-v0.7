import 'package:flutter/material.dart';

import 'ui/assistant_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DreamPulseApp());
}

class DreamPulseApp extends StatelessWidget {
  const DreamPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF8E7CFF);
    const cyan = Color(0xFF23D5E7);
    const surface = Color(0xFF11131A);
    const border = Color(0xFF2C3140);

    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
      surface: surface,
    ).copyWith(
      primary: accent,
      secondary: cyan,
      surface: surface,
    );

    final sharp = RoundedRectangleBorder(
      borderRadius: BorderRadius.zero,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Dream Pulse',
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF090B10),
        dividerColor: border,
        splashFactory: InkRipple.splashFactory,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          backgroundColor: Color(0xFF0C0E14),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: const BorderSide(color: border),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: sharp,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: sharp,
            side: const BorderSide(color: border),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(shape: sharp),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(shape: sharp),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0F1219),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: const BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: const BorderSide(color: border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: const BorderSide(color: accent, width: 1.2),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          side: const BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          selectedColor: const Color(0xFF262344),
          backgroundColor: const Color(0xFF10131A),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFF0D1016),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF0D1016),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ),
      home: const AssistantShell(),
    );
  }
}
