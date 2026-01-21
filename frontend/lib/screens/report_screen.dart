import 'package:flutter/material.dart';

class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dashboard, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'Report Page',
            style: TextStyle(fontSize: 24),
          ),
          SizedBox(height: 8),
          Text(
            'Coming soon...',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

