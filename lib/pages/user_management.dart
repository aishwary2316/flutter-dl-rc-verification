// user_management.dart
import 'package:flutter/material.dart';

class UserManagementPage extends StatelessWidget {
  const UserManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    const Color _primaryBlue = Color(0xFF1E3A8A);
    const Color _textGray = Color(0xFF64748B);
    const Color _lightGray = Color(0xFFF8FAFC);

    return Container(
      color: _lightGray,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                children: const [
                  Icon(Icons.group, size: 64, color: _primaryBlue),
                  SizedBox(height: 16),
                  Text(
                    'User Management',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _primaryBlue),
                  ),
                  SizedBox(height: 8),
                  Text('This page is under development', style: TextStyle(fontSize: 14, color: _textGray)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
