import 'package:flutter/material.dart';

import 'app_info.dart';
import 'pages/daily_log_page.dart';

void main() {
  runApp(const DayforgeApp());
}

class DayforgeApp extends StatelessWidget {
  const DayforgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF376A5A);

    return MaterialApp(
      title: appTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          surface: const Color(0xFFF6F7F5),
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F7F5),
        useMaterial3: true,
      ),
      home: const DailyLogPage(),
    );
  }
}
