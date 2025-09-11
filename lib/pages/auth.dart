// lib/pages/auth.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import 'home_page.dart';

void main() {
  runApp(const AuthPage());
}

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Operator Login',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final ApiService api = ApiService();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _showPassword = false;
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _error = 'Please enter email and password';
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter email and password')));
      return;
    }

    bool parseBool(dynamic v) {
      if (v == null) return false;
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v.toString().trim().toLowerCase();
      return s == 'true' || s == '1' || s == 'yes';
    }


    try {
      // Call ApiService.login (ApiService has internal prints if instrumented)
      print('auth.dart -> attempting login for: $email');
      final result = await api.login(email, password);
      print('auth.dart -> login result: $result');

      if (result['ok'] == true) {
        final data = result['data'] ?? {};

        // Save non-sensitive user metadata in SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        final String name = data['name'] ?? data['username'] ?? '';
        final String userId = data['userId']?.toString() ?? data['id']?.toString() ?? '';
        final String userEmail = data['email'] ?? email;
        final String role = data['role'] ?? '';
        //final bool isActive = (data['isActive'] == true) || (data['isActive']?.toString().toLowerCase() == 'true');
        final dynamic rawActive = data['isActive'];
        final bool isActive = rawActive == true ||
            rawActive == 1 ||
            rawActive?.toString().trim().toLowerCase() == 'true' ||
            rawActive?.toString().trim() == '1';

        print('\n\n\n isActive = ');
        print(isActive);
        print('\n\n\n');
        print('LOGIN RAW isActive: ${data['isActive']} (type: ${data['isActive']?.runtimeType})');
        print('\n\n\n');


        final String loginTimeIso = DateTime.now().toIso8601String();

        if (userId.isNotEmpty) await prefs.setString('user_id', userId);
        if (name.isNotEmpty) await prefs.setString('user_name', name);
        if (userEmail.isNotEmpty) await prefs.setString('user_email', userEmail);
        if (role.isNotEmpty) await prefs.setString('user_role', role);
        await prefs.setBool('user_is_active', isActive);
        await prefs.setString('user_login_time', loginTimeIso);


        // If ApiService saved JWT on login, it's already stored securely.

        if (!mounted) return;
        // Open the provided home_page.dart and pass the user details
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => HomePage(
              userName: name.isNotEmpty ? name : 'Operator',
              userEmail: userEmail,
              role: role,
              isActive: parseBool(data['isActive']),
              loginTime: DateTime.parse(loginTimeIso),
            ),
          ),
        );
      } else {
        final msg = result['message'] ?? 'Login failed';
        setState(() {
          _error = msg;
        });

        // Provide immediate user feedback
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $msg')));
        }
      }
    } catch (e) {
      print('auth.dart -> unexpected exception in _signIn: $e');
      setState(() {
        _error = 'Unexpected error: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unexpected error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Widget _buildLoginCard(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 400,
        child: Card(
          elevation: 5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'Operator Login',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.indigo),
                ),
                const SizedBox(height: 30),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Email', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                const SizedBox(height: 8),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    hintText: 'akshaya@toll.com',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                  ),
                ),
                const SizedBox(height: 20),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Password', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    hintText: 'operator123',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Checkbox(
                      value: _showPassword,
                      onChanged: (bool? value) {
                        setState(() {
                          _showPassword = value ?? false;
                        });
                      },
                    ),
                    const Text('Show Password'),
                  ],
                ),
                const SizedBox(height: 10),
                if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _signIn,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      backgroundColor: Colors.indigo[800],
                    ),
                    child: _loading
                        ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                    )
                        : const Text(
                      'Sign In',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo[50],
      body: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  // Replace with your asset or remove if not present
                  Image.asset('assets/india_gov.png', height: 50, errorBuilder: (c, o, s) => const SizedBox()),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Government of India', style: TextStyle(fontSize: 12, color: Colors.black54)),
                      Text('MINISTRY OF ROAD TRANSPORT & HIGHWAYS',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo)),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
            _buildLoginCard(context),
          ],
        ),
      ),
    );
  }
}
