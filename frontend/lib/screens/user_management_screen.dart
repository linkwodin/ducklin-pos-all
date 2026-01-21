import 'package:flutter/material.dart';

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_alt, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text(
            'User Management Page',
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

