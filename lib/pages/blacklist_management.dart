// lib/pages/blacklist_management.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import '../utils/safe_log.dart';
import '../utils/safe_error.dart';
import '../services/api_service.dart';
import '../utils/validators.dart';

/// Blacklist Management
class BlacklistManagementPage extends StatefulWidget {
  final String role;

  const BlacklistManagementPage({super.key, required this.role});

  @override
  State<BlacklistManagementPage> createState() => _BlacklistManagementPageState();
}

class _BlacklistManagementPageState extends State<BlacklistManagementPage>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();

  // Explicitly define Base URL
  //String BASE_URL = ${ApiService.backendBaseUrl};

  final int _limit = 20;

  bool _loadingDL = false;
  bool _loadingRC = false;
  bool _loadingFace = false;
  String? _errorDL;
  String? _errorRC;
  String? _errorFace;

  List<Map<String, dynamic>> _dlList = [];
  List<Map<String, dynamic>> _rcList = [];
  // Key: unique_id (string), Value: {id, name, image} where image is base64
  Map<String, Map<String, dynamic>> _faceMap = {};
  int _dlTotal = 0;
  int _rcTotal = 0;
  int _faceTotal = 0;
  int _dlPage = 1;
  int _rcPage = 1;
  bool _isSearching = false;

  final TextEditingController _dlSearchCtrl = TextEditingController();
  final TextEditingController _rcSearchCtrl = TextEditingController();
  final TextEditingController _faceSearchCtrl = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _typeCtrl = TextEditingController(text: 'dl');
  final Map<String, TextEditingController> _formCtrls = {
    'number': TextEditingController(),
    'reason': TextEditingController(),
    'name': TextEditingController(),
    'phone': TextEditingController(),
    'owner': TextEditingController(),
    'maker': TextEditingController(),
    'vehicle': TextEditingController(),
    'wheel': TextEditingController(),
    'father': TextEditingController(),
    'address': TextEditingController(),
    'fuel': TextEditingController(),
    'body': TextEditingController(),
    'mfg': TextEditingController(),
    'chassis': TextEditingController(),
    'engine': TextEditingController(),
    'regn_date': TextEditingController(),
    'valid_upto': TextEditingController(),
    'tax_paid': TextEditingController(),
    'crime': TextEditingController(),
  };

  final _faceAddFormKey = GlobalKey<FormState>();
  final TextEditingController _faceAddName = TextEditingController();
  XFile? _faceAddImage;

  final ImagePicker _imagePicker = ImagePicker();

  XFile? _dlBlacklistImage;
  XFile? _rcBlacklistImage;
  List<String> _dlBlacklistCandidates = [];
  int _dlBlacklistCandidateIndex = 0;
  bool _dlBlacklistExtracting = false;
  bool _rcBlacklistExtracting = false;
  bool _dlBlacklistCancelled = false;
  bool _rcBlacklistCancelled = false;
  int _dlBlacklistRequestId = 0;
  int _rcBlacklistRequestId = 0;
  bool _submittingBlacklist = false;

  late TabController _tabController;
  final ScrollController _dlScroll = ScrollController();
  final ScrollController _rcScroll = ScrollController();
  final ScrollController _faceScroll = ScrollController();

  Timer? _dlDebounce;
  Timer? _rcDebounce;
  Timer? _faceDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));

    _dlSearchCtrl.addListener(() {
      _dlDebounce?.cancel();
      _dlDebounce = Timer(const Duration(milliseconds: 400), () => _fetchDLs(page: 1));
    });
    _rcSearchCtrl.addListener(() {
      _rcDebounce?.cancel();
      _rcDebounce = Timer(const Duration(milliseconds: 400), () => _fetchRCs(page: 1));
    });
    _faceSearchCtrl.addListener(() {
      _faceDebounce?.cancel();
      _faceDebounce = Timer(const Duration(milliseconds: 400), () => _fetchFaces());
    });

    _fetchDLs();
    _fetchRCs();
    _fetchFaces();

    _dlScroll.addListener(() {
      if (_dlScroll.position.pixels > _dlScroll.position.maxScrollExtent - 200 &&
          (_dlPage * _limit) < _dlTotal &&
          !_loadingDL) {
        _fetchDLs(page: _dlPage + 1);
      }
    });

    _rcScroll.addListener(() {
      if (_rcScroll.position.pixels > _rcScroll.position.maxScrollExtent - 200 &&
          (_rcPage * _limit) < _rcTotal &&
          !_loadingRC) {
        _fetchRCs(page: _rcPage + 1);
      }
    });
  }

  @override
  void dispose() {
    _dlDebounce?.cancel();
    _rcDebounce?.cancel();
    _faceDebounce?.cancel();
    _dlSearchCtrl.dispose();
    _rcSearchCtrl.dispose();
    _faceSearchCtrl.dispose();
    _formCtrls.forEach((key, ctrl) => ctrl.dispose());
    _typeCtrl.dispose();
    _faceAddName.dispose();
    _tabController.dispose();
    _dlScroll.dispose();
    _rcScroll.dispose();
    _faceScroll.dispose();
    super.dispose();
  }

  // Helper to get Headers with Token
  Future<Map<String, String>> _getHeaders() async {
    final token = await _api.getToken();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'accept': 'application/json',
    };
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }


  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // -----------------------
  // Autofill, validation, and search helpers
  // -----------------------
  String _normalizeText(String? value) {
    return (value ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _flattenAny(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();
    if (value is Map) {
      return value.values.map(_flattenAny).where((e) => e.trim().isNotEmpty).join(' ');
    }
    if (value is List) {
      return value.map(_flattenAny).where((e) => e.trim().isNotEmpty).join(' ');
    }
    return value.toString();
  }

  List<Map<String, dynamic>> _semanticFilterEntries(
      List<Map<String, dynamic>> entries,
      String query,
      ) {
    final q = _normalizeText(query);
    if (q.isEmpty) return entries;

    final tokens = q.split(' ').where((t) => t.trim().length >= 2).toList();
    if (tokens.isEmpty) return entries;

    int score(Map<String, dynamic> entry) {
      final blob = _normalizeText(_flattenAny(entry));
      int s = 0;
      for (final token in tokens) {
        if (blob.contains(token)) s += 2;
      }
      return s;
    }

    final filtered = entries
        .where((entry) {
      final blob = _normalizeText(_flattenAny(entry));
      return tokens.every((t) => blob.contains(t));
    })
        .toList();

    filtered.sort((a, b) => score(b).compareTo(score(a)));
    return filtered;
  }

  String? _safeString(dynamic value) {
    final s = value?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  String? _deepFindString(dynamic source, List<String> keys) {
    if (source == null) return null;
    if (source is Map) {
      for (final entry in source.entries) {
        for (final key in keys) {
          if (entry.key.toString().toLowerCase() == key.toLowerCase()) {
            final found = _safeString(entry.value);
            if (found != null) return found;
          }
        }
      }
      for (final value in source.values) {
        final nested = _deepFindString(value, keys);
        if (nested != null) return nested;
      }
    } else if (source is List) {
      for (final value in source) {
        final nested = _deepFindString(value, keys);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  bool _isImageSelectionValid(String pathOrName) {
    final ext = pathOrName.toLowerCase();
    return ext.endsWith('.jpg') ||
        ext.endsWith('.jpeg') ||
        ext.endsWith('.png') ||
        ext.endsWith('.webp') ||
        ext.endsWith('.bmp');
  }

  Future<bool> _validatePickedImage(XFile picked) async {
    if (kIsWeb) {
      return _isImageSelectionValid(picked.name);
    }
    final file = File(picked.path);
    return Validators.isValidImage(file);
  }

  File? _xFileToFile(XFile? file) {
    if (kIsWeb || file == null || file.path.isEmpty) return null;
    return File(file.path);
  }

  List<String> _extractDlCandidates(dynamic resp) {
    final dynamic data = resp is Map ? (resp['data'] ?? resp) : resp;
    final candidates = <String>[];

    if (data is Map && data['dl_numbers'] is List) {
      for (final item in (data['dl_numbers'] as List)) {
        final s = _safeString(item);
        if (s != null) candidates.add(s);
      }
    }

    if (candidates.isEmpty) {
      final text = _safeString(_deepFindString(data, ['extracted_text', 'dl_number', 'dl_numbers']));
      if (text != null) candidates.add(text);
    }

    final unique = <String>[];
    for (final item in candidates) {
      if (!unique.contains(item)) unique.add(item);
    }
    return unique;
  }

  String? _extractRcNumber(dynamic resp) {
    final dynamic data = resp is Map ? (resp['data'] ?? resp) : resp;
    return _safeString(_deepFindString(data, [
      'extracted_text', 'rc_number', 'regn_number', 'regnno',
      'rc_regn_no', 'regNo', 'vehicle_number', 'number_plate',
    ]));
  }

  void _resetDlAutofillState({bool clearNumber = false}) {
    _dlBlacklistCancelled = false;
    _dlBlacklistExtracting = false;
    _dlBlacklistCandidates = [];
    _dlBlacklistCandidateIndex = 0;
    if (clearNumber) {
      _formCtrls['number']?.clear();
    }
  }

  void _resetRcAutofillState({bool clearNumber = false}) {
    _rcBlacklistCancelled = false;
    _rcBlacklistExtracting = false;
    if (clearNumber) {
      _formCtrls['number']?.clear();
    }
  }

  void _cancelDlAutofill() {
    _dlBlacklistCancelled = true;
    _dlBlacklistRequestId++;
    if (mounted) {
      setState(() {
        _dlBlacklistExtracting = false;
      });
    }
  }

  void _cancelRcAutofill() {
    _rcBlacklistCancelled = true;
    _rcBlacklistRequestId++;
    if (mounted) {
      setState(() {
        _rcBlacklistExtracting = false;
      });
    }
  }

  void _cycleDlCandidate() {
    if (_dlBlacklistCandidates.isEmpty) return;
    _dlBlacklistCandidateIndex = (_dlBlacklistCandidateIndex + 1) % _dlBlacklistCandidates.length;
    _formCtrls['number']?.text = _dlBlacklistCandidates[_dlBlacklistCandidateIndex];
    if (mounted) setState(() {});
  }

  void _populateRcDetails(dynamic data) {
    final map = data is Map ? data : <String, dynamic>{};

    // Map aishtrex API keys (rc_*) and also fallback to generic keys
    _formCtrls['owner']?.text = _safeString(_deepFindString(map, [
      'rc_owner_name', 'owner_name', 'owner', 'registered_owner'])) ?? '';
    _formCtrls['maker']?.text = _safeString(_deepFindString(map, [
      'rc_maker_desc', 'rc_maker_model', 'maker_class', 'maker', 'manufacturer'])) ?? '';
    _formCtrls['vehicle']?.text = _safeString(_deepFindString(map, [
      'rc_vh_class_desc', 'rc_vhclass_desc', 'vehicle_class', 'class_of_vehicle', 'vehicle_type'])) ?? '';
    // Wheel type: derive from rc_vh_class_desc (e.g. "Motor Car(LMV)" -> "4 Wheeler")
    final vhClassDesc = _safeString(_deepFindString(map, ['rc_vh_class_desc', 'rc_vhclass_desc'])) ?? '';
    final wheelDerived = _deriveWheelType(vhClassDesc);
    _formCtrls['wheel']?.text = _safeString(_deepFindString(map, [
      'wheel_type', 'wheel'])) ?? wheelDerived;
    _formCtrls['father']?.text = _safeString(_deepFindString(map, [
      'father_name', 'father'])) ?? '';
    _formCtrls['address']?.text = _safeString(_deepFindString(map, [
      'rc_present_address', 'rc_permanent_address', 'address', 'present_address', 'permanent_address'])) ?? '';
    _formCtrls['fuel']?.text = _safeString(_deepFindString(map, [
      'rc_fuel_desc', 'fuel_used', 'fuel'])) ?? '';
    _formCtrls['body']?.text = _safeString(_deepFindString(map, [
      'type_of_body', 'body_type'])) ?? '';
    _formCtrls['mfg']?.text = _safeString(_deepFindString(map, [
      'rc_manu_month_yr', 'mfg_month_year', 'manufacturing_date', 'mfg'])) ?? '';
    _formCtrls['chassis']?.text = _safeString(_deepFindString(map, [
      'rc_chasi_no', 'chassis_number', 'chassis_no'])) ?? '';
    _formCtrls['engine']?.text = _safeString(_deepFindString(map, [
      'rc_eng_no', 'engine_number', 'engine_no'])) ?? '';
    _formCtrls['regn_date']?.text = _safeString(_deepFindString(map, [
      'rc_purchase_dt', 'registration_date', 'regn_date'])) ?? '';
    _formCtrls['valid_upto']?.text = _safeString(_deepFindString(map, [
      'rc_regn_upto', 'rc_fit_upto', 'valid_upto', 'validity', 'expiry_date'])) ?? '';
    _formCtrls['tax_paid']?.text = _safeString(_deepFindString(map, [
      'rc_tax_upto', 'tax_paid', 'tax'])) ?? '';
  }

  /// Derive wheel type from vehicle class description (aishtrex specific)
  String _deriveWheelType(String vhClassDesc) {
    final lower = vhClassDesc.toLowerCase();
    if (lower.contains('two') || lower.contains('2w') || lower.contains('motorcycle') ||
        lower.contains('scooter') || lower.contains('moped')) {
      return '2 Wheeler';
    } else if (lower.contains('three') || lower.contains('3w') || lower.contains('auto')) {
      return '3 Wheeler';
    } else if (lower.contains('lmv') || lower.contains('motor car') ||
        lower.contains('four') || lower.contains('4w') || lower.contains('truck') ||
        lower.contains('bus') || lower.contains('maxi')) {
      return '4 Wheeler';
    }
    return '';
  }

  Future<void> _runDlAutofill(XFile picked) async {
    final file = _xFileToFile(picked);
    if (file == null) return;

    final requestId = ++_dlBlacklistRequestId;
    _dlBlacklistCancelled = false;

    if (mounted) {
      setState(() {
        _dlBlacklistExtracting = true;
        _dlBlacklistCandidates = [];
        _dlBlacklistCandidateIndex = 0;
      });
    }

    try {
      final resp = await _api.ocrDL(file);
      if (!mounted || requestId != _dlBlacklistRequestId || _dlBlacklistCancelled) return;

      final candidates = _extractDlCandidates(resp);
      if (candidates.isEmpty) {
        if (mounted) {
          setState(() {
            _dlBlacklistExtracting = false;
            _formCtrls['number']?.clear();
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _dlBlacklistCandidates = candidates;
          _dlBlacklistCandidateIndex = 0;
          _formCtrls['number']?.text = candidates.first;
          _dlBlacklistExtracting = false;
        });
      }
    } catch (e) {
      if (!mounted || requestId != _dlBlacklistRequestId || _dlBlacklistCancelled) return;
      if (mounted) {
        setState(() {
          _dlBlacklistExtracting = false;
          _formCtrls['number']?.clear();
        });
      }
      devLog('DL OCR error: $e');
      _showErrorSnackBar(SafeError.format(e, fallback: 'Could not extract DL number from the image. Please type it manually.'));
    }
  }

  Future<void> _runRcAutofill(XFile picked) async {
    final file = _xFileToFile(picked);
    if (file == null) return;

    final requestId = ++_rcBlacklistRequestId;
    _rcBlacklistCancelled = false;

    if (mounted) {
      setState(() {
        _rcBlacklistExtracting = true;
      });
    }

    try {
      final ocrResp = await _api.ocrRC(file);
      if (!mounted || requestId != _rcBlacklistRequestId || _rcBlacklistCancelled) return;

      final rcNumber = _extractRcNumber(ocrResp);
      if (rcNumber == null || rcNumber.isEmpty) {
        if (mounted) {
          setState(() {
            _rcBlacklistExtracting = false;
            _formCtrls['number']?.clear();
          });
        }
        _showErrorSnackBar('Could not read a vehicle number from the image. Please type the RC number manually, then tap "Fetch Vehicle Details".');
        return;
      }

      if (mounted) {
        setState(() {
          _formCtrls['number']?.text = rcNumber;
        });
      }

      final detailsResp = await _api.getVehicleDetails(rcNumber);
      if (!mounted || requestId != _rcBlacklistRequestId || _rcBlacklistCancelled) return;

      if (detailsResp['ok'] == true) {
        // aishtrex returns the fields directly in 'data'
        final data = detailsResp['data'];
        if (mounted) {
          setState(() {
            _populateRcDetails(data);
            _rcBlacklistExtracting = false;
          });
        }
        _showInfoSnackBar('Vehicle details auto-filled successfully.');
      } else {
        if (mounted) {
          setState(() {
            _rcBlacklistExtracting = false;
          });
        }
        _showInfoSnackBar('Vehicle number extracted, but auto-fill details were not available.');
      }
    } catch (e) {
      if (!mounted || requestId != _rcBlacklistRequestId || _rcBlacklistCancelled) return;
      if (mounted) {
        setState(() {
          _rcBlacklistExtracting = false;
          _formCtrls['number']?.clear();
        });
      }
      devLog('RC OCR error: $e');
      _showErrorSnackBar(SafeError.format(e, fallback: 'Could not read the RC image. Please type the vehicle number manually.'));
    }
  }
  /// -----------------------
  /// Fetching functions
  /// -----------------------
  Future<void> _fetchDLs({int page = 1}) async {
    if (!mounted) return;
    setState(() {
      _loadingDL = true;
      _errorDL = null;
    });

    final q = _dlSearchCtrl.text.trim();
    // Sanitize search query slightly to prevent crash in URL encoding
    if (q.isNotEmpty && Validators.validateSafeText(q) != null) {
      // Only log internally, don't stop user typing
      devLog('Invalid search char in DL query');
    }

    final uri = Uri.parse(
        '${ApiService.backendBaseUrl}/api/blacklist/dl?page=$page&limit=$_limit${q.isNotEmpty ? '&search=${Uri.encodeQueryComponent(q)}' : ''}');

    try {
      final headers = await _getHeaders();
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
      final body = jsonDecode(res.body);

      if (res.statusCode == 200) {
        List<Map<String, dynamic>> dataList = [];
        int pageGot = page;
        int totalGot = 0;

        if (body is Map) {
          final rawList = body['data'] ?? body['items'] ?? body['results'] ?? body;
          if (rawList is List) {
            dataList = List<Map<String, dynamic>>.from(
                rawList.map((e) => Map<String, dynamic>.from(e as Map)));
          }
          pageGot = body['page'] ?? page;
          totalGot = body['total'] ?? dataList.length;
        } else if (body is List) {
          dataList = List<Map<String, dynamic>>.from(
              body.map((e) => Map<String, dynamic>.from(e as Map)));
          totalGot = dataList.length;
        }

        if (!mounted) return;
        setState(() {
          if (page == 1) {
            _dlList = dataList;
          } else {
            _dlList.addAll(dataList);
          }
          _dlTotal = totalGot;
          _dlPage = pageGot;
        });
      } else {
        if (!mounted) return;
        setState(() => _errorDL = body['message'] ?? 'Failed to load DL blacklist');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorDL!)));
      }
    } catch (e) {
      if (!mounted) return;
      devLog('fetchDLs error: $e');
      setState(() => _errorDL = SafeError.format(e, fallback: 'Error loading DL blacklist.'));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorDL!)));
    } finally {
      if (!mounted) return;
      setState(() => _loadingDL = false);
    }
  }

  Future<void> _fetchRCs({int page = 1}) async {
    if (!mounted) return;
    setState(() {
      _loadingRC = true;
      _errorRC = null;
    });

    final q = _rcSearchCtrl.text.trim();
    final uri = Uri.parse(
        '${ApiService.backendBaseUrl}/api/blacklist/rc?page=$page&limit=$_limit${q.isNotEmpty ? '&search=${Uri.encodeQueryComponent(q)}' : ''}');

    try {
      final headers = await _getHeaders();
      final res = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));
      final body = jsonDecode(res.body);

      if (res.statusCode == 200) {
        List<Map<String, dynamic>> dataList = [];
        int pageGot = page;
        int totalGot = 0;

        if (body is Map) {
          final rawList = body['data'] ?? body['items'] ?? body['results'] ?? body;
          if (rawList is List) {
            dataList = List<Map<String, dynamic>>.from(
                rawList.map((e) => Map<String, dynamic>.from(e as Map)));
          }
          pageGot = body['page'] ?? page;
          totalGot = body['total'] ?? dataList.length;
        } else if (body is List) {
          dataList = List<Map<String, dynamic>>.from(
              body.map((e) => Map<String, dynamic>.from(e as Map)));
          totalGot = dataList.length;
        }

        if (!mounted) return;
        setState(() {
          if (page == 1) {
            _rcList = dataList;
          } else {
            _rcList.addAll(dataList);
          }
          _rcTotal = totalGot;
          _rcPage = pageGot;
        });
      } else {
        if (!mounted) return;
        setState(() => _errorRC = body['message'] ?? 'Failed to load RC blacklist');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorRC!)));
      }
    } catch (e) {
      if (!mounted) return;
      devLog('fetchRCs error: $e');
      setState(() => _errorRC = SafeError.format(e, fallback: 'Error loading RC blacklist.'));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorRC!)));
    } finally {
      if (!mounted) return;
      setState(() => _loadingRC = false);
    }
  }

  Future<void> _fetchFaces() async {
    if (!mounted) return;
    setState(() {
      _loadingFace = true;
      _errorFace = null;
    });

    try {
      final resp = await _api.listSuspects();
      if (resp is Map && resp['ok'] == true) {
        final body = resp['data'];
        // New API: body is a List of {name, image} objects (image is base64)
        // We use an auto-generated unique ID (index-based) as key so duplicate
        // names are handled correctly. The unique_id is the map key.
        final Map<String, Map<String, dynamic>> faceMap = {};

        if (body is List) {
          for (int i = 0; i < body.length; i++) {
            final item = body[i];
            if (item is Map) {
              final name = (item['name'] ?? '').toString();
              final image = item['image']?.toString() ?? '';
              // Use id field from server if available, otherwise generate one
              final uniqueId = (item['id'] ?? item['unique_id'] ?? 'face_$i').toString();
              faceMap[uniqueId] = {
                'id': uniqueId,
                'name': name,
                'image': image,
              };
            }
          }
        } else if (body is Map) {
          // Fallback: handle old map-style response gracefully
          int idx = 0;
          body.forEach((key, value) {
            final uniqueId = 'face_${idx++}';
            faceMap[uniqueId] = {
              'id': uniqueId,
              'name': key.toString(),
              'image': value is String ? value : '',
            };
          });
        }

        final q = _faceSearchCtrl.text.trim().toLowerCase();
        final Map<String, Map<String, dynamic>> filteredMap = q.isEmpty
            ? faceMap
            : {
          for (var entry in faceMap.entries)
            if (entry.value['name'].toString().toLowerCase().contains(q))
              entry.key: entry.value
        };
        if (!mounted) return;
        setState(() {
          _faceMap = filteredMap;
          _faceTotal = _faceMap.length;
        });
      } else {
        if (!mounted) return;
        final msg = (resp is Map)
            ? resp['message'] ?? 'Failed to load face suspects'
            : 'Failed to load face suspects';
        setState(() => _errorFace = msg);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (!mounted) return;
      devLog('fetchFaces error: $e');
      setState(() => _errorFace = SafeError.format(e, fallback: 'Error loading face suspects.'));
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_errorFace!)));
    } finally {
      if (!mounted) return;
      setState(() => _loadingFace = false);
    }
  }

  /// -----------------------
  /// Add & Remove functions
  /// -----------------------

  Future<void> _addToBlacklist() async {
    final type = _typeCtrl.text.trim();

    if (type == 'face') {
      if (!_faceAddFormKey.currentState!.validate()) return;
    } else {
      if (!_formKey.currentState!.validate()) return;
    }

    final reason = _safeString(_formCtrls['reason']?.text);
    if (type != 'face' && (reason == null || reason.isEmpty)) {
      _showErrorSnackBar('Reason for blacklisting is required.');
      return;
    }

    if (type == 'face') {
      await _addFaceSuspect();
      return;
    }

    final payload = <String, dynamic>{
      'type': type,
      'number': _safeString(_formCtrls['number']?.text),
      'reason': reason,
    };

    if (type == 'dl') {
      final name = _safeString(_formCtrls['name']?.text);
      final phone = _safeString(_formCtrls['phone']?.text);
      if (name != null) payload['name'] = name;
      if (phone != null) payload['phone_number'] = phone;
    }

    if (type == 'rc') {
      final fields = {
        'owner_name': _safeString(_formCtrls['owner']?.text),
        'maker_class': _safeString(_formCtrls['maker']?.text),
        'vehicle_class': _safeString(_formCtrls['vehicle']?.text),
        'wheel_type': _safeString(_formCtrls['wheel']?.text),
        'father_name': _safeString(_formCtrls['father']?.text),
        'address': _safeString(_formCtrls['address']?.text),
        'fuel_used': _safeString(_formCtrls['fuel']?.text),
        'type_of_body': _safeString(_formCtrls['body']?.text),
        'mfg_month_year': _safeString(_formCtrls['mfg']?.text),
        'chassis_number': _safeString(_formCtrls['chassis']?.text),
        'engine_number': _safeString(_formCtrls['engine']?.text),
        'registration_date': _safeString(_formCtrls['regn_date']?.text),
        'valid_upto': _safeString(_formCtrls['valid_upto']?.text),
        'tax_paid': _safeString(_formCtrls['tax_paid']?.text),
      };
      fields.forEach((key, value) {
        if (value != null) payload[key] = value;
      });
    }

    payload.removeWhere((key, value) => value == null || (value is String && value.trim().isEmpty));

    if (!mounted) return;
    setState(() => _submittingBlacklist = true);

    try {
      final resp = await _api.addToBlacklist(payload);

      if (!mounted) return;
      if (resp is Map && resp['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Added to blacklist successfully!'),
          backgroundColor: Colors.green,
        ));

        if (type == 'dl') {
          await _fetchDLs(page: 1);
        } else if (type == 'rc') {
          await _fetchRCs(page: 1);
        }
        Navigator.of(context).pop();
      } else {
        final msg = (resp is Map)
            ? (resp['message'] ?? 'Failed to add')
            : 'Failed to add';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      devLog('addToBlacklist error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(SafeError.format(e, fallback: 'Failed to add to blacklist. Please try again.')), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _submittingBlacklist = false);
    }
  }

// Helpers for Face deletions
  bool _mapIndicatesDeleted(dynamic obj) {
    try {
      if (obj == null) return false;
      if (obj is Map) {
        for (final k in obj.keys) {
          final v = obj[k];
          if (v is String) {
            if (v.toLowerCase().contains('deleted')) return true;
          } else if (v is num) {
            if (k.toString().toLowerCase().contains('deleted') && v.toInt() > 0) return true;
            if (v.toInt() > 0 && k.toString().toLowerCase().contains('count')) return true;
          } else if (v is Map || v is List) {
            if (_mapIndicatesDeleted(v)) return true;
          }
        }
        final status = (obj['status'] ?? obj['result'] ?? '').toString().toLowerCase();
        if (status.contains('deleted')) return true;
        final dc = obj['deleted_count'] ?? obj['deleted'] ?? obj['deletedCount'];
        if (dc is num && dc.toInt() > 0) return true;
        if (obj['ok'] == true) return true;
        return false;
      } else if (obj is List) {
        for (final el in obj) {
          if (_mapIndicatesDeleted(el)) return true;
        }
        return false;
      } else if (obj is String) {
        return obj.toLowerCase().contains('deleted');
      } else {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  bool _isPersonPresentInFaceListResponse(dynamic body, String personName) {
    try {
      if (body == null) return false;
      if (body is Map) {
        if (body.containsKey(personName)) return true;
        for (final entryKey in body.keys) {
          final val = body[entryKey];
          if (val is List) {
            for (final item in val) {
              if (item is String) {
                final lower = item.toLowerCase();
                if (lower.contains('/${personName.toLowerCase()}/') ||
                    lower.endsWith('/${personName.toLowerCase()}') ||
                    lower.contains(personName.toLowerCase())) {
                  try {
                    final uri = Uri.parse(item);
                    if (uri.pathSegments.length >= 2) {
                      final candidate = uri.pathSegments[uri.pathSegments.length - 2];
                      if (candidate.toLowerCase() == personName.toLowerCase()) return true;
                    }
                  } catch (_) {
                    return true;
                  }
                }
              }
            }
          } else if (entryKey.toString().toLowerCase() == personName.toLowerCase()) {
            return true;
          }
        }
      }
      if (body is List) {
        for (final el in body) {
          if (el is String && el.toLowerCase().contains(personName.toLowerCase())) return true;
          if (el is Map && _isPersonPresentInFaceListResponse(el, personName)) return true;
        }
      }
      final s = body.toString().toLowerCase();
      if (s.contains(personName.toLowerCase())) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _deleteFaceSuspectApi(String personName) async {
    try {
      final dynamic raw = await _api.deleteSuspectFromFace(personName);
      if (raw == null) return false;

      if (raw is Map) {
        if (raw['ok'] == true) {
          if (raw.containsKey('deleted')) return raw['deleted'] == true;
          if (raw.containsKey('data') && _mapIndicatesDeleted(raw['data'])) return true;
          if (_mapIndicatesDeleted(raw)) return true;
          return true;
        } else {
          if (raw.containsKey('data') && _mapIndicatesDeleted(raw['data'])) return true;
          if (_mapIndicatesDeleted(raw)) return true;
          return false;
        }
      }
      return false;
    } catch (e) {
      try {
        final listResp = await _api.listSuspects();
        if (listResp is Map && listResp['ok'] == true) {
          final body = listResp['data'];
          final present = _isPersonPresentInFaceListResponse(body, personName);
          if (!present) return true;
        }
      } catch (_) {}
      return false;
    }
  }

  Future<void> _addFaceSuspect() async {
    if (!_faceAddFormKey.currentState!.validate()) return;
    if (_faceAddImage == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select an image'), backgroundColor: Colors.red));
      return;
    }

    // NEW: Validate Image Magic Bytes
    final file = File(_faceAddImage!.path);
    if (!await Validators.isValidImage(file)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Security Error: The file is corrupted or not a valid image.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final resp = await _api.addSuspectFromFace(
        personName: _faceAddName.text.trim(),
        imagePath: _faceAddImage!.path,
      );

      try {
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      } catch (_) {}

      if (!mounted) return;
      if (resp is Map && resp['ok'] == true) {
        // Extract unique ID assigned by the server if available
        final assignedId = (resp['data'] is Map)
            ? (resp['data']['unique_id'] ?? resp['data']['id'] ?? resp['data']['person_id'])?.toString()
            : null;
        final msg = assignedId != null
            ? 'Suspect added! Unique ID: $assignedId'
            : 'Suspect added successfully!';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg),
            backgroundColor: Colors.green));
        await _fetchFaces();
      } else {
        final msg = (resp is Map)
            ? resp['message'] ?? 'Failed to add face suspect'
            : 'Failed to add face suspect';
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    } catch (e) {
      try {
        if (Navigator.of(context, rootNavigator: true).canPop()) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      } catch (_) {}
      if (mounted) {
        devLog('addFaceSuspect error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(SafeError.format(e, fallback: 'Failed to add face suspect. Please try again.')), backgroundColor: Colors.red));
      }
    }
  }

  Future<bool> _markValid(String type, String id) async {
    try {
      // final uri = Uri.parse('${ApiService.backendBaseUrl}/api/blacklist/$type/$id');
      // Encode the ID to ensure the URI is always valid format
      final encodedId = Uri.encodeComponent(id);
      final uri = Uri.parse('${ApiService.backendBaseUrl}/api/blacklist/$type/$encodedId');

      // Optional: Add a log to verify the URL being called
      devLog("Attempting to delete $type with URI: $uri");


      final headers = await _getHeaders();

      final res = await http.put(uri, headers: headers).timeout(const Duration(seconds: 30));
      final resp = jsonDecode(res.body);

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Entry marked valid (removed)'),
              backgroundColor: Colors.green));
        }
        if (type == 'dl') {
          await _fetchDLs(page: 1);
        } else {
          await _fetchRCs(page: 1);
        }
        return true;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(resp['message'] ?? 'Failed to mark valid'),
              backgroundColor: Colors.red));
        }
        return false;
      }
    } catch (e) {
      if (mounted) {
        devLog('markValid error: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(SafeError.format(e, fallback: 'Failed to remove from blacklist. Please try again.')), backgroundColor: Colors.red));
      }
      return false;
    }
  }

  /// -----------------------
  /// UI pieces
  /// -----------------------

  Widget _buildListContent(
      List<Map<String, dynamic>> list,
      String type,
      String? error,
      bool loading,
      ScrollController scrollController,
      ) {
    final query = type == 'dl' ? _dlSearchCtrl.text.trim() : _rcSearchCtrl.text.trim();
    final visibleList = _semanticFilterEntries(list, query);

    if (loading && visibleList.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && visibleList.isEmpty) {
      return Center(child: Text(error, style: const TextStyle(color: Colors.red)));
    }

    if (visibleList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(type == 'dl' ? Icons.no_accounts : Icons.directions_car,
                size: 60, color: Colors.black38),
            const SizedBox(height: 16),
            Text(
              query.isNotEmpty
                  ? 'No matching ${type.toUpperCase()} entries found.'
                  : 'No blacklisted ${type.toUpperCase()}s found.',
              style: const TextStyle(fontSize: 18, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final isSuperAdmin = widget.role == 'superadmin';
    final dismissDirection =
    isSuperAdmin ? DismissDirection.endToStart : DismissDirection.none;

    return RefreshIndicator(
      onRefresh: () => type == 'dl' ? _fetchDLs(page: 1) : _fetchRCs(page: 1),
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: visibleList.length + (loading && visibleList.isNotEmpty ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == visibleList.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final entry = visibleList[i];

          dynamic rawId = entry['id'];
          String id = '';

          if (rawId != null) {
            if (rawId is Map) {
              id = rawId[r'$oid']?.toString() ?? rawId.toString();
            } else {
              id = rawId.toString();
            }
          }

          if (id.isEmpty) {
            devLog('WARNING: Could not extract ID from entry: $entry');
          }

          final title = type == 'dl'
              ? (entry['dl_number'] ?? entry['dl'] ?? entry['number'] ?? 'Unknown DL')
              : (entry['regn_number'] ??
              entry['rc_number'] ??
              entry['regnNo'] ??
              entry['number'] ??
              'Unknown RC');
          final subtitle = _buildSubtitle(entry, type);
          final status = (entry['verification'] ??
              entry['Verification'] ??
              entry['status'] ??
              '')
              .toString();

          return Dismissible(
            key: ValueKey(id.isNotEmpty ? id : '$type-$i'),
            direction: dismissDirection,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.delete_forever, color: Colors.red),
            ),
            confirmDismiss: (direction) async {
              final confirmed = await _showConfirmDialog(
                  'Mark this ${type.toUpperCase()} as valid (remove from blacklist)?');
              if (confirmed != true) return false;

              showDialog(
                context: context,
                barrierDismissible: false,
                useRootNavigator: true,
                builder: (_) => const Center(child: CircularProgressIndicator()),
              );

              bool ok = false;
              try {
                ok = await _markValid(type, id.toString());
              } catch (e) {
                ok = false;
              } finally {
                try {
                  if (Navigator.of(context, rootNavigator: true).canPop()) {
                    Navigator.of(context, rootNavigator: true).pop();
                  }
                } catch (_) {}
              }

              return ok;
            },
            onDismissed: (direction) {
              if (mounted) {
                setState(() {
                  list.removeWhere((e) {
                    final eid = (e['id'] is Map)
                        ? (e['id'][r'$oid'] ?? e['id'].toString())
                        : e['id']?.toString() ?? '';
                    return eid == id;
                  });
                  if (type == 'dl') {
                    _dlTotal = _dlList.length;
                  } else {
                    _rcTotal = _rcList.length;
                  }
                });
              }
            },
            child: Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                leading: CircleAvatar(
                  backgroundColor:
                  type == 'dl' ? Colors.blue.shade50 : Colors.teal.shade50,
                  child: Icon(
                    type == 'dl' ? Icons.badge : Icons.directions_car,
                    color: type == 'dl' ? Colors.blue : Colors.teal,
                  ),
                ),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: subtitle,
                trailing: Chip(
                  label: Text(
                    status.isNotEmpty ? status : '-',
                    style: TextStyle(
                      color: status.toLowerCase().contains('black')
                          ? Colors.red.shade700
                          : Colors.green.shade700,
                    ),
                  ),
                  backgroundColor: status.toLowerCase().contains('black')
                      ? Colors.red.shade50
                      : Colors.green.shade50,
                ),
                onTap: () => _showEntryDetails(context, entry, type: type),
              ),
            ),
          );
        },
      ),
    );
  }


  Widget _buildFaceListContent(String? error, bool loading, ScrollController scrollController) {
    final q = _faceSearchCtrl.text.trim().toLowerCase();
    final filteredMap = q.isEmpty
        ? _faceMap
        : {
      for (final entry in _faceMap.entries)
        if ((entry.value['name'] ?? '').toString().toLowerCase().contains(q))
          entry.key: entry.value,
    };

    if (loading && filteredMap.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null && filteredMap.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(error, style: const TextStyle(color: Colors.red, fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchFaces,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (filteredMap.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.face_retouching_off, size: 60, color: Colors.black38),
            const SizedBox(height: 16),
            const Text('No face suspects found.',
                style: TextStyle(fontSize: 18, color: Colors.black54)),
          ],
        ),
      );
    }

    final isSuperAdmin = widget.role == 'superadmin';
    final dismissDirection =
    isSuperAdmin ? DismissDirection.endToStart : DismissDirection.none;
    final filteredKeys = filteredMap.keys.toList();

    return RefreshIndicator(
      onRefresh: _fetchFaces,
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: filteredKeys.length,
        itemBuilder: (ctx, i) {
          final uniqueId = filteredKeys[i];
          final suspect = filteredMap[uniqueId]!;
          final personName = (suspect['name'] ?? '').toString();
          final imageB64 = (suspect['image'] ?? '').toString();

          Widget leadingWidget;
          if (imageB64.isNotEmpty) {
            try {
              final bytes = base64Decode(imageB64);
              leadingWidget = ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(bytes, width: 50, height: 50, fit: BoxFit.cover,
                    errorBuilder: (c, o, s) => const Icon(Icons.person, size: 50)),
              );
            } catch (_) {
              leadingWidget = const Icon(Icons.person, size: 50);
            }
          } else {
            leadingWidget = const Icon(Icons.person, size: 50);
          }

          return Dismissible(
            key: ValueKey(uniqueId),
            direction: dismissDirection,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                  color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.delete_forever, color: Colors.red),
            ),
            confirmDismiss: (direction) async {
              final confirmed = await _showConfirmDialog(
                  'Are you sure you want to delete $personName from the suspect list?');
              if (confirmed != true) return false;

              showDialog(
                context: context,
                barrierDismissible: false,
                useRootNavigator: true,
                builder: (_) => const Center(child: CircularProgressIndicator()),
              );

              bool success = false;
              try {
                success = await _deleteFaceSuspectApi(personName);
                if (success) {
                  await _fetchFaces();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Suspect deleted successfully!'),
                        backgroundColor: Colors.green));
                  }
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Failed to delete suspect'),
                        backgroundColor: Colors.red));
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(SafeError.format(e, fallback: 'Failed to delete suspect. Please try again.')), backgroundColor: Colors.red));
                }
                success = false;
              } finally {
                try {
                  if (Navigator.of(context, rootNavigator: true).canPop()) {
                    Navigator.of(context, rootNavigator: true).pop();
                  }
                } catch (_) {}
              }

              return success;
            },
            onDismissed: (direction) {
              if (mounted) {
                setState(() {
                  _faceMap.remove(uniqueId);
                  _faceTotal = _faceMap.length;
                });
              }
            },
            child: Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                leading: leadingWidget,
                title: Text(personName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('ID: $uniqueId'),
                onTap: () => _showSuspectDetails(context, personName, uniqueId, imageB64),
              ),
            ),
          );
        },
      ),
    );
  }

  String? _convertGsUrlToHttp(String? gsUrl) {
    if (gsUrl == null || !gsUrl.startsWith('gs://')) {
      return null;
    }
    final parts = gsUrl.substring(5).split('/');
    if (parts.length < 2) {
      return null;
    }
    final bucket = parts.first;
    final path = parts.sublist(1).join('/');
    return 'https://storage.googleapis.com/$bucket/$path';
  }

  Widget _buildSubtitle(Map<String, dynamic> entry, String type) {
    List<Widget> children = [];
    final reason = (entry['crime_involved'] ?? entry['reason'] ?? '').toString();

    if (type == 'dl') {
      final name = (entry['name'] ?? '').toString();
      final phone = (entry['phone_number'] ?? '').toString();
      if (name.isNotEmpty) children.add(Text(name));
      if (phone.isNotEmpty) children.add(Text('📞 $phone'));
    } else {
      final owner = (entry['owner_name'] ?? '').toString();
      final maker = (entry['maker_class'] ?? '').toString();
      final vclass = (entry['vehicle_class'] ?? '').toString();
      if (owner.isNotEmpty) children.add(Text('Owner: $owner'));
      if (maker.isNotEmpty) children.add(Text('Maker: $maker'));
      if (vclass.isNotEmpty) children.add(Text('Class: $vclass'));
    }
    if (reason.isNotEmpty) {
      children.add(Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Reason: $reason',
              style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic))));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Future<bool?> _showConfirmDialog(String text) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Action'),
        content: Text(text),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Confirm')),
        ],
      ),
    );
  }


  void _showAddBottomSheet() {
    void clearDlFields() {
      _dlBlacklistImage = null;
      _dlBlacklistCandidates = [];
      _dlBlacklistCandidateIndex = 0;
      _formCtrls['number']?.clear();
      _formCtrls['reason']?.clear();
      _formCtrls['name']?.clear();
      _formCtrls['phone']?.clear();
      _cancelDlAutofill();
    }

    void clearRcFields() {
      _rcBlacklistImage = null;
      for (final key in [
        'number',
        'reason',
        'owner',
        'maker',
        'vehicle',
        'wheel',
        'father',
        'address',
        'fuel',
        'body',
        'mfg',
        'chassis',
        'engine',
        'regn_date',
        'valid_upto',
        'tax_paid',
      ]) {
        _formCtrls[key]?.clear();
      }
      _cancelRcAutofill();
    }

    void clearFaceFields() {
      _faceAddImage = null;
      _faceAddName.clear();
    }

    clearDlFields();
    clearRcFields();
    clearFaceFields();

    if (_tabController.index == 0) {
      _typeCtrl.text = 'dl';
    } else if (_tabController.index == 1) {
      _typeCtrl.text = 'rc';
    } else {
      _typeCtrl.text = 'face';
    }

    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          final mediaQuery = MediaQuery.of(context);
          final isPortrait = mediaQuery.orientation == Orientation.portrait;
          final type = _typeCtrl.text.trim();

          Future<void> pickDlImage(ImageSource source) async {
            final picked = await _imagePicker.pickImage(
              source: source,
              imageQuality: 85,
            );
            if (picked == null) return;

            final valid = await _validatePickedImage(picked);
            if (!valid) {
              if (mounted) {
                _showErrorSnackBar('Security Error: Invalid image file.');
              }
              return;
            }

            clearDlFields();
            if (mounted) {
              setState(() {
                _dlBlacklistImage = picked;
              });
            }
            setModalState(() {});

            await _runDlAutofill(picked);
            if (mounted) setModalState(() {});
          }

          Future<void> pickRcImage(ImageSource source) async {
            final picked = await _imagePicker.pickImage(
              source: source,
              imageQuality: 85,
            );
            if (picked == null) return;

            final valid = await _validatePickedImage(picked);
            if (!valid) {
              if (mounted) {
                _showErrorSnackBar('Security Error: Invalid image file.');
              }
              return;
            }

            clearRcFields();
            if (mounted) {
              setState(() {
                _rcBlacklistImage = picked;
              });
            }
            setModalState(() {});

            await _runRcAutofill(picked);
            if (mounted) setModalState(() {});
          }

          Widget autoField(String label, TextEditingController ctrl) {
            return TextFormField(
              controller: ctrl,
              readOnly: true,
              decoration: InputDecoration(
                labelText: label,
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.grey.shade100,
              ),
            );
          }

          Widget actionSuffixDl() {
            if (_dlBlacklistExtracting) {
              return IconButton(
                tooltip: 'Cancel extraction',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _cancelDlAutofill();
                  setModalState(() {});
                },
              );
            }

            if (_dlBlacklistCandidates.length > 1) {
              final current = _dlBlacklistCandidateIndex + 1;
              final total = _dlBlacklistCandidates.length;
              return IconButton(
                tooltip: 'Show next DL suggestion',
                onPressed: () {
                  _cycleDlCandidate();
                  setModalState(() {});
                },
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.swap_horiz),
                    Positioned(
                      right: -10,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade600,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$current/$total',
                          style: const TextStyle(fontSize: 10, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            if (_dlBlacklistImage != null) {
              return IconButton(
                tooltip: 'Refresh OCR',
                icon: const Icon(Icons.refresh),
                onPressed: () async {
                  await _runDlAutofill(_dlBlacklistImage!);
                  if (mounted) setModalState(() {});
                },
              );
            }

            return const SizedBox.shrink();
          }

          Widget actionSuffixRc() {
            if (_rcBlacklistExtracting) {
              return IconButton(
                tooltip: 'Cancel extraction',
                icon: const Icon(Icons.close),
                onPressed: () {
                  _cancelRcAutofill();
                  setModalState(() {});
                },
              );
            }

            if (_rcBlacklistImage != null) {
              return IconButton(
                tooltip: 'Refresh OCR',
                icon: const Icon(Icons.refresh),
                onPressed: () async {
                  await _runRcAutofill(_rcBlacklistImage!);
                  if (mounted) setModalState(() {});
                },
              );
            }

            return const SizedBox.shrink();
          }

          Widget uploadCard({
            required String title,
            required XFile? image,
            required VoidCallback onCamera,
            required VoidCallback onGallery,
            required bool extracting,
            String? extraText,
          }) {
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.shade50,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: extracting ? null : onCamera,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Camera'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: extracting ? null : onGallery,
                          icon: const Icon(Icons.photo_library),
                          label: const Text('Gallery'),
                        ),
                      ),
                    ],
                  ),
                  if (image != null || (extraText != null && extraText.isNotEmpty)) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: extracting ? Colors.orange : Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            extracting
                                ? 'Extracting... you can cancel and type manually'
                                : extraText ?? image!.name,
                            style: TextStyle(
                              color: extracting ? Colors.orange.shade800 : Colors.green.shade800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: mediaQuery.viewInsets.bottom,
              top: 20,
              left: isPortrait ? 20 : 40,
              right: isPortrait ? 20 : 40,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: type == 'face' ? _faceAddFormKey : _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Add New Blacklist Entry',
                            style: Theme.of(context).textTheme.titleLarge),
                        IconButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Entry Type',
                        border: OutlineInputBorder(),
                      ),
                      value: type,
                      items: const [
                        DropdownMenuItem(value: 'dl', child: Text('Driving License (DL)')),
                        DropdownMenuItem(value: 'rc', child: Text('Registration Certificate (RC)')),
                        DropdownMenuItem(value: 'face', child: Text('Face Suspect')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setModalState(() {
                          _typeCtrl.text = v;
                          clearDlFields();
                          clearRcFields();
                          clearFaceFields();
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (type == 'face') ...[
                      TextFormField(
                        controller: _faceAddName,
                        decoration: const InputDecoration(
                          labelText: 'Suspect Name',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => Validators.validateSafeText(v, fieldName: 'Suspect Name'),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await _imagePicker.pickImage(
                                  source: ImageSource.camera,
                                  imageQuality: 85,
                                );
                                if (picked != null) {
                                  if (!await _validatePickedImage(picked)) {
                                    _showErrorSnackBar('Security Error: Invalid image file.');
                                    return;
                                  }
                                  if (mounted) {
                                    setState(() => _faceAddImage = picked);
                                  }
                                  setModalState(() {});
                                }
                              },
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Take Photo'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await _imagePicker.pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 85,
                                );
                                if (picked != null) {
                                  if (!await _validatePickedImage(picked)) {
                                    _showErrorSnackBar('Security Error: Invalid image file.');
                                    return;
                                  }
                                  if (mounted) {
                                    setState(() => _faceAddImage = picked);
                                  }
                                  setModalState(() {});
                                }
                              },
                              icon: const Icon(Icons.photo_library),
                              label: const Text('From Gallery'),
                            ),
                          ),
                        ],
                      ),
                      if (_faceAddImage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Selected: ${_faceAddImage!.name}',
                                  style: const TextStyle(fontSize: 12, color: Colors.green)),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(_faceAddImage!.path),
                                  height: 120,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (c, e, s) =>
                                  const Icon(Icons.broken_image, size: 60),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ] else ...[
                      if (type == 'dl') ...[
                        uploadCard(
                          title: 'Upload DL Image (Optional)',
                          image: _dlBlacklistImage,
                          onCamera: () => pickDlImage(ImageSource.camera),
                          onGallery: () => pickDlImage(ImageSource.gallery),
                          extracting: _dlBlacklistExtracting,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _formCtrls['number'],
                          validator: (v) => Validators.validateID(v, type: 'DL Number'),
                          decoration: InputDecoration(
                            labelText: 'DL Number *',
                            border: const OutlineInputBorder(),
                            suffixIcon: actionSuffixDl(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _formCtrls['reason'],
                          validator: (v) => Validators.validateReason(v, fieldName: 'Reason'),
                          decoration: const InputDecoration(
                            labelText: 'Reason for Blacklisting *',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _formCtrls['name'],
                          decoration: const InputDecoration(
                            labelText: 'Name of Person',
                            border: OutlineInputBorder(),
                            hintText: 'Optional',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _formCtrls['phone'],
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            border: OutlineInputBorder(),
                            hintText: 'Optional',
                          ),
                        ),
                      ] else ...[
                        uploadCard(
                          title: 'Upload RC Image',
                          image: _rcBlacklistImage,
                          onCamera: () => pickRcImage(ImageSource.camera),
                          onGallery: () => pickRcImage(ImageSource.gallery),
                          extracting: _rcBlacklistExtracting,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _formCtrls['number'],
                          validator: (v) => Validators.validateID(v, type: 'RC Number'),
                          decoration: InputDecoration(
                            labelText: 'RC / Vehicle Number',
                            border: const OutlineInputBorder(),
                            suffixIcon: actionSuffixRc(),
                          ),
                          textCapitalization: TextCapitalization.characters,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: _rcBlacklistExtracting
                                ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.search),
                            label: Text(_rcBlacklistExtracting
                                ? 'Fetching details...' : 'Fetch Vehicle Details'),
                            onPressed: _rcBlacklistExtracting
                                ? null
                                : () async {
                              final rcNum = _formCtrls['number']?.text.trim() ?? '';
                              if (rcNum.isEmpty) {
                                _showErrorSnackBar('Please enter an RC number first.');
                                return;
                              }
                              final requestId = ++_rcBlacklistRequestId;
                              _rcBlacklistCancelled = false;
                              if (mounted) setState(() => _rcBlacklistExtracting = true);
                              setModalState(() {});
                              try {
                                final detailsResp = await _api.getVehicleDetails(rcNum);
                                if (!mounted || requestId != _rcBlacklistRequestId || _rcBlacklistCancelled) return;
                                if (detailsResp['ok'] == true) {
                                  final data = detailsResp['data'];
                                  if (mounted) setState(() {
                                    _populateRcDetails(data);
                                    _rcBlacklistExtracting = false;
                                  });
                                  setModalState(() {});
                                  _showInfoSnackBar('Vehicle details auto-filled successfully.');
                                } else {
                                  if (mounted) setState(() => _rcBlacklistExtracting = false);
                                  setModalState(() {});
                                  _showErrorSnackBar(
                                      detailsResp['message']?.toString() ??
                                          'Could not fetch vehicle details.');
                                }
                              } catch (e) {
                                if (mounted) setState(() => _rcBlacklistExtracting = false);
                                setModalState(() {});
                                devLog('Manual RC fetch error: $e');
                                _showErrorSnackBar(SafeError.format(e, fallback: 'Could not fetch vehicle details. Please check the RC number and try again.'));
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _formCtrls['reason'],
                          validator: (v) => Validators.validateReason(v, fieldName: 'Reason'),
                          decoration: const InputDecoration(
                            labelText: 'Reason for Blacklisting',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 16),
                        Text('Auto-filled vehicle details',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        autoField('Owner Name', _formCtrls['owner']!),
                        const SizedBox(height: 12),
                        autoField('Maker Class', _formCtrls['maker']!),
                        const SizedBox(height: 12),
                        autoField('Vehicle Class', _formCtrls['vehicle']!),
                        const SizedBox(height: 12),
                        autoField('Wheel Type', _formCtrls['wheel']!),
                        const SizedBox(height: 12),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text('More auto-filled details'),
                          childrenPadding: const EdgeInsets.only(bottom: 8),
                          children: [
                            autoField('Father Name', _formCtrls['father']!),
                            const SizedBox(height: 12),
                            autoField('Address', _formCtrls['address']!),
                            const SizedBox(height: 12),
                            autoField('Fuel Used', _formCtrls['fuel']!),
                            const SizedBox(height: 12),
                            autoField('Body Type', _formCtrls['body']!),
                            const SizedBox(height: 12),
                            autoField('Manufacture Date', _formCtrls['mfg']!),
                            const SizedBox(height: 12),
                            autoField('Chassis Number', _formCtrls['chassis']!),
                            const SizedBox(height: 12),
                            autoField('Engine Number', _formCtrls['engine']!),
                            const SizedBox(height: 12),
                            autoField('Registration Date', _formCtrls['regn_date']!),
                            const SizedBox(height: 12),
                            autoField('Valid Upto', _formCtrls['valid_upto']!),
                            const SizedBox(height: 12),
                            autoField('Tax Paid', _formCtrls['tax_paid']!),
                          ],
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    if (type != 'face')
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue.shade700, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                type == 'dl'
                                    ? 'Optionally upload a DL image to auto-fill the DL number. Fill in the reason (required) and optionally the person\'s name and phone number.'
                                    : 'Optionally upload an RC image to auto-fill the vehicle number. You can also type it and tap "Fetch Vehicle Details". Only the reason is required.',
                                style: TextStyle(color: Colors.blue.shade800, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submittingBlacklist
                            ? null
                            : () async {
                          if (type == 'face') {
                            await _addFaceSuspect();
                          } else {
                            await _addToBlacklist();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _submittingBlacklist
                            ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Text('Add to Blacklist'),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEntryDetails(BuildContext parentContext, Map<String, dynamic> item,
      {required String type}) {
    String? _getImageUrl(Map<String, dynamic> it) {
      final keys = ['photo', 'image', 'photoUrl', 'image_url', 'photo_url'];
      for (final k in keys) {
        final v = it[k];
        if (v != null && v is String && v.trim().isNotEmpty) return v;
      }
      if (it['images'] is List && (it['images'] as List).isNotEmpty) {
        final first = (it['images'] as List).first;
        if (first is String && first.isNotEmpty) return first;
        if (first is Map && first['url'] is String) return first['url'];
      }
      return null;
    }

    Widget row(String label, String? value) {
      if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 120,
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ]),
      );
    }

    final imageUrl = _getImageUrl(item);
    showDialog(
      context: parentContext,
      builder: (ctx) {
        bool _isRemoving = false;
        return StatefulBuilder(builder: (ctx2, setState2) {
          final List<Widget> content = [];
          final idVal = (item['id'] is Map)
              ? (item['id']['\$oid'] ?? item['id'].toString())
              : item['id']?.toString() ?? '';
          if (idVal.isNotEmpty) content.add(row('ID', idVal));

          if (type == 'dl') {
            content.add(row('DL Number', (item['dl_number'] ?? item['dl'] ?? '').toString()));
            content.add(row('Name', (item['name'] ?? '').toString()));
            content.add(row('DOB', (item['dob'] ?? '').toString()));
            content.add(row('Blood Group', (item['blood_group'] ?? '').toString()));
            content.add(row('Organ Donor', (item['organ_donor'] ?? '').toString()));
            content.add(row('Issue Date', (item['issue_date'] ?? '').toString()));
            content.add(row('Valid Upto', (item['validity'] ?? item['valid_upto'] ?? '').toString()));
            content.add(row('Father', (item['father_name'] ?? '').toString()));
            content.add(row('Phone', (item['phone_number'] ?? '').toString()));
            content.add(row('Address', (item['address'] ?? '').toString()));
            content.add(row('Crime', (item['crime_involved'] ?? item['reason'] ?? '').toString()));
            content.add(row('Verification', (item['verification'] ?? item['Verification'] ?? '').toString()));
          } else {
            content.add(row('RC / Regn', (item['regn_number'] ?? item['rc_number'] ?? item['regnNo'] ?? '').toString()));
            content.add(row('Owner', (item['owner_name'] ?? item['owner'] ?? '').toString()));
            content.add(row('Father', (item['father_name'] ?? '').toString()));
            content.add(row('Address', (item['address'] ?? '').toString()));
            content.add(row('Maker', (item['maker_class'] ?? '').toString()));
            content.add(row('Vehicle Class', (item['vehicle_class'] ?? '').toString()));
            content.add(row('Wheel Type', (item['wheel_type'] ?? item['wheel'] ?? '').toString()));
            content.add(row('Fuel', (item['fuel_used'] ?? '').toString()));
            content.add(row('Body Type', (item['type_of_body'] ?? '').toString()));
            content.add(row('Mfg', (item['mfg_month_year'] ?? '').toString()));
            content.add(row('Chassis', (item['chassis_number'] ?? '').toString()));
            content.add(row('Engine', (item['engine_number'] ?? '').toString()));
            content.add(row('Regn Date', (item['registration_date'] ?? '').toString()));
            content.add(row('Valid Upto', (item['valid_upto'] ?? '').toString()));
            content.add(row('Tax Paid', (item['tax_paid'] ?? '').toString()));
            content.add(row('Crime', (item['crime_involved'] ?? item['reason'] ?? '').toString()));
            content.add(row('Verification', (item['verification'] ?? item['Verification'] ?? '').toString()));
          }

          final filtered = content.where((w) => w is! SizedBox).toList();

          return AlertDialog(
            title: Text('${type.toUpperCase()} Details'),
            content: SizedBox(
              width: MediaQuery.of(ctx).size.width * 0.8,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageUrl != null) ...[
                      GestureDetector(
                        onTap: () {
                          Navigator.of(ctx2).push(MaterialPageRoute(builder: (_) {
                            return Scaffold(
                              appBar: AppBar(title: const Text('Photo')),
                              body: Center(child: InteractiveViewer(child: Image.network(imageUrl))),
                            );
                          }));
                        },
                        child: Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(imageUrl,
                                height: MediaQuery.of(ctx).size.height * 0.2,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) =>
                                const Icon(Icons.broken_image, size: 64)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    ...filtered,
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: _isRemoving ? null : () => Navigator.of(ctx2).pop(),
                child: const Text('Close'),
              ),
              if (widget.role == 'superadmin')
                OutlinedButton.icon(
                  icon: _isRemoving
                      ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                      : const Icon(Icons.check, color: Colors.red),
                  label: const Text('Remove from blacklist',
                      style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red, width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  onPressed: _isRemoving
                      ? null
                      : () async {
                    final confirm = await showDialog<bool>(
                      context: ctx2,
                      builder: (c) => AlertDialog(
                        title: const Text('Confirm Remove'),
                        content: Text(
                            'Mark this ${type.toUpperCase()} as valid (remove from blacklist)?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(c).pop(false),
                              child: const Text('Cancel')),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.red, width: 1.5),
                                foregroundColor: Colors.red),
                            onPressed: () => Navigator.of(c).pop(true),
                            child: const Text('Confirm'),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    setState(() => _isRemoving = true);

                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      useRootNavigator: true,
                      builder: (_) => const Center(child: CircularProgressIndicator()),
                    );

                    final ok = await _markValid(type, idVal);

                    try {
                      if (Navigator.of(context, rootNavigator: true).canPop()) {
                        Navigator.of(context, rootNavigator: true).pop();
                      }
                    } catch (_) {}

                    setState(() => _isRemoving = false);
                    if (ok) {
                      Navigator.of(ctx2).pop();
                    }
                  },
                ),
            ],
          );
        });
      },
    );
  }

  void _showSuspectDetails(BuildContext parentContext, String name, String uniqueId, String imageB64) {
    Widget _buildImage({double? height, BoxFit fit = BoxFit.cover}) {
      if (imageB64.isEmpty) return const Icon(Icons.person, size: 100);
      try {
        final bytes = base64Decode(imageB64);
        return Image.memory(bytes, height: height, fit: fit,
            errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 100));
      } catch (_) {
        return const Icon(Icons.broken_image, size: 100);
      }
    }

    showDialog(
      context: parentContext,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx2, setState2) {
          return AlertDialog(
            title: Text('Suspect: $name'),
            content: SizedBox(
              width: MediaQuery.of(ctx).size.width * 0.8,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: imageB64.isNotEmpty
                            ? () {
                          Navigator.of(ctx2).push(MaterialPageRoute(builder: (_) {
                            // Decode bytes once outside the builder
                            late final Uint8List imageBytes;
                            bool decodeOk = false;
                            try {
                              imageBytes = base64Decode(imageB64);
                              decodeOk = true;
                            } catch (_) {}

                            return Scaffold(
                              backgroundColor: Colors.black,
                              appBar: AppBar(
                                backgroundColor: Colors.black,
                                iconTheme: const IconThemeData(color: Colors.white),
                                title: Text(name, style: const TextStyle(color: Colors.white)),
                              ),
                              body: decodeOk
                                  ? InteractiveViewer(
                                // Allow zooming beyond the widget bounds without clipping
                                boundaryMargin: const EdgeInsets.all(double.infinity),
                                minScale: 0.5,
                                maxScale: 5.0,
                                child: Center(
                                  child: Image.memory(
                                    imageBytes,
                                    // Fill width; height auto-scales to maintain aspect ratio
                                    width: double.infinity,
                                    fit: BoxFit.contain,
                                    errorBuilder: (c, e, s) => const Icon(
                                        Icons.broken_image, color: Colors.white, size: 80),
                                  ),
                                ),
                              )
                                  : const Center(
                                  child: Icon(Icons.broken_image,
                                      color: Colors.white, size: 80)),
                            );
                          }));
                        }
                            : null,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _buildImage(height: MediaQuery.of(ctx).size.height * 0.25),
                        ),
                      ),
                    ),
                    if (imageB64.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Center(
                          child: Text('Tap photo to view full screen',
                              style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text('Name: $name',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('Unique ID: $uniqueId',
                        style: const TextStyle(fontSize: 13, color: Colors.black54)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx2).pop(), child: const Text('Close')),
              if (widget.role == 'superadmin')
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  label: const Text('Remove suspect', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final confirmed = await _showConfirmDialog(
                        'Are you sure you want to delete $name from the suspect list?');
                    if (confirmed != true) return;

                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      useRootNavigator: true,
                      builder: (_) => const Center(child: CircularProgressIndicator()),
                    );

                    bool success = false;
                    try {
                      success = await _deleteFaceSuspectApi(name);

                      try {
                        if (Navigator.of(context, rootNavigator: true).canPop()) {
                          Navigator.of(context, rootNavigator: true).pop();
                        }
                      } catch (_) {}

                      if (success && mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Suspect deleted successfully!'),
                            backgroundColor: Colors.green));
                        if (mounted) {
                          setState(() {
                            _faceMap.remove(uniqueId);
                            _faceTotal = _faceMap.length;
                          });
                        }
                        Navigator.of(ctx2).pop();
                      } else {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('Failed to delete suspect'),
                              backgroundColor: Colors.red));
                        }
                      }
                    } catch (e) {
                      try {
                        if (Navigator.of(context, rootNavigator: true).canPop()) {
                          Navigator.of(context, rootNavigator: true).pop();
                        }
                      } catch (_) {}
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(SafeError.format(e, fallback: 'Failed to delete suspect. Please try again.')), backgroundColor: Colors.red));
                      }
                    }
                  },
                ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final TextEditingController activeSearchController = _tabController.index == 0
        ? _dlSearchCtrl
        : _tabController.index == 1
        ? _rcSearchCtrl
        : _faceSearchCtrl;

    final displayedDlCount = _semanticFilterEntries(_dlList, _dlSearchCtrl.text.trim()).length;
    final displayedRcCount = _semanticFilterEntries(_rcList, _rcSearchCtrl.text.trim()).length;
    final displayedFaceCount = _faceSearchCtrl.text.trim().isEmpty
        ? _faceMap.length
        : _faceMap.values.where(
          (v) => (v['name'] ?? '').toString().toLowerCase().contains(_faceSearchCtrl.text.trim().toLowerCase()),
    ).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Blacklist Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = true;
              });
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_isSearching ? 110.0 : 48.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isSearching)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: TextField(
                    controller: activeSearchController,
                    decoration: InputDecoration(
                      hintText: _tabController.index == 0
                          ? 'Search DL number...'
                          : _tabController.index == 1
                          ? 'Search RC number...'
                          : 'Search suspect name...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _isSearching = false;
                            _dlSearchCtrl.clear();
                            _rcSearchCtrl.clear();
                            _faceSearchCtrl.clear();
                            _fetchDLs(page: 1);
                            _fetchRCs(page: 1);
                            _fetchFaces();
                          });
                        },
                        tooltip: 'Close search',
                      ),
                      border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(30))),
                      filled: true,
                      fillColor: Colors.grey[200],
                      contentPadding:
                      const EdgeInsets.symmetric(vertical: 0.0, horizontal: 16.0),
                    ),
                    onSubmitted: (_) {
                      if (_tabController.index == 0) {
                        _fetchDLs(page: 1);
                      } else if (_tabController.index == 1)
                        _fetchRCs(page: 1);
                      else
                        _fetchFaces();
                    },
                  ),
                ),
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: 'DL ($displayedDlCount)'),
                  Tab(text: 'RC ($displayedRcCount)'),
                  Tab(text: 'Face ($displayedFaceCount)'),
                ],
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                indicatorWeight: 3.0,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: widget.role == 'superadmin'
          ? FloatingActionButton(
        onPressed: _showAddBottomSheet,
        child: const Icon(Icons.add),
      )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildListContent(_dlList, 'dl', _errorDL, _loadingDL, _dlScroll),
          _buildListContent(_rcList, 'rc', _errorRC, _loadingRC, _rcScroll),
          _buildFaceListContent(_errorFace, _loadingFace, _faceScroll),
        ],
      ),
    );
  }
}