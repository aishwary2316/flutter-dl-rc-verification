// profile.dart
import 'package:flutter/material.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    const Color _primaryBlue = Color(0xFF1E3A8A);
    const Color _textGray = Color(0xFF64748B);
    const Color _lightGray = Color(0xFFF8FAFC);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile'), backgroundColor: _primaryBlue),
      body: Container(
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
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(Icons.person, size: 64, color: _primaryBlue),
                    const SizedBox(height: 16),
                    const Text('Profile', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text('This page is under development', style: TextStyle(fontSize: 14, color: Color(0xFF64748B))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
