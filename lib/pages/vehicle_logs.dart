// lib/pages/vehicle_logs.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import '../services/api_service.dart';

class VehicleLogsPage extends StatefulWidget {
  const VehicleLogsPage({super.key});

  @override
  State<VehicleLogsPage> createState() => _VehicleLogsPageState();
}

class _VehicleLogsPageState extends State<VehicleLogsPage> {
  final ApiService _api = ApiService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = [];

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _api.getLogs();
      if (res['ok'] == true) {
        final data = res['data'];
        final normalized = _normalizeDataToList(data);
        setState(() {
          _logs = normalized;
        });
      } else {
        setState(() {
          _error = res['message'] ?? 'Failed to fetch logs';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error fetching logs: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _normalizeDataToList(dynamic data) {
    List<Map<String, dynamic>> logsList = [];
    if (data is List) {
      logsList = data.map<Map<String, dynamic>>((e) {
        if (e is Map) return Map<String, dynamic>.from(e);
        return {'entry': e};
      }).toList();
    } else if (data is Map && data['logs'] is List) {
      logsList = (data['logs'] as List).map<Map<String, dynamic>>((e) {
        if (e is Map) return Map<String, dynamic>.from(e);
        return {'entry': e};
      }).toList();
    } else if (data is Map) {
      logsList = [Map<String, dynamic>.from(data)];
    } else {
      logsList = [
        {'data': data}
      ];
    }
    return logsList;
  }

  Widget _buildImageWidget(dynamic img, double size) {
    if (img == null) {
      return CircleAvatar(radius: size / 2, child: Icon(Icons.directions_car, size: size * 0.6));
    }

    try {
      final s = img.toString();

      if (s.startsWith('http') || s.startsWith('https')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            s,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => CircleAvatar(radius: size / 2, child: Icon(Icons.directions_car, size: size * 0.6)),
          ),
        );
      }

      if (s.startsWith('data:')) {
        final base64Str = s.split(',').last;
        final bytes = base64Decode(base64Str);
        return ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover));
      }

      // Heuristic: plain base64
      if (s.length > 100 && RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(s)) {
        final bytes = base64Decode(s.replaceAll('\n', ''));
        return ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover));
      }
    } catch (e) {
      // ignore and fallback
    }

    final label = img.toString();
    return CircleAvatar(radius: size / 2, child: Text(label.isNotEmpty ? label[0].toUpperCase() : '?'));
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
          return t;
        }
      } else if (t is DateTime) {
        final dt = t;
        return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}';
      }
    } catch (e) {
      // ignore
    }
    return t.toString();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF1E3A8A);
    const Color textGray = Color(0xFF64748B);
    const Color lightGray = Color(0xFFF8FAFC);

    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle Logs'), backgroundColor: primaryBlue),
      backgroundColor: lightGray,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 12),
                ElevatedButton.icon(onPressed: _fetchLogs, icon: const Icon(Icons.refresh), label: const Text('Retry')),
              ],
            ),
          ),
        )
            : _logs.isEmpty
            ? Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.history, size: 64, color: primaryBlue),
                SizedBox(height: 12),
                Text('No logs available', style: TextStyle(fontSize: 18)),
                SizedBox(height: 8),
                Text('Pull down to refresh.', textAlign: TextAlign.center),
              ],
            ),
          ),
        )
            : RefreshIndicator(
          onRefresh: _fetchLogs,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            itemCount: _logs.length,
            itemBuilder: (context, index) {
              final item = _logs[index];
              final vehicleNumber = item['vehicle_number'] ?? item['veh_no'] ?? item['vehicleNo'] ?? item['vehicle'] ?? item['vehicle_no'] ?? '';
              final driverName = item['driver_name'] ?? item['driver'] ?? item['name'] ?? '';
              final dlNumber = item['dl_number'] ?? item['dl'] ?? '';
              final rcNumber = item['rc_number'] ?? item['rc'] ?? '';
              final status = item['status'] ?? item['result'] ?? item['verification'] ?? '';
              final ts = item['timestamp'] ?? item['time'] ?? item['created_at'] ?? item['date'] ?? '';
              final imageField = item['driver_image'] ?? item['vehicle_image'] ?? item['image'] ?? item['photo'];

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildImageWidget(imageField, 72.0),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    vehicleNumber.toString().isNotEmpty ? vehicleNumber.toString() : 'Unknown vehicle',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (status.toString().toLowerCase() == 'verified' ||
                                        status.toString().toLowerCase() == 'ok' ||
                                        status.toString().toLowerCase() == 'success')
                                        ? Colors.green.withOpacity(0.12)
                                        : Colors.orange.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    status.toString().isNotEmpty ? status.toString() : 'N/A',
                                    style: TextStyle(
                                      color: (status.toString().toLowerCase() == 'verified' ||
                                          status.toString().toLowerCase() == 'ok' ||
                                          status.toString().toLowerCase() == 'success')
                                          ? Colors.green[800]
                                          : Colors.orange[800],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            if (driverName.toString().isNotEmpty) Text('Driver: ${driverName.toString()}', style: const TextStyle(fontSize: 14)),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (dlNumber.toString().isNotEmpty)
                                  Expanded(child: Text('DL: ${dlNumber.toString()}', style: TextStyle(fontSize: 13, color: textGray))),
                                if (rcNumber.toString().isNotEmpty)
                                  Expanded(child: Text('RC: ${rcNumber.toString()}', style: TextStyle(fontSize: 13, color: textGray))),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatTimestamp(ts), style: const TextStyle(fontSize: 12, color: textGray)),
                                TextButton(
                                  onPressed: () {
                                    // Use the builder-context for safe pop
                                    showDialog(
                                      context: context,
                                      builder: (dialogCtx) => AlertDialog(
                                        title: const Text('Log JSON'),
                                        content: SingleChildScrollView(child: Text(const JsonEncoder.withIndent('  ').convert(item))),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.of(dialogCtx).pop(),
                                            child: const Text('Close'),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  child: const Text('View raw', style: TextStyle(fontSize: 13)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
