// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  // === Set this correctly for your environment ===
  // Android emulator: http://10.0.2.2:3000
  // iOS simulator: http://localhost:3000
  // Real device: http://<PC_LAN_IP>:3000
  //static const String backendBaseUrl = 'http://10.0.2.2:3000';
  static const String backendBaseUrl = 'https://ai-tollgate-surveillance-1.onrender.com';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // Token helpers
  Future<void> saveToken(String token) => _secureStorage.write(key: 'jwt', value: token);
  Future<String?> getToken() => _secureStorage.read(key: 'jwt');
  Future<void> deleteToken() => _secureStorage.delete(key: 'jwt');

  Map<String, String> _jsonHeaders({String? token}) {
    final headers = {'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  // LOGIN -> server may return token (preferred). If server doesn't return token, we still return data.
  // Future<Map<String, dynamic>> login(String email, String password) async {
  //   final uri = Uri.parse('$backendBaseUrl/login');
  //   try {
  //     final resp = await http
  //         .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'email': email, 'password': password}))
  //         .timeout(const Duration(seconds: 15));
  //
  //     final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
  //     if (resp.statusCode == 200) {
  //       if (body['token'] != null) await saveToken(body['token']);
  //       return {'ok': true, 'data': body};
  //     } else {
  //       return {'ok': false, 'message': body['message'] ?? 'Login failed (${resp.statusCode})'};
  //     }
  //   } catch (e) {
  //     return {'ok': false, 'message': 'Network error: $e'};
  //   }
  // }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final uri = Uri.parse('$backendBaseUrl/login');
    try {
      print('ApiService.login -> POST $uri with email=$email');
      final resp = await http
          .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({'email': email, 'password': password}))
          .timeout(const Duration(seconds: 15));

      print('ApiService.login -> statusCode: ${resp.statusCode}');
      print('ApiService.login -> raw body: ${resp.body}');

      dynamic bodyParsed;
      try {
        bodyParsed = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      } catch (jsonErr) {
        print('ApiService.login -> JSON decode failed: $jsonErr');
        return {
          'ok': false,
          'message': 'Server returned non-JSON response (status ${resp.statusCode}). Response body: ${resp.body}'
        };
      }

      if (resp.statusCode == 200) {
        if (bodyParsed is Map && bodyParsed['token'] != null) await saveToken(bodyParsed['token']);
        return {'ok': true, 'data': bodyParsed};
      } else {
        final msg = (bodyParsed is Map && bodyParsed['message'] != null) ? bodyParsed['message'] : 'Login failed (${resp.statusCode})';
        return {'ok': false, 'message': msg, 'status': resp.statusCode, 'raw': resp.body};
      }
    } catch (e) {
      print('ApiService.login -> exception: $e');
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }












  // Example protected GET using token
  Future<Map<String, dynamic>> getLogs() async {
    final token = await getToken();
    final uri = Uri.parse('$backendBaseUrl/api/logs');
    try {
      final resp = await http.get(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        return {'ok': true, 'data': jsonDecode(resp.body)};
      } else if (resp.statusCode == 401) {
        return {'ok': false, 'message': 'Unauthorized', 'status': 401};
      } else {
        return {'ok': false, 'message': 'Failed to fetch logs (${resp.statusCode})'};
      }
    } catch (e) {
      return {'ok': false, 'message': 'Network error: $e'};
    }
  }

  // Multipart upload to /api/verify (driverImage)
  Future<Map<String, dynamic>> verifyDriver({
    String? dlNumber,
    String? rcNumber,
    String? location,
    String? tollgate,
    required File driverImage,
  }) async {
    final token = await getToken();
    final uri = Uri.parse('$backendBaseUrl/api/verify');
    final request = http.MultipartRequest('POST', uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';

    request.fields['dl_number'] = dlNumber ?? '';
    request.fields['rc_number'] = rcNumber ?? '';
    request.fields['location'] = location ?? '';
    request.fields['tollgate'] = tollgate ?? '';

    request.files.add(await http.MultipartFile.fromPath('driverImage', driverImage.path, filename: driverImage.path.split(Platform.pathSeparator).last));

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 40));
      final resp = await http.Response.fromStream(streamed);
      final body = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      if (resp.statusCode == 200) return {'ok': true, 'data': body};
      return {'ok': false, 'message': body['message'] ?? 'Verify failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {'ok': false, 'message': 'Network/upload error: $e'};
    }
  }

  // Logout: delete token and optionally call server logout route
  Future<void> localLogout() => deleteToken();
}

