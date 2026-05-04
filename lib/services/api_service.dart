// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'hash_service.dart';
import '../utils/safe_log.dart';
import '../utils/safe_error.dart';

class ApiService {
  // === Set this correctly for your environment ===
  static const String backendBaseUrl = 'https://api2.aishtrex.com';

  final HashService _hasher = HashService();

  // ---------------------------------------------------------
  // SECURITY FIX: Vulnerability #2 (Insecure Encryption Mode)
  // ---------------------------------------------------------
  // This forces Android to use AES-GCM (EncryptedSharedPreferences).
  // NOTE: This will effectively "logout" existing users once, as old keys become unreadable.
  AndroidOptions _getAndroidOptions() => const AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
  );

  late final FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: _getAndroidOptions(),
  );

  // New Keys for Session Management
  static const String _kLoginTime = 'login_timestamp';
  static const String _kLastActive = 'last_active_timestamp';

  // Constants for api.aishtrex.com - Vehicle details api
  static const String _aishTokenKey = 'aish_token';
  static const String _aishTokenExpiry = 'aish_token_expiry';

  static const String _aishTokenUrl = 'https://api.aishtrex.com/proxy-api';
  static const String _aishVehicleUrl = 'https://api2.aishtrex.com/api/getRCDetails';

  static const String _aishApiKey = 'testing';
  static const String _clientId = 'NagalandPolice';

  // Aishtrex token helper (internal)
  Future<String?> _getAishToken() async {
    try {
      final storedToken = await _secureStorage.read(key: _aishTokenKey);
      final expiryStr = await _secureStorage.read(key: _aishTokenExpiry);

      if (storedToken != null && expiryStr != null) {
        final expiry = DateTime.tryParse(expiryStr);
        if (expiry != null && DateTime.now().isBefore(expiry)) {
          return storedToken;
        }
      }

      final uri = Uri.parse(_aishTokenUrl);

      final resp = await http.post(
        uri,
        headers: {
          'x-api-key': _aishApiKey,
          'Content-Type': 'application/json'
        },
      ).timeout(const Duration(seconds: 15));

      final body = _safeJson(resp.body);

      if (resp.statusCode == 200 && body['access_token'] != null) {
        final token = body['access_token'];

        final expiresIn = body['expires_in'] ?? 3600;

        final expiry =
        DateTime.now().add(Duration(seconds: expiresIn - 60));

        await _secureStorage.write(key: _aishTokenKey, value: token);
        await _secureStorage.write(
            key: _aishTokenExpiry, value: expiry.toIso8601String());

        return token;
      }

      return null;
    } catch (e) {
      devLog("Aishtrex token error: $e");
      return null;
    }
  }

  // single vehicle lookup function
  Future<Map<String, dynamic>> getVehicleDetails(String regNo) async {
    try {
      final aishtoken = await _getAishToken();
      final jwtToken = await getToken();

      if (aishtoken == null) {
        return {
          'ok': false,
          'message': 'Unable to get authorization token'
        };
      }

      if (jwtToken == null || jwtToken.isEmpty) {
        return {
          'ok': false,
          'message': 'User not authenticated (JWT missing)'
        };
      }

      final uri = Uri.parse(_aishVehicleUrl);

      final resp = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'accept': 'application/json',
          //'x-api-key': _aishApiKey,
          'token': 'Bearer $aishtoken',
          'Authorization': 'Bearer $jwtToken'
        },
        body: jsonEncode({
          "regNo": regNo,
          "clientId": _clientId
        }),
      ).timeout(const Duration(seconds: 20));

      final body = _safeJson(resp.body);

      if (resp.statusCode == 200) {
        return {
          'ok': true,
          'data': body,
          'status': resp.statusCode
        };
      }

      if (resp.statusCode == 401) {
        await _secureStorage.delete(key: _aishTokenKey);
        await _secureStorage.delete(key: _aishTokenExpiry);

        return await getVehicleDetails(regNo);
      }

      return {
        'ok': false,
        'message': body['message'] ?? 'Vehicle lookup failed',
        'status': resp.statusCode
      };
    } catch (e) {
      return {
        'ok': false,
        'message': SafeError.format(e,
            fallback: "Vehicle lookup failed due to network issue")
      };
    }
  }



  // Token helpers (do NOT change these — other parts of app rely on them)
  // Future<void> saveToken(String token) => _secureStorage.write(key: 'jwt', value: token);
  Future<String?> getToken() => _secureStorage.read(key: 'jwt');
  // Future<void> deleteToken() => _secureStorage.delete(key: 'jwt');
  Future<void> localLogout() => deleteToken();

  // ---------------------------------------------------------
  // UPDATED TOKEN HELPERS
  // ---------------------------------------------------------

  // When saving token, also save the Login Time and reset Last Active Time
  Future<void> saveToken(String token) async {
    final now = DateTime.now().toIso8601String();
    await _secureStorage.write(key: 'jwt', value: token);
    await _secureStorage.write(key: _kLoginTime, value: now);
    await _secureStorage.write(key: _kLastActive, value: now);
  }


  // When updating activity (e.g., on app pause/resume), save to storage
  Future<void> updateLastActivity() async {
    final now = DateTime.now().toIso8601String();
    await _secureStorage.write(key: _kLastActive, value: now);
  }

  // Helper to retrieve timestamps
  Future<DateTime?> getLoginTimestamp() async {
    final str = await _secureStorage.read(key: _kLoginTime);
    if (str == null) return null;
    return DateTime.tryParse(str);
  }

  Future<DateTime?> getLastActiveTimestamp() async {
    final str = await _secureStorage.read(key: _kLastActive);
    if (str == null) return null;
    return DateTime.tryParse(str);
  }

  Future<void> deleteToken() async {
    await _secureStorage.delete(key: 'jwt');
    await _secureStorage.delete(key: _kLoginTime);
    await _secureStorage.delete(key: _kLastActive);
  }

  Map<String, String> _jsonHeaders({String? token}) {
    final headers = {'Content-Type': 'application/json', 'accept': 'application/json'};
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  // -----------------------------
  // LOGIN (Secure)
  // -----------------------------
  Future<Map<String, dynamic>> login(String email, String password) async {
    final uri = Uri.parse('$backendBaseUrl/login');
    // 1. HASH THE PASSWORD
    final String hashedPassword = _hasher.hashPassword(password);
    devLog ("hashedPassword = $hashedPassword");

    try {
      final payload = {
        'email': email,
        'password': hashedPassword,
      };

      devLog('ApiService.login -> POST $uri with email=$email');
      final resp = await http
          .post(uri, headers: {'Content-Type': 'application/json', 'accept': 'application/json'}, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 30));

      devLog('ApiService.login -> statusCode: ${resp.statusCode}');
      devLog('ApiService.login -> raw body: ${resp.body}');

      dynamic bodyParsed;
      try {
        bodyParsed = resp.body.isNotEmpty ? jsonDecode(resp.body) : {};
      } catch (jsonErr) {
        devLog('ApiService.login -> JSON decode failed: $jsonErr');
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
      devLog('ApiService.login -> exception: $e');
      return {
        'ok': false,
        'message': SafeError.format(e, fallback: "Something went wrong due to a network issue.")
      };
    }
  }

  // -----------------------------
  // Protected GET example
  // -----------------------------
  Future<Map<String, dynamic>> getLogs() async {
    final uri = Uri.parse('$backendBaseUrl/api/logs');
    return _authenticatedGet(uri);
  }

  // Helper to parse JSON safely
  dynamic _safeJson(String? body) {
    if (body == null || body.isEmpty) return {};
    try {
      return jsonDecode(body);
    } catch (_) {
      return {'raw': body};
    }
  }

  // -----------------------------
  // VERIFY (multipart) - improved
  // -----------------------------
        Future<Map<String, dynamic>> verifyDriver({
          String? dlNumber,
          String? rcNumber,
          String? location,
          String? tollgate,
          File? driverImage,
        }) async {
        final token = await getToken();
        final uri = Uri.parse('$backendBaseUrl/api/verify');
    final request = http.MultipartRequest('POST', uri);
    if (token != null && token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';
    request.headers['accept'] = 'application/json';

    if (dlNumber != null && dlNumber.trim().isNotEmpty) request.fields['dl_number'] = dlNumber.trim();
    if (rcNumber != null && rcNumber.trim().isNotEmpty) request.fields['rc_number'] = rcNumber.trim();
    if (location != null && location.trim().isNotEmpty) request.fields['location'] = location.trim();
    if (tollgate != null && tollgate.trim().isNotEmpty) request.fields['tollgate'] = tollgate.trim();

    if (driverImage != null) {
      request.files.add(
        await http.MultipartFile.fromPath(
          'driverImage',
          driverImage.path,
          filename: driverImage.path.split(Platform.pathSeparator).last,
        ),
      );
    }

    try {
      // Increased timeout for robust verification
      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final resp = await http.Response.fromStream(streamed);
      final body = _safeJson(resp.body);

      if (resp.statusCode == 200) return {'ok': true, 'data': body};
      return {'ok': false, 'message': body['message'] ?? 'Verify failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {
        'ok': false,
        'message': SafeError.format(e, fallback: "Network/upload error: Please try again.")
      };
    }
  }

  // -----------------------------
  // OCR endpoints (multipart)
  // -----------------------------


  Future<Map<String, dynamic>> ocrDL(File dlImage) async {
    //final uri = Uri.parse('https://dl-extractor-web-980624091991.us-central1.run.app/extract');
    final uri = Uri.parse('https://ml-model-service-831062770462.us-central1.run.app/extract');
    final request = http.MultipartRequest('POST', uri);
    request.headers['accept'] = 'application/json';

    request.files.add(await http.MultipartFile.fromPath(
        'file',
        dlImage.path,
        filename: dlImage.path.split(Platform.pathSeparator).last
    ));

    devLog("Api Service: Posting to $uri");

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 45));
      final resp = await http.Response.fromStream(streamed);
      final body = _safeJson(resp.body);

      if (resp.statusCode == 200) {
        String extractedData = '';
        if (body['dl_numbers'] is List) {
          extractedData = (body['dl_numbers'] as List).join(', ');
        } else {
          extractedData = body['dl_numbers']?.toString() ?? '';
        }
        return {'ok': true, 'extracted_text': extractedData, 'data': body};
      }
      return {'ok': false, 'message': body['message'] ?? 'OCR DL failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {
        'ok': false,
        'message': SafeError.format(e, fallback: "OCR DL extraction failed due to a network issue.")
      };
    }
  }

  Future<Map<String, dynamic>> ocrRC(File rcImage) async {
    final uri = Uri.parse('$backendBaseUrl/api/ocr/rc');
    final request = http.MultipartRequest('POST', uri);
    final token = await getToken();
    if (token != null && token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';
    request.headers['accept'] = 'application/json';

    request.files.add(await http.MultipartFile.fromPath('rcImage', rcImage.path,
        filename: rcImage.path.split(Platform.pathSeparator).last));

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 45));
      final resp = await http.Response.fromStream(streamed);
      final body = _safeJson(resp.body);
      if (resp.statusCode == 200) {
        return {'ok': true, 'extracted_text': body['extracted_text'], 'data': body};
      }
      return {'ok': false, 'message': body['message'] ?? 'OCR RC failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {
        'ok': false,
        'message': SafeError.format(e, fallback: "OCR RC extraction failed due to a network issue.")
      };
    }
  }

  // -----------------------------
  // Blacklist suspect upload (For Manual Blacklist Entry)
  // -----------------------------
  Future<Map<String, dynamic>> addSuspect({required String name, required File photo}) async {
    final uri = Uri.parse('$backendBaseUrl/api/blacklist/suspect');
    final request = http.MultipartRequest('POST', uri);
    final token = await getToken();
    if (token != null && token.isNotEmpty) request.headers['Authorization'] = 'Bearer $token';
    request.headers['accept'] = 'application/json';

    request.fields['name'] = name;
    request.files.add(await http.MultipartFile.fromPath('photo', photo.path,
        filename: photo.path.split(Platform.pathSeparator).last));

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final resp = await http.Response.fromStream(streamed);
      final body = _safeJson(resp.body);
      if (resp.statusCode == 201) {
        return {'ok': true, 'message': body['message'] ?? 'Suspect added', 'data': body};
      }
      return {'ok': false, 'message': body['message'] ?? 'Add suspect failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {
        'ok': false,
        'message': SafeError.format(e, fallback: "Network/upload error: Please try again")
      };
    }
  }

  // -----------------------------
  // Add to blacklist (JSON body) -> POST /api/blacklist
  // -----------------------------
  Future<Map<String, dynamic>> addToBlacklist(Map<String, dynamic> payload) async {
    final uri = Uri.parse('$backendBaseUrl/api/blacklist');
    final token = await getToken();
    try {
      final resp = await http
          .post(uri, headers: _jsonHeaders(token: token), body: jsonEncode(payload))
          .timeout(const Duration(seconds: 30));
      final body = _safeJson(resp.body);
      if (resp.statusCode == 200) {
        return {'ok': true, 'message': body['message'] ?? 'Added to blacklist', 'data': body};
      }
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {
        'ok': false,
        'message': SafeError.format(e, fallback: "Something went wrong due to a network issue.")
      };
    }
  }

  // -----------------------------
  // Mark blacklist entry as valid -> PUT /api/blacklist/:type/:id
  // -----------------------------
  Future<Map<String, dynamic>> markBlacklistValid({required String type, required String id}) async {
    // final uri = Uri.parse('$backendBaseUrl/api/blacklist/$type/$id');

    final encodedId = Uri.encodeComponent(id);
    final uri = Uri.parse('$backendBaseUrl/api/blacklist/$type/$encodedId');

    final token = await getToken();
    try {
      final resp = await http.put(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      final body = _safeJson(resp.body);
      if (resp.statusCode == 200) return {'ok': true, 'message': body['message'] ?? 'Marked valid', 'data': body};
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {
        'ok': false,
        'message': SafeError.format(e, fallback: "Something went wrong due to a network issue.")
      };
    }
  }

  // -----------------------------
  // Get blacklisted DLs / RCs
  // -----------------------------
  Future<Map<String, dynamic>> getBlacklistedDLs({int page = 1, int limit = 50, String search = ''}) async {
    final uri = Uri.parse(
        '$backendBaseUrl/api/blacklist/dl?page=$page&limit=$limit${search.isNotEmpty ? '&search=${Uri.encodeQueryComponent(search)}' : ''}');
    return _authenticatedGet(uri);
  }

  Future<Map<String, dynamic>> getBlacklistedRCs({int page = 1, int limit = 50, String search = ''}) async {
    final uri = Uri.parse(
        '$backendBaseUrl/api/blacklist/rc?page=$page&limit=$limit${search.isNotEmpty ? '&search=${Uri.encodeQueryComponent(search)}' : ''}');
    return _authenticatedGet(uri);
  }

  // -----------------------------
  // User management
  // -----------------------------
  Future<Map<String, dynamic>> getUsers() async {
    final uri = Uri.parse('$backendBaseUrl/api/users');
    return _authenticatedGet(uri);
  }

  Future<Map<String, dynamic>> addUser({required String name, required String email, required String password, required String role}) async {
    final uri = Uri.parse('$backendBaseUrl/api/users');
    final token = await getToken();
    try {
      final resp = await http
          .post(uri, headers: _jsonHeaders(token: token), body: jsonEncode({'name': name, 'email': email, 'password': password, 'role': role}))
          .timeout(const Duration(seconds: 12));
      final body = _safeJson(resp.body);
      if (resp.statusCode == 201) return {'ok': true, 'userId': body['userId'], 'message': body['message'], 'data': body};
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {
        'ok': false,
        'message': SafeError.format(e, fallback: "Something went wrong due to a network issue.")
      };
    }
  }

  Future<Map<String, dynamic>> deleteUser(String userId) async {
    final uri = Uri.parse('$backendBaseUrl/api/users/$userId');
    final token = await getToken();
    try {
      final resp = await http.delete(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 30));
      final body = _safeJson(resp.body);
      if (resp.statusCode == 200) return {'ok': true, 'message': body['message'] ?? 'Deleted', 'data': body};
      return {'ok': false, 'message': body['message'] ?? 'Failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {
        'ok': false,
        'message': SafeError.format(e, fallback: "Something went wrong due to a network issue.")
      };
    }
  }

  // -----------------------------
  // Server logout
  // -----------------------------
  Future<Map<String, dynamic>> logoutServer(String userId) async {
    final uri = Uri.parse('$backendBaseUrl/api/logout/$userId');
    final token = await getToken();
    try {
      final resp = await http.post(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      final body = _safeJson(resp.body);
      // Always delete token locally even if server fails
      await deleteToken();
      if (resp.statusCode == 200) {
        return {'ok': true, 'message': body['message'] ?? 'Logged out', 'data': body};
      }
      return {'ok': false, 'message': body['message'] ?? 'Failed to logout (${resp.statusCode})', 'body': body};
    } catch (e) {
      await deleteToken();
      return {
        'ok': false,
        'message': SafeError.format(e, fallback: "Something went wrong due to a network issue.")
      };
    }
  }

  // -----------------------------
  // DL usage
  // -----------------------------
  Future<Map<String, dynamic>> getDLUsage(String dlNumber) async {
    final encoded = Uri.encodeComponent(dlNumber);
    final uri = Uri.parse('$backendBaseUrl/api/dl-usage/$encoded');
    return _authenticatedGet(uri);
  }

  // -----------------------------
  // NEW FACE SURVEILLANCE API FUNCTIONS (Secure Middleware)
  // -----------------------------

  // Method to get a list of all suspects
  Future<Map<String, dynamic>> listSuspects({Map<String, String>? faceAuthHeader}) async {
    // New Endpoint: /api/suspects
    final uri = Uri.parse('$backendBaseUrl/api/suspects');
    return _authenticatedGet(uri);
  }

  // Method to verify a face against the suspect list
  Future<Map<String, dynamic>> recognizeFace(String imagePath, {Map<String, String>? faceAuthHeader}) async {
    // New Endpoint: /api/recognize
    final uri = Uri.parse('$backendBaseUrl/api/recognize');
    final token = await getToken();

    final request = http.MultipartRequest('POST', uri);
    request.headers['accept'] = 'application/json';

    // Attach JWT
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    // UPDATED FIELD NAME: 'image'
    request.files.add(await http.MultipartFile.fromPath(
        'image',
        imagePath,
        filename: imagePath.split(Platform.pathSeparator).last
    ));

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 60)); // Increased timeout
      final resp = await http.Response.fromStream(streamed);
      final body = _safeJson(resp.body);

      if (resp.statusCode == 200) {
        return {'ok': true, 'data': body};
      }
      return {'ok': false, 'message': body['message'] ?? 'Recognition failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {
        'ok': false,
        'message': SafeError.format(e, fallback: "Network/upload error: Something went wrong due to a network issue.")
      };
    }
  }

  // Method to add a new person to the suspect list
  Future<Map<String, dynamic>> addSuspectFromFace({required String personName, required String imagePath, Map<String, String>? faceAuthHeader}) async {
    // New Endpoint: /api/suspects/add
    final uri = Uri.parse('$backendBaseUrl/api/suspects/add');
    final token = await getToken();

    final request = http.MultipartRequest('POST', uri);
    request.headers['accept'] = 'application/json';

    // Attach JWT
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.fields['person_name'] = personName;
    request.files.add(await http.MultipartFile.fromPath('file', imagePath,
        filename: imagePath.split(Platform.pathSeparator).last));

    try {
      final streamed = await request.send().timeout(const Duration(seconds: 40));
      final resp = await http.Response.fromStream(streamed);
      final body = _safeJson(resp.body);

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return {'ok': true, 'data': body};
      }
      return {'ok': false, 'message': body['detail'] ?? body['message'] ?? 'Add suspect failed (${resp.statusCode})', 'body': body};
    } catch (e) {
      return {
        'ok': false,
        'message': SafeError.format(e, fallback: "Network/upload error: Something went wrong due to a network issue.")
      };
    }
  }

  // Method to delete a person from the suspect list
  Future<Map<String, dynamic>> deleteSuspectFromFace(String personName, {Map<String, String>? faceAuthHeader}) async {
    // New Endpoint: /api/suspects/delete
    final uri = Uri.parse('$backendBaseUrl/api/suspects/delete');
    final token = await getToken();

    try {
      devLog('ApiService.deleteSuspectFromFace -> POST $uri person_name=$personName');
      final resp = await http.post(
          uri,
          headers: _jsonHeaders(token: token),
          body: jsonEncode({'person_name': personName})
      ).timeout(const Duration(seconds: 40));

      // parse body safely
      final body = _safeJson(resp.body);
      devLog('ApiService.deleteSuspectFromFace -> status ${resp.statusCode} bodyParsed=$body');

      // determine "deleted" deterministically
      bool deleted = false;
      try {
        if (resp.statusCode == 200) {
          deleted = true;
        } else if (body is Map) {
          final statusStr = (body['status'] ?? body['detail'] ?? body['result'] ?? '').toString().toLowerCase();
          if (statusStr.contains('deleted')) deleted = true;
          final dc = body['deleted_count'] ?? body['deleted'];
          if (dc is num && dc.toInt() > 0) deleted = true;
        }
      } catch (e) {
        devLog('ApiService.deleteSuspectFromFace -> parsing error: $e');
      }

      if (deleted) {
        return {
          'ok': true,
          'deleted': deleted,
          'status': resp.statusCode,
          'data': body,
          'raw': resp.body,
        };
      }

      // non-200
      return {
        'ok': false,
        'deleted': false,
        'message': body is Map ? (body['detail'] ?? body['message'] ?? 'Delete suspect failed (${resp.statusCode})') : 'Delete suspect failed (${resp.statusCode})',
        'status': resp.statusCode,
        'body': body,
        'raw': resp.body,
      };
    } catch (e) {
      devLog('ApiService.deleteSuspectFromFace -> exception: $e');
      return {
        'ok': false,
        'deleted': false,
        'message': SafeError.format(e, fallback: "Something went wrong due to a network issue.")
      };
    }
  }

  // -----------------------------
  // Internal Helper: Authenticated GET
  // -----------------------------
  Future<Map<String, dynamic>> _authenticatedGet(Uri uri) async {
    final token = await getToken();
    try {
      final resp = await http.get(uri, headers: _jsonHeaders(token: token)).timeout(const Duration(seconds: 12));
      final body = _safeJson(resp.body);

      if (resp.statusCode == 200) {
        return {'ok': true, 'data': body};
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        return {'ok': false, 'message': 'Unauthorized (401/403). Please login again.', 'status': resp.statusCode};
      } else {
        return {'ok': false, 'message': body['message'] ?? 'Failed to fetch data (${resp.statusCode})', 'body': body};
      }
    } catch (e) {
      return {
        'ok': false,
        'message': SafeError.format(e, fallback: "Network connection error.")
      };
    }
  }
}