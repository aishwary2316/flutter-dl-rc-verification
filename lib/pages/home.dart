// lib/pages/home.dart

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import '../utils/safe_log.dart';
import '../utils/validators.dart'; // Import Validators
import 'verification.dart'; // <- uses verifyDriverAndShowDialog()
import '../services/api_service.dart';

class HomePageContent extends StatefulWidget {
  const HomePageContent({super.key});

  @override
  State<HomePageContent> createState() => _HomePageContentState();
}

class _HomePageContentState extends State<HomePageContent> {
  final ApiService _apiService = ApiService();
  // ====== Configure Backend / Model URLs HERE ======
  // Leave verify empty if you don't want verify POSTs from the app
  final String _verifyBaseUrl = '';

  List<String> _dlCandidates = [];
  int _dlCandidateIndex = 0;
  int _dlRequestSerial = 0;
  bool _dlRequestCancelled = false;

  int _rcRequestSerial = 0;
  bool _rcRequestCancelled = false;

  Future<void> _extractDlFromService(File file) async {
    final int requestId = ++_dlRequestSerial;
    setState(() {
      _dlExtracting = true;
      _dlRequestCancelled = false;
      _dlCandidates = [];
      _dlCandidateIndex = 0;
      _dlController.text = 'Extracting...';
    });

    try {
      final result = await _apiService.ocrDL(file);

      if (!mounted || requestId != _dlRequestSerial || _dlRequestCancelled) {
        return;
      }

      if (result['ok'] == true) {
        final candidates = _extractDlCandidates(result);

        if (candidates.isNotEmpty) {
          setState(() {
            _dlCandidates = candidates;
            _dlCandidateIndex = 0;
            if (_dlController.text.trim().isEmpty || _dlController.text.trim() == 'Extracting...') {
              _dlController.text = _dlCandidates.first;
            }
          });
        } else {
          final text = (result['extracted_text'] ?? '').toString().trim();
          if (text.isNotEmpty) {
            setState(() {
              _dlCandidates = [text];
              _dlCandidateIndex = 0;
              if (_dlController.text.trim().isEmpty || _dlController.text.trim() == 'Extracting...') {
                _dlController.text = text;
              }
            });
          } else {
            if (_dlController.text.trim() == 'Extracting...') {
              _dlController.clear();
            }
            _showErrorSnackBar('Could not extract DL number from the image.');
          }
        }
      } else {
        if (_dlController.text.trim() == 'Extracting...') {
          _dlController.clear();
        }
        _showErrorSnackBar(result['message'] ?? 'DL OCR failed');
      }
    } catch (e) {
      if (!mounted || requestId != _dlRequestSerial || _dlRequestCancelled) {
        return;
      }
      if (_dlController.text.trim() == 'Extracting...') {
        _dlController.clear();
      }
      _showErrorSnackBar('DL OCR error: $e');
    } finally {
      if (mounted && requestId == _dlRequestSerial) {
        setState(() => _dlExtracting = false);
      }
    }
  }

  Future<void> _extractRcFromService(File file) async {
    final int requestId = ++_rcRequestSerial;
    setState(() {
      _rcExtracting = true;
      _rcRequestCancelled = false;
      _rcController.text = 'Extracting...';
    });

    try {
      final result = await _apiService.ocrRC(file);

      if (!mounted || requestId != _rcRequestSerial || _rcRequestCancelled) {
        return;
      }

      if (result['ok'] == true) {
        final text = _normalizeOcrText((result['extracted_text'] ?? '').toString().trim());
        if (text.isNotEmpty) {
          if (_rcController.text.trim().isEmpty || _rcController.text.trim() == 'Extracting...') {
            _rcController.text = text;
          }
        } else {
          if (_rcController.text.trim() == 'Extracting...') {
            _rcController.clear();
          }
          _showErrorSnackBar('Could not extract vehicle number from the image.');
        }
      } else {
        if (_rcController.text.trim() == 'Extracting...') {
          _rcController.clear();
        }
        _showErrorSnackBar(result['message'] ?? 'RC OCR failed');
      }
    } catch (e) {
      if (!mounted || requestId != _rcRequestSerial || _rcRequestCancelled) {
        return;
      }
      if (_rcController.text.trim() == 'Extracting...') {
        _rcController.clear();
      }
      _showErrorSnackBar('RC OCR error: $e');
    } finally {
      if (mounted && requestId == _rcRequestSerial) {
        setState(() => _rcExtracting = false);
      }
    }
  }

  List<String> _extractDlCandidates(dynamic result) {
    final candidates = <String>[];

    void addCandidate(dynamic value) {
      final raw = value?.toString().trim();
      if (raw != null && raw.isNotEmpty) {
        final text = _normalizeOcrText(raw);
        if (text.isNotEmpty && !candidates.contains(text)) {
          candidates.add(text);
        }
      }
    }

    final data = result is Map ? result['data'] : null;
    if (data is Map) {
      final dlNumbers = data['dl_numbers'];
      if (dlNumbers is List) {
        for (final item in dlNumbers) {
          addCandidate(item);
        }
      }
    }

    if (candidates.isEmpty) {
      final extractedRaw = result is Map ? result['extracted_text'] : null;
      final extracted = extractedRaw?.toString().trim() ?? '';
      if (extracted.isNotEmpty) {
        for (final part in extracted.split(',')) {
          addCandidate(part);
        }
        if (candidates.isEmpty) {
          addCandidate(extracted);
        }
      }
    }

    return candidates;
  }

  void _cancelDlExtraction() {
    if (!_dlExtracting) return;
    setState(() {
      _dlRequestCancelled = true;
      _dlRequestSerial++;
      _dlExtracting = false;
      _dlCandidates = [];
      _dlCandidateIndex = 0;
      if (_dlController.text.trim() == 'Extracting...') {
        _dlController.clear();
      }
    });
  }

  void _cancelRcExtraction() {
    if (!_rcExtracting) return;
    setState(() {
      _rcRequestCancelled = true;
      _rcRequestSerial++;
      _rcExtracting = false;
      if (_rcController.text.trim() == 'Extracting...') {
        _rcController.clear();
      }
    });
  }

  void _cycleDlCandidate() {
    if (_dlCandidates.length <= 1) return;
    setState(() {
      _dlCandidateIndex = (_dlCandidateIndex + 1) % _dlCandidates.length;
      _dlController.text = _dlCandidates[_dlCandidateIndex];
      _dlController.selection = TextSelection.collapsed(offset: _dlController.text.length);
    });
  }

  bool _isAllowedImageFilename(String filename) {
    final ext = p.extension(filename).toLowerCase();
    return ext == '.jpg' ||
        ext == '.jpeg' ||
        ext == '.png' ||
        ext == '.webp' ||
        ext == '.bmp' ||
        ext == '.gif';
  }


  String _normalizeOcrText(String text) {
    return text.replaceAll(RegExp(r'\s+'), '').toUpperCase();
  }

  Widget? _buildDlSuffixIcon() {
    if (_dlExtracting) {
      return IconButton(
        tooltip: 'Cancel extraction',
        icon: const Icon(Icons.close),
        onPressed: _cancelDlExtraction,
      );
    }

    if (_dlCandidates.length > 1) {
      final countLabel = '${_dlCandidateIndex + 1}/${_dlCandidates.length}';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  countLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Show next DL candidate',
            icon: const Icon(Icons.swap_horiz),
            onPressed: _cycleDlCandidate,
          ),
        ],
      );
    }

    if (_lastDlXFile != null || _lastDlPFile != null) {
      return IconButton(
        tooltip: 'Refresh DL OCR',
        icon: const Icon(Icons.refresh),
        onPressed: () async {
          File? dlFile;
          if (!kIsWeb) {
            if (_lastDlXFile != null && _lastDlXFile!.path.isNotEmpty) {
              dlFile = File(_lastDlXFile!.path);
            } else if (_lastDlPFile != null && _lastDlPFile!.path != null && _lastDlPFile!.path!.isNotEmpty) {
              dlFile = File(_lastDlPFile!.path!);
            }
          }
          if (dlFile == null) {
            _showErrorSnackBar('Unable to reload the selected DL image.');
            return;
          }
          _dlController.clear();
          await _extractDlFromService(dlFile);
        },
      );
    }

    return null;
  }

  Widget? _buildRcSuffixIcon() {
    if (_rcExtracting) {
      return IconButton(
        tooltip: 'Cancel extraction',
        icon: const Icon(Icons.close),
        onPressed: _cancelRcExtraction,
      );
    }

    if (_lastRcXFile != null || _lastRcPFile != null) {
      return IconButton(
        tooltip: 'Refresh RC OCR',
        icon: const Icon(Icons.refresh),
        onPressed: _refreshRcExtraction,
      );
    }

    return null;
  }

  // OCR model endpoints (use the exact working paths)

  // RC API endpoint

  // Field names used when sending multipart to each OCR endpoint.
  // ================================================

  // App theme colors to match government portal
  static const Color _primaryBlue = Color(0xFF1E3A8A);
  static const Color _lightGray = Color(0xFFF8FAFC);
  static const Color _borderGray = Color(0xFFE2E8F0);
  static const Color _textGray = Color(0xFF64748B);

  // Controllers & state for the Home UI
  final TextEditingController _dlController = TextEditingController();
  final TextEditingController _rcController = TextEditingController();

  // Form Key for Validation
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  String? _dlImageName;
  String? _rcImageName;
  String? _driverImageName;

  // Keep references to actual picked files so we can attach them later
  XFile? _lastDlXFile;
  PlatformFile? _lastDlPFile;

  XFile? _lastRcXFile;
  PlatformFile? _lastRcPFile;

  XFile? _lastDriverXFile;
  PlatformFile? _lastDriverPFile;

  // Loading / extracting states
  bool _isVerifying = false;
  bool _dlExtracting = false;
  bool _rcExtracting = false;

  final ImagePicker _imagePicker = ImagePicker();

  @override
  void dispose() {
    _dlController.dispose();
    _rcController.dispose();
    super.dispose();
  }

  // Helper to know if we can enable the Verify button
  bool get _hasInput {
    if (_dlController.text.trim().isNotEmpty) return true;
    if (_rcController.text.trim().isNotEmpty) return true;
    if (_lastDriverXFile != null) return true;
    if (_lastDriverPFile != null) return true;
    return false;
  }

  // ----------------- Pick handlers (camera/gallery/file) --------------

  Future<void> _pickDlImage() async {
    _showImageSourceOptions(
      title: 'Select Driving License',
      onCamera: () async {
        final XFile? picked = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 85);
        if (picked != null) {
          // SECURITY: Validate Magic Bytes
          if (!kIsWeb && !await Validators.isValidImage(File(picked.path))) {
            _showErrorSnackBar('Security Error: Invalid file format.');
            return;
          }
          setState(() {
            _dlImageName = picked.name;
            _lastDlXFile = picked;
            _lastDlPFile = null;
            _dlCandidates = [];
            _dlCandidateIndex = 0;
            _dlController.clear();
          });

          if (!kIsWeb) {
            await _extractDlFromService(File(picked.path));
          }
        }
      },
      onGallery: () async {
        final XFile? picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (picked != null) {
          // SECURITY: Validate Magic Bytes
          if (!kIsWeb && !await Validators.isValidImage(File(picked.path))) {
            _showErrorSnackBar('Security Error: Invalid file format.');
            return;
          }
          setState(() {
            _dlImageName = picked.name;
            _lastDlXFile = picked;
            _lastDlPFile = null;
            _dlCandidates = [];
            _dlCandidateIndex = 0;
            _dlController.clear();
          });

          if (!kIsWeb) {
            await _extractDlFromService(File(picked.path));
          }
        }
      },
      onFile: () async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          final pfile = result.files.single;

          if (!_isAllowedImageFilename(pfile.name)) {
            _showErrorSnackBar('Please choose a JPG/PNG image for OCR.');
            return;
          }

          // SECURITY: Validate Magic Bytes (if file path exists)
          if (!kIsWeb && pfile.path != null) {
            if (!await Validators.isValidImage(File(pfile.path!))) {
              _showErrorSnackBar('Security Error: Invalid image file.');
              return;
            }
          }

          setState(() {
            _dlImageName = pfile.name;
            _lastDlPFile = pfile;
            _lastDlXFile = null;
            _dlCandidates = [];
            _dlCandidateIndex = 0;
            _dlController.clear();
          });
          if (pfile.path != null && pfile.path!.isNotEmpty) {
            await _extractDlFromService(File(pfile.path!));
          }
        }
      },
    );
  }

  Future<void> _pickRcImage() async {
    _showImageSourceOptions(
      title: 'Select Vehicle Registration (RC)',
      onCamera: () async {
        final XFile? picked = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 85);
        if (picked != null) {
          // SECURITY: Validate Magic Bytes
          if (!kIsWeb && !await Validators.isValidImage(File(picked.path))) {
            _showErrorSnackBar('Security Error: Invalid file format.');
            return;
          }
          setState(() {
            _rcImageName = picked.name;
            _lastRcXFile = picked;
            _lastRcPFile = null;
            _rcController.clear();
          });
          if (!kIsWeb) {
            await _extractRcFromService(File(picked.path));
          }
        }
      },
      onGallery: () async {
        final XFile? picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (picked != null) {
          // SECURITY: Validate Magic Bytes
          if (!kIsWeb && !await Validators.isValidImage(File(picked.path))) {
            _showErrorSnackBar('Security Error: Invalid file format.');
            return;
          }
          setState(() {
            _rcImageName = picked.name;
            _lastRcXFile = picked;
            _lastRcPFile = null;
            _rcController.clear();
          });
          if (!kIsWeb) {
            await _extractRcFromService(File(picked.path));
          }
        }
      },
      onFile: () async {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        );
        if (result != null && result.files.isNotEmpty) {
          final pfile = result.files.single;

          if (!_isAllowedImageFilename(pfile.name)) {
            _showErrorSnackBar('Please choose a JPG/PNG image for OCR.');
            return;
          }

          // SECURITY: Validate Magic Bytes if path exists and it claims to be an image
          if (!kIsWeb && pfile.path != null) {
            if (!await Validators.isValidImage(File(pfile.path!))) {
              _showErrorSnackBar('Security Error: Invalid image file.');
              return;
            }
          }
          setState(() {
            _rcImageName = pfile.name;
            _lastRcPFile = pfile;
            _lastRcXFile = null;
            _rcController.clear();
          });
          if (pfile.path != null && pfile.path!.isNotEmpty) {
            await _extractRcFromService(File(pfile.path!));
          }
        }
      },
    );
  }

  // Re-run RC extraction by re-sending the last-picked RC image to the server.
  Future<void> _refreshRcExtraction() async {
    if (_lastRcXFile == null && _lastRcPFile == null) {
      _showInfoSnackBar('No vehicle image selected to refresh.');
      return;
    }

    File? rcFile;
    if (!kIsWeb) {
      if (_lastRcXFile != null && _lastRcXFile!.path.isNotEmpty) {
        rcFile = File(_lastRcXFile!.path);
      } else if (_lastRcPFile != null && _lastRcPFile!.path != null && _lastRcPFile!.path!.isNotEmpty) {
        rcFile = File(_lastRcPFile!.path!);
      }
    }

    if (rcFile == null) {
      _showErrorSnackBar('Unable to reload the selected RC image.');
      return;
    }

    _rcController.clear();
    await _extractRcFromService(rcFile);
  }

  Future<void> _pickDriverImage() async {
    _showImageSourceOptions(
      title: 'Select Driver Image',
      onCamera: () async {
        final XFile? picked = await _imagePicker.pickImage(source: ImageSource.camera, imageQuality: 85);
        if (picked != null) {
          // SECURITY: Validate Magic Bytes
          if (!kIsWeb && !await Validators.isValidImage(File(picked.path))) {
            _showErrorSnackBar('Security Error: Invalid file format.');
            return;
          }
          setState(() {
            _driverImageName = picked.name;
            _lastDriverXFile = picked;
            _lastDriverPFile = null;
          });
        }
      },
      onGallery: () async {
        final XFile? picked = await _imagePicker.pickImage(source: ImageSource.gallery, imageQuality: 85);
        if (picked != null) {
          // SECURITY: Validate Magic Bytes
          if (!kIsWeb && !await Validators.isValidImage(File(picked.path))) {
            _showErrorSnackBar('Security Error: Invalid file format.');
            return;
          }
          setState(() {
            _driverImageName = picked.name;
            _lastDriverXFile = picked;
            _lastDriverPFile = null;
          });
        }
      },
      onFile: () async {
        final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
        if (result != null && result.files.isNotEmpty) {
          final pfile = result.files.single;
          // SECURITY: Validate Magic Bytes
          if (!kIsWeb && pfile.path != null) {
            if (!await Validators.isValidImage(File(pfile.path!))) {
              _showErrorSnackBar('Security Error: Invalid image file.');
              return;
            }
          }
          setState(() {
            _driverImageName = pfile.name;
            _lastDriverPFile = pfile;
            _lastDriverXFile = null;
          });
        }
      },
    );
  }

  // ----------------- Bottom sheet (minimal) ----------------------------
  void _showImageSourceOptions({
    required String title,
    required VoidCallback onCamera,
    required VoidCallback onGallery,
    required VoidCallback onFile,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.camera_alt),
                  title: const Text('Take Photo (Camera)'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onCamera();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Pick from Gallery'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onGallery();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('Choose image file'),
                  subtitle: const Text('Images only'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onFile();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------- Verification: delegate to verification.dart ----------
  Future<void> _handleVerification() async {
    // 1. FORM VALIDATION (Regex)
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) {
      return;
    }

    final dlNumber = _dlController.text.trim();
    final rcNumber = _rcController.text.trim();

    // Build driverFile (if any) - only on non-web platforms we can build a dart:io File
    File? driverFile;
    if (!kIsWeb) {
      if (_lastDriverXFile != null && _lastDriverXFile!.path.isNotEmpty) {
        driverFile = File(_lastDriverXFile!.path);
      } else if (_lastDriverPFile != null && _lastDriverPFile!.path != null && _lastDriverPFile!.path!.isNotEmpty) {
        driverFile = File(_lastDriverPFile!.path!);
      }
    } else {
      // On web: cannot convert picked file into dart:io File.
      // If only driver image is selected on web, inform user that face verification via file path is not supported.
      if (dlNumber.isEmpty && rcNumber.isEmpty && (_lastDriverXFile != null || _lastDriverPFile != null)) {
        _showErrorSnackBar('Face verification from web is currently unsupported. Try from a mobile device or enter DL/RC numbers.');
        return;
      }
      // If DL/RC present, proceed without driverFile (face verification skipped in backend call)
      driverFile = null;
    }

    if (dlNumber.isEmpty && rcNumber.isEmpty && driverFile == null) {
      _showErrorSnackBar('Please provide a DL number, a Vehicle number, or a Driver Image to verify.');
      return;
    }

    setState(() => _isVerifying = true);

    try {
      await verifyDriverAndShowDialog(
        context,
        dlNumber: dlNumber.isNotEmpty ? dlNumber : null,
        rcNumber: rcNumber.isNotEmpty ? rcNumber : null,
        driverImageFile: driverFile,
        location: 'Toll-Plaza-1',
        tollgate: 'Gate-A',
      );
    } catch (e) {
      _showErrorSnackBar('An error occurred during verification: $e');
    } finally {
      setState(() {
        _isVerifying = false;
        // Reset selected names and file references (keep extracted text in controllers so user can edit if desired)
        _dlImageName = null;
        _rcImageName = null;
        _driverImageName = null;
        _lastDlXFile = _lastDlPFile = null;
        _lastRcXFile = _lastRcPFile = null;
        _lastDriverXFile = _lastDriverPFile = null;
      });
    }
  }

  // ----------------- Driver image helpers for preview -----------------

  /// Load driver image bytes from whichever source is available.
  Future<Uint8List?> _loadDriverImageBytes() async {
    try {
      if (_lastDriverPFile != null) {
        if (_lastDriverPFile!.bytes != null) return _lastDriverPFile!.bytes;
        if (_lastDriverPFile!.path != null && _lastDriverPFile!.path!.isNotEmpty) {
          return await File(_lastDriverPFile!.path!).readAsBytes();
        }
      }

      if (_lastDriverXFile != null) {
        // On native platforms xfile.path is usually available
        if (!kIsWeb && _lastDriverXFile!.path.isNotEmpty) {
          return await File(_lastDriverXFile!.path).readAsBytes();
        }
        // On web or fallback, read bytes from XFile
        return await _lastDriverXFile!.readAsBytes();
      }
    } catch (e) {
      devLog('[_loadDriverImageBytes] error: $e');
    }
    return null;
  }

  /// Show fullscreen preview of driver image (tappable thumbnail opens this).
  void _openFullScreenDriverPreview() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(0),
          backgroundColor: Colors.black,
          child: ConstrainedBox( // Responsive container for the image
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(ctx).size.width * 0.9,
              maxHeight: MediaQuery.of(ctx).size.height * 0.9,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: FutureBuilder<Uint8List?>(
                    future: _loadDriverImageBytes(),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Colors.white));
                      }
                      if (!snap.hasData || snap.data == null) {
                        return const Center(child: Text('Unable to load image', style: TextStyle(color: Colors.white)));
                      }
                      return InteractiveViewer(
                        maxScale: 5.0,
                        child: Center(
                          child: Image.memory(
                            snap.data!,
                            fit: BoxFit.contain,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Close button top-right
                Positioned(
                  top: 28,
                  right: 16,
                  child: SafeArea(
                    child: CircleAvatar(
                      backgroundColor: Colors.black45,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ----------------- Snackbars ----------------------------------------
  void _showErrorSnackBar(String message) {
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ----------------- Build UI (kept same & minimal) -------------------
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final double horizontalPadding = screenWidth > 600 ? screenWidth * 0.1 : 16.0;

    return Container(
      color: _lightGray,
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Header section with government branding
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'Driving License and Vehicle Registration Certificate Verification Portal',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _primaryBlue,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Main form container
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              child: Form(
                key: _formKey,
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Driving License Section
                      _buildSectionHeader(
                        icon: Icons.credit_card,
                        title: 'Upload Driving License',
                        subtitle: 'Upload your driving license document',
                      ),
                      const SizedBox(height: 16),

                      _buildFileUploadCard(
                        label: 'Choose Driving License File',
                        fileName: _dlImageName,
                        onTap: _pickDlImage,
                        icon: Icons.upload_file,
                        isDriver: false,
                      ),

                      const SizedBox(height: 12),

                      _buildTextInput(
                        controller: _dlController,
                        label: 'Driving License Number',
                        hint: _dlExtracting ? 'Extracting...' : 'Select image or enter manually',
                        prefixIcon: Icons.confirmation_number,
                        enabled: true,
                        readOnly: _dlExtracting,
                        suffixIconWidget: _buildDlSuffixIcon(),
                        // VALIDATION: Only check regex if field is populated (optional field logic)
                        validator: (v) => (v != null && v.trim().isNotEmpty)
                            ? Validators.validateID(v, type: 'DL Number')
                            : null,
                      ),

                      const SizedBox(height: 24),

                      // Vehicle Registration Section
                      _buildSectionHeader(
                        icon: Icons.directions_car,
                        title: 'Upload Vehicle Registration Number (Number Plate Number)',
                        subtitle: 'Upload your vehicle registration certificate',
                      ),
                      const SizedBox(height: 16),

                      _buildFileUploadCard(
                        label: 'Choose Vehicle Registration File',
                        fileName: _rcImageName,
                        onTap: _pickRcImage,
                        icon: Icons.upload_file,
                        isDriver: false,
                      ),

                      const SizedBox(height: 12),

                      _buildTextInput(
                        controller: _rcController,
                        label: 'Vehicle Number',
                        hint: _rcExtracting ? 'Extracting...' : 'Select image or enter manually',
                        prefixIcon: Icons.directions_car,
                        enabled: true,
                        readOnly: _rcExtracting,
                        suffixIconWidget: _buildRcSuffixIcon(),
                        // VALIDATION
                        validator: (v) => (v != null && v.trim().isNotEmpty)
                            ? Validators.validateID(v, type: 'Vehicle Number')
                            : null,
                      ),

                      const SizedBox(height: 24),

                      // Driver Image Section
                      _buildSectionHeader(
                        icon: Icons.person,
                        title: 'Upload Driver Image',
                        subtitle: 'Upload a clear photo of the driver',
                      ),
                      const SizedBox(height: 16),

                      _buildFileUploadCard(
                        label: 'Choose Driver Image File',
                        fileName: _driverImageName,
                        onTap: _pickDriverImage,
                        icon: Icons.person_add_alt_1,
                        isDriver: true, // <--- show thumbnail + preview behavior
                      ),

                      const SizedBox(height: 32),

                      // Verify Information Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isVerifying ? null : _handleVerification,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _primaryBlue,
                            foregroundColor: Colors.white,
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            disabledBackgroundColor: Colors.grey.shade400,
                          ),
                          child: _isVerifying
                              ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('Verifying...', style: TextStyle(fontSize: 16)),
                            ],
                          )
                              : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.verified_user, size: 20),
                              SizedBox(width: 8),
                              Text('Verify Information', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Info note
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue.shade600, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'AI-powered verification will extract information from uploaded documents automatically.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _primaryBlue, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: _textGray,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// fileName: display label
  /// isDriver: when true, we render a small thumbnail if driver image is selected and allow tap-to-enlarge
  Widget _buildFileUploadCard({
    required String label,
    required String? fileName,
    required VoidCallback onTap,
    required IconData icon,
    bool isDriver = false,
  }) {
    Widget trailing = const SizedBox.shrink();
    // If this is the driver card and an image is selected, create a small thumbnail
    if (isDriver && (_lastDriverPFile != null || _lastDriverXFile != null)) {
      trailing = GestureDetector(
        onTap: _openFullScreenDriverPreview,
        child: FutureBuilder<Uint8List?>(
          future: _loadDriverImageBytes(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.grey.shade200),
                child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              );
            }
            if (!snap.hasData || snap.data == null) {
              // fallback small icon
              return Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: Colors.grey.shade100),
                child: Icon(Icons.image, color: Colors.grey.shade600),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                snap.data!,
                width: 46,
                height: 46,
                fit: BoxFit.cover,
              ),
            );
          },
        ),
      );
    } else if (fileName != null) {
      trailing = Icon(Icons.check_circle, color: Colors.green.shade600, size: 18);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: _borderGray),
          borderRadius: BorderRadius.circular(8),
          color: fileName != null ? Colors.green.shade50 : _lightGray,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: fileName != null ? Colors.green.shade600 : _textGray,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                fileName ?? label,
                style: TextStyle(
                  fontSize: 14,
                  color: fileName != null ? Colors.green.shade700 : _textGray,
                  fontWeight: fileName != null ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildTextInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData prefixIcon,
    bool enabled = true,
    bool readOnly = false,
    Widget? suffixIconWidget,
    String? Function(String?)? validator, // ADDED VALIDATOR PARAM
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      readOnly: readOnly,
      validator: validator, // PASSED VALIDATOR
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(prefixIcon, size: 18),
        suffixIcon: suffixIconWidget,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _borderGray),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _borderGray),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}