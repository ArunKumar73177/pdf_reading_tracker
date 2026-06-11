import 'package:flutter/material.dart';

import 'screens/pdf_selection_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PdfReadingTrackerExampleApp());
}

class PdfReadingTrackerExampleApp extends StatelessWidget {
  const PdfReadingTrackerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Reading Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      // Landing screen is now the selection screen, not the reader directly.
      home: const PdfSelectionScreen(),
    );
  }
}