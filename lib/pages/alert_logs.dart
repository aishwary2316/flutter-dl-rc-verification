// lib/pages/alert_logs.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';

enum _Severity { red, orange, none }
enum _ActiveFilter { all, suspicious, systemAlerts, multipleDL }

class AlertLogsPage extends StatefulWidget {
  const AlertLogsPage({super.key});

  @override
  State<AlertLogsPage> createState() => _AlertLogsPageState();
}

class _AlertLogsPageState extends State<AlertLogsPage> {
  final ApiService _api = ApiService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = [];

  final TextEditingController _searchController = TextEditingController();
  String _search = '';
  _ActiveFilter _activeFilter = _ActiveFilter.all;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Robust fetch + normalization (accepts List, Map with 'data', or single Map)
  Future<void> _fetchLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _api.getLogs();

      List<Map<String, dynamic>> normalized = [];

      if (res is List) {
      normalized = _normalizeDataToList(res);
    } else if (res.containsKey('data')) {
      normalized = _normalizeDataToList(res['data']);
    } else    normalized = _normalizeDataToList(res);
  

      setState(() {
        _logs = normalized;
      });
    } catch (e) {
      setState(() {
        _error = 'Error fetching logs: $e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _normalizeDataToList(dynamic data) {
    if (data == null) return [];
    if (data is List) {
      return data.map<Map<String, dynamic>>((e) {
        if (e is Map) return Map<String, dynamic>.from(e);
        return {'entry': e};
      }).toList();
    } else if (data is Map && data['logs'] is List) {
      return (data['logs'] as List).map<Map<String, dynamic>>((e) {
        if (e is Map) return Map<String, dynamic>.from(e);
        return {'entry': e};
      }).toList();
    } else if (data is Map) {
      return [Map<String, dynamic>.from(data)];
    } else {
      return [
        {'data': data}
      ];
    }
  }

  // Image builder supports http(s), data:base64, or plain base64.
  Widget _buildImageWidget(dynamic img, double size, {VoidCallback? onTap}) {
    if (img == null) {
      return CircleAvatar(radius: size / 2, child: Icon(Icons.directions_car, size: size * 0.6));
    }

    try {
      final s = img.toString();

      if (s.startsWith('http') || s.startsWith('https')) {
        return GestureDetector(
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(s, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) {
              return CircleAvatar(radius: size / 2, child: Icon(Icons.directions_car, size: size * 0.6));
            }),
          ),
        );
      }

      if (s.startsWith('data:')) {
        final base64Str = s.split(',').last;
        final bytes = base64Decode(base64Str);
        return GestureDetector(onTap: onTap, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover)));
      }

      if (s.length > 100 && RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(s)) {
        final bytes = base64Decode(s.replaceAll('\n', ''));
        return GestureDetector(onTap: onTap, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover)));
      }
    } catch (_) {
      // fallback
    }

    final label = img.toString();
    return GestureDetector(onTap: onTap, child: CircleAvatar(radius: size / 2, child: Text(label.isNotEmpty ? label[0].toUpperCase() : '?')));
  }

  String _formatTimestamp(dynamic t) {
    if (t == null) return '';
    try {
      if (t is int) {
        DateTime dt = (t.toString().length > 10) ? DateTime.fromMillisecondsSinceEpoch(t) : DateTime.fromMillisecondsSinceEpoch(t * 1000);
        return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';
      } else if (t is String) {
        final parsed = DateTime.tryParse(t);
        if (parsed != null) {
          return '${parsed.year}-${_two(parsed.month)}-${_two(parsed.day)} ${_two(parsed.hour)}:${_two(parsed.minute)}';
        } else {
          // Some servers return weird formats — show raw
          return t;
        }
      } else if (t is DateTime) {
        final dt = t;
        return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';
      }
    } catch (_) {}
    return t.toString();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  // Determine card severity:
  // - RED: alert_type contains 'suspicious' or 'suspect' (except multiple-DL case), driver_status == 'alert', suspicious==true (unless multiple-DL)
  // - ORANGE: scanned_by == 'System Alert' (unless RED), or multiple-DL usage
  // - NONE: otherwise
  _Severity _cardSeverity(Map<String, dynamic> item) {
    final alertType = (item['alert_type'] ?? '').toString().toLowerCase();
    final scannedBy = (item['scanned_by'] ?? '').toString().toLowerCase();
    final reason = (item['description'] ?? item['reason'] ?? item['crime_involved'] ?? '').toString().toLowerCase();
    final driverStatus = (item['driver_status'] ?? item['driverStatus'] ?? '').toString().toLowerCase();

    // Detect multiple DL usage: phrases like "used with 3", "used with 3 or more"
    final multipleDLPattern = RegExp(r'used with\s*\d+|\b3 or more\b|\b\d+\s+or more\b', caseSensitive: false);
    final isMultipleDL = multipleDLPattern.hasMatch(reason);

    // If alert_type explicitly contains 'suspicious' or 'suspect' but it's the multiple-DL case then use ORANGE
    if (alertType.contains('suspicious') || alertType.contains('suspect')) {
      if (isMultipleDL) return _Severity.orange;
      return _Severity.red;
    }

    // driver status explicit alert
    if (driverStatus == 'alert') {
      if (isMultipleDL) return _Severity.orange;
      return _Severity.red;
    }

    // suspicious boolean from server
    final suspiciousFlag = item['suspicious'];
    if (suspiciousFlag == true) {
      if (isMultipleDL) return _Severity.orange;
      return _Severity.red;
    }

    // multiple-DL reason -> ORANGE
    if (isMultipleDL) return _Severity.orange;

    // scanned_by System Alert -> ORANGE (but only if not red / not multiple-dl handled above)
    if (scannedBy == 'system alert' || scannedBy == 'system_alert' || scannedBy == 'systemalert') {
      return _Severity.orange;
    }

    return _Severity.none;
  }

  // Search + filter
  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    bySearch(Map<String, dynamic> item) {
      if (q.isEmpty) return true;
      final dl = (item['dl_number'] ?? item['dl'] ?? item['licenseNumber'] ?? '').toString().toLowerCase();
      final rc = (item['vehicle_number'] ?? item['regn_number'] ?? item['rc_number'] ?? item['rc'] ?? '').toString().toLowerCase();
      final reason = (item['description'] ?? item['reason'] ?? item['crime_involved'] ?? '').toString().toLowerCase();
      final location = (item['location'] ?? '').toString().toLowerCase();
      final scannedBy = (item['scanned_by'] ?? '').toString().toLowerCase();
      final driverName = (item['driver_name'] ?? item['driver'] ?? item['name'] ?? '').toString().toLowerCase();
      return dl.contains(q) || rc.contains(q) || reason.contains(q) || location.contains(q) || scannedBy.contains(q) || driverName.contains(q);
    }

    final list = _logs.where((item) => bySearch(item)).toList();

    // Apply active filter
    if (_activeFilter == _ActiveFilter.all) return list;
    if (_activeFilter == _ActiveFilter.suspicious) return list.where((i) => _cardSeverity(i) == _Severity.red).toList();
    if (_activeFilter == _ActiveFilter.systemAlerts) return list.where((i) => _cardSeverity(i) == _Severity.orange && _isSystemAlert(i)).toList();
    if (_activeFilter == _ActiveFilter.multipleDL) return list.where((i) => _cardSeverity(i) == _Severity.orange && _isMultipleDL(i)).toList();
    return list;
  }

  bool _isMultipleDL(Map<String, dynamic> item) {
    final reason = (item['description'] ?? item['reason'] ?? item['crime_involved'] ?? '').toString().toLowerCase();
    final multipleDLPattern = RegExp(r'used with\s*\d+|\b3 or more\b|\b\d+\s+or more\b', caseSensitive: false);
    return multipleDLPattern.hasMatch(reason);
  }

  bool _isSystemAlert(Map<String, dynamic> item) {
    final scannedBy = (item['scanned_by'] ?? '').toString().toLowerCase();
    return scannedBy == 'system alert' || scannedBy == 'system_alert' || scannedBy == 'systemalert';
  }

  void _showRawJson(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log JSON'),
        content: SingleChildScrollView(child: Text(const JsonEncoder.withIndent('  ').convert(item))),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
          TextButton(
            onPressed: () {
              final jsonStr = const JsonEncoder.withIndent('  ').convert(item);
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON copied to clipboard')));
            },
            child: const Text('Copy JSON'),
          ),
        ],
      ),
    );
  }

  Future<void> _showImageFullscreen(dynamic img) async {
    if (img == null) return;
    Widget content;
    try {
      final s = img.toString();
      if (s.startsWith('http') || s.startsWith('https')) {
        content = InteractiveViewer(child: Image.network(s, fit: BoxFit.contain));
      } else if (s.startsWith('data:')) {
        final base64Str = s.split(',').last;
        final bytes = base64Decode(base64Str);
        content = InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain));
      } else if (s.length > 100 && RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(s)) {
        final bytes = base64Decode(s.replaceAll('\n', ''));
        content = InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain));
      } else {
        content = Center(child: Text(s));
      }
    } catch (e) {
      content = Center(child: Text('Unable to preview image: $e'));
    }

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(8),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9, maxWidth: MediaQuery.of(context).size.width * 0.95),
          child: Column(
            children: [
              Expanded(child: content),
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
            ],
          ),
        ),
      ),
    );
  }

  Color _reasonColor(_Severity sev) => sev == _Severity.red ? Colors.red.shade800 : Colors.orange.shade800;

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF1E3A8A);
    const Color lightGray = Color(0xFFF8FAFC);
    final list = _filtered;

    final total = _logs.length;
    final suspiciousCount = _logs.where((i) => _cardSeverity(i) == _Severity.red).length;
    final systemAlertCount = _logs.where((i) => _cardSeverity(i) == _Severity.orange && _isSystemAlert(i)).length;
    final multipleDLCount = _logs.where((i) => _cardSeverity(i) == _Severity.orange && _isMultipleDL(i)).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Alert Logs'), backgroundColor: primaryBlue),
      backgroundColor: lightGray,
      body: SafeArea(
        child: Column(
          children: [
            // Search bar, filter button, and counters
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search DL / RC / Reason / Location',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _search.isNotEmpty
                            ? IconButton(icon: const Icon(Icons.clear), onPressed: () {
                          _searchController.clear();
                          setState(() => _search = '');
                        })
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<_ActiveFilter>(
                    tooltip: 'Filter logs',
                    icon: const Icon(Icons.filter_alt),
                    onSelected: (f) => setState(() => _activeFilter = f),
                    itemBuilder: (ctx) => [
                      PopupMenuItem(value: _ActiveFilter.all, child: Row(children: const [Icon(Icons.list), SizedBox(width: 8), Text('All')])),
                      PopupMenuItem(value: _ActiveFilter.suspicious, child: Row(children: const [Icon(Icons.warning, color: Colors.red), SizedBox(width: 8), Text('Suspicious (RED)')])),
                      PopupMenuItem(value: _ActiveFilter.systemAlerts, child: Row(children: const [Icon(Icons.notifications, color: Colors.orange), SizedBox(width: 8), Text('System Alerts (ORANGE)')])),
                      PopupMenuItem(value: _ActiveFilter.multipleDL, child: Row(children: const [Icon(Icons.copy_all, color: Colors.orange), SizedBox(width: 8), Text('Multiple DL (ORANGE)')])),
                    ],
                  ),
                ],
              ),
            ),
            // Horizontal counters
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  _smallStatChip('Total', total.toString()),
                  const SizedBox(width: 8),
                  _smallStatChip('Suspicious', suspiciousCount.toString(), color: Colors.red.shade50, textColor: Colors.red.shade700),
                  const SizedBox(width: 8),
                  _smallStatChip('System', systemAlertCount.toString(), color: Colors.orange.shade50, textColor: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  _smallStatChip('Multi-DL', multipleDLCount.toString(), color: Colors.orange.shade50, textColor: Colors.orange.shade700),
                ],
              ),
            ),
            // Expanded to take up remaining space
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(onPressed: _fetchLogs, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                  ]),
                ),
              )
                  : RefreshIndicator(
                onRefresh: _fetchLogs,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final item = list[index];
                    final sev = _cardSeverity(item);

                    final ts = item['timestamp'] ?? item['time'] ?? item['created_at'] ?? item['date'] ?? '';
                    final dlNumber = (item['dl_number'] ?? item['dl'] ?? item['licenseNumber'] ?? '').toString();
                    final dlStatus = (item['dl_status'] ?? item['status'] ?? item['verification'] ?? '').toString();
                    final rcNumber = (item['vehicle_number'] ?? item['regn_number'] ?? item['rc_number'] ?? item['rc'] ?? '').toString();
                    final rcStatus = (item['rc_status'] ?? item['verification'] ?? '').toString();
                    final reason = (item['description'] ?? item['reason'] ?? item['crime_involved'] ?? '').toString();
                    final location = (item['location'] ?? '').toString();
                    final scannedBy = (item['scanned_by'] ?? '').toString();
                    final imageField = item['driver_image'] ?? item['vehicle_image'] ?? item['image'] ?? item['photo'];

                    // Card background / border color based on severity
                    final cardBg = sev == _Severity.red ? Colors.red.shade50 : (sev == _Severity.orange ? Colors.orange.shade50 : Colors.white);
                    final borderColor = sev == _Severity.red ? Colors.red.shade300 : (sev == _Severity.orange ? Colors.orange.shade300 : Colors.grey.shade200);
                    final markerLabel = sev == _Severity.red ? 'SUSPICIOUS' : (sev == _Severity.orange ? 'ALERT' : 'ALERT');
                    final markerColor = sev == _Severity.red ? Colors.red.shade700 : Colors.orange.shade600;

                    return Card(
                      color: cardBg,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: borderColor, width: sev == _Severity.none ? 1.0 : 1.6),
                      ),
                      elevation: sev == _Severity.red ? 6 : 3,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            _buildImageWidget(imageField, 64.0, onTap: () => _showImageFullscreen(imageField)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(_formatTimestamp(ts), style: const TextStyle(fontWeight: FontWeight.w700))),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: markerColor,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(markerLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  )
                                ]),
                                const SizedBox(height: 8),
                                Wrap(spacing: 8, runSpacing: 6, children: [
                                  if (dlNumber.isNotEmpty)
                                    ActionChip(
                                      label: Text('DL: $dlNumber', style: const TextStyle(fontSize: 13)),
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: dlNumber));
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('DL copied')));
                                      },
                                    ),
                                  if (dlStatus.isNotEmpty)
                                    Chip(
                                      label: Text(dlStatus, style: const TextStyle(fontSize: 13)),
                                      backgroundColor: dlStatus.toLowerCase().contains('black') ? Colors.red.shade50 : Colors.green.shade50,
                                    ),
                                  if (rcNumber.isNotEmpty)
                                    ActionChip(
                                      label: Text('RC: $rcNumber', style: const TextStyle(fontSize: 13)),
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: rcNumber));
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('RC copied')));
                                      },
                                    ),
                                  if (rcStatus.isNotEmpty)
                                    Chip(
                                      label: Text(rcStatus, style: const TextStyle(fontSize: 13)),
                                      backgroundColor: rcStatus.toLowerCase().contains('black') ? Colors.red.shade50 : Colors.green.shade50,
                                    ),
                                ]),
                              ]),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          // Reason text (prominent for red)
                          Text(
                            reason.isNotEmpty ? reason : 'No reason provided',
                            style: TextStyle(
                              color: _reasonColor(sev),
                              fontWeight: sev == _Severity.red ? FontWeight.w700 : FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Expanded(child: Text('Location: ${location.isNotEmpty ? location : '-'}', style: const TextStyle(color: Colors.black54))),
                            Row(children: [
                              Text(scannedBy.isNotEmpty ? scannedBy : '-', style: const TextStyle(color: Colors.black54)),
                              const SizedBox(width: 8),
                              IconButton(icon: const Icon(Icons.remove_red_eye), tooltip: 'View Raw', onPressed: () => _showRawJson(item)),
                              IconButton(
                                icon: const Icon(Icons.copy_all),
                                tooltip: 'Copy JSON',
                                onPressed: () {
                                  final jsonStr = const JsonEncoder.withIndent('  ').convert(item);
                                  Clipboard.setData(ClipboardData(text: jsonStr));
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON copied')));
                                },
                              )
                            ])
                          ])
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallStatChip(String label, String value, {Color? color, Color? textColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: textColor ?? Colors.black87)),
          const SizedBox(width: 6),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textColor ?? Colors.black87)),
        ],
      ),
    );
  }
}