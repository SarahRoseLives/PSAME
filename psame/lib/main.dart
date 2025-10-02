// lib/main.dart

import 'package:flutter/material.dart';
import 'ui/transmitter_page.dart';

Future<void> main() async {
  // Ensures the Flutter binding is initialized before any platform channel calls.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HackRF FM Transmitter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const TransmitterPage(),
    );
  }
}