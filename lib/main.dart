import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: DeviceMeshApp()));
}

class DeviceMeshApp extends StatelessWidget {
  const DeviceMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeviceMesh',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF080B14),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF45E6FF),
          secondary: Color(0xFF9B7BFF),
          surface: Color(0xFF0E1422),
        ),
      ),
      home: const Scaffold(
        body: Center(
          child: Text(
            'DeviceMesh\nMany Devices. One Intelligence.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}