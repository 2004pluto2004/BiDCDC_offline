import 'package:flutter/material.dart';

import 'domain/bidcdc_controller.dart';
import 'features/dashboard/dashboard_page.dart';

void main() {
  runApp(const BidcdcApp());
}

class BidcdcApp extends StatefulWidget {
  const BidcdcApp({super.key});

  @override
  State<BidcdcApp> createState() => _BidcdcAppState();
}

class _BidcdcAppState extends State<BidcdcApp> {
  final controller = BidcdcController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiDCDC Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff1687ff),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xff020814),
        useMaterial3: true,
      ),
      home: DashboardPage(controller: controller),
    );
  }
}
