import 'package:flutter/material.dart';

import '../features/mesh/presentation/debug_connection_screen.dart';
import 'theme/app_theme.dart';

class DeviceMeshApp extends StatelessWidget {
  const DeviceMeshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeviceMesh',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const DebugConnectionScreen(),
    );
  }
}