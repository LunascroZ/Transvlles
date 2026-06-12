import 'package:flutter/material.dart';
import 'screens/homepage.dart';

void main() {
  runApp(const TransvilleApp());
}

class TransvilleApp extends StatelessWidget {
  const TransvilleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transville',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32), // vert "ville verte"
        ),
      ),
      home: const MapPage(),
    );
  }
}
