// lib/pages/vehicle_logs.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  // UI state
  String _searchQuery = '';
  String _filter = 'all'; // all, suspicious, blacklisted, verified
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _fetchLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _api.getLogs();
      if (res['ok'] == true || res['data'] != null) {
        final data = res['data'] ?? res;
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
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              s,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => CircleAvatar(radius: size / 2, child: Icon(Icons.directions_car, size: size * 0.6)),
            ),
          ),
        );
      }

      if (s.startsWith('data:')) {
        final base64Str = s.split(',').last;
        final bytes = base64Decode(base64Str);
        return GestureDetector(
          onTap: onTap,
          child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover)),
        );
      }

      // Heuristic: plain base64
      if (s.length > 100 && RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(s)) {
        final bytes = base64Decode(s.replaceAll('\n', ''));
        return GestureDetector(
          onTap: onTap,
          child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover)),
        );
      }
    } catch (e) {
      // ignore and fallback
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

  // --- Filtering & grouping helpers ---
  List<Map<String, dynamic>> get _filteredLogs {
    final q = _searchQuery.trim().toLowerCase();
    return _logs.where((item) {
      // filter by search
      final vehicleNumber = (item['vehicle_number'] ?? item['veh_no'] ?? item['vehicleNo'] ?? item['vehicle'] ?? item['vehicle_no'] ?? '').toString().toLowerCase();
      final driverName = (item['driver_name'] ?? item['driver'] ?? item['name'] ?? '').toString().toLowerCase();
      final dlNumber = (item['dl_number'] ?? item['dl'] ?? '').toString().toLowerCase();
      final rcNumber = (item['rc_number'] ?? item['rc'] ?? '').toString().toLowerCase();
      final status = (item['status'] ?? item['result'] ?? item['verification'] ?? '').toString().toLowerCase();

      final matchesQuery = q.isEmpty ||
          vehicleNumber.contains(q) ||
          driverName.contains(q) ||
          dlNumber.contains(q) ||
          rcNumber.contains(q) ||
          status.contains(q);

      if (!matchesQuery) return false;

      if (_filter == 'all') return true;
      if (_filter == 'suspicious') {
        // suspicious marker in server is often boolean or suspicious==true or alert_type present
        if (item['suspicious'] == true) return true;
        if (item['alert_type'] != null) return true;
        if (status.contains('blacklist') || status.contains('blacklisted') || status.contains('suspicious') || status.contains('alert')) return true;
        return false;
      }
      if (_filter == 'blacklisted') {
        if ((item['dl_status'] ?? item['rc_status'] ?? item['status'] ?? '').toString().toLowerCase().contains('blacklist')) return true;
        if ((item['verification'] ?? '').toString().toLowerCase().contains('blacklist')) return true;
        return false;
      }
      if (_filter == 'verified') {
        final s = (item['status'] ?? item['result'] ?? item['verification'] ?? item['dl_status'] ?? '').toString().toLowerCase();
        return s.contains('ok') || s.contains('verified') || s.contains('valid') || s.contains('success');
      }
      return true;
    }).toList();
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate(List<Map<String, dynamic>> logs) {
    final Map<String, List<Map<String, dynamic>>> map = {};
    for (var item in logs) {
      final tsRaw = item['timestamp'] ?? item['time'] ?? item['created_at'] ?? item['date'] ?? '';
      DateTime? dt;
      if (tsRaw is int) {
        dt = (tsRaw.toString().length > 10) ? DateTime.fromMillisecondsSinceEpoch(tsRaw) : DateTime.fromMillisecondsSinceEpoch(tsRaw * 1000);
      } else if (tsRaw is String) {
        dt = DateTime.tryParse(tsRaw);
      } else if (tsRaw is DateTime) {
        dt = tsRaw;
      }
      final key = dt != null ? '${dt.year}-${_two(dt.month)}-${_two(dt.day)}' : 'Unknown';
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  // --- UI helpers ---
  Color _statusColor(String s) {
    final st = s.toLowerCase();
    if (st.contains('black')) return Colors.red.shade600;
    if (st.contains('susp') || st.contains('alert') || st.contains('suspect')) return Colors.red.shade700;
    if (st.contains('ok') || st.contains('verified') || st.contains('valid') || st.contains('success')) return Colors.green.shade700;
    return Colors.orange.shade700;
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

  void _copyToClipboard(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied to clipboard')));
  }

  void _showRawJson(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Log JSON'),
        content: SingleChildScrollView(child: Text(const JsonEncoder.withIndent('  ').convert(item))),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(), child: const Text('Close')),
          TextButton(
            onPressed: () {
              final jsonStr = const JsonEncoder.withIndent('  ').convert(item);
              Clipboard.setData(ClipboardData(text: jsonStr));
              Navigator.of(dialogCtx).pop();
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON copied to clipboard')));
            },
            child: const Text('Copy JSON'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final total = _logs.length;
    final suspiciousCount = _logs.where((i) {
      if (i['suspicious'] == true) return true;
      if (i['alert_type'] != null) return true;
      final s = ((i['status'] ?? i['result'] ?? i['verification']) ?? '').toString().toLowerCase();
      return s.contains('blacklist') || s.contains('susp');
    }).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: 'Search vehicle / driver / DL / RC / status',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                  textInputAction: TextInputAction.search,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: _fetchLogs, icon: const Icon(Icons.refresh)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Chip(label: Text('Total: $total')),
              const SizedBox(width: 8),
              Chip(backgroundColor: Colors.red.shade50, label: Text('Suspicious: $suspiciousCount', style: TextStyle(color: Colors.red.shade700))),
              const Spacer(),
              DropdownButton<String>(
                value: _filter,
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'suspicious', child: Text('Suspicious')),
                  DropdownMenuItem(value: 'blacklisted', child: Text('Blacklisted')),
                  DropdownMenuItem(value: 'verified', child: Text('Verified')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _filter = v;
                  });
                },
              )
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryBlue = Color(0xFF1E3A8A);
    const Color textGray = Color(0xFF64748B);
    const Color lightGray = Color(0xFFF8FAFC);

    final filtered = _filteredLogs;
    final grouped = _groupByDate(filtered);

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
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              ...grouped.entries.map((entry) {
                final dateKey = entry.key;
                final listForDate = entry.value;
                String label;
                final now = DateTime.now();
                final todayKey = '${now.year}-${_two(now.month)}-${_two(now.day)}';
                final yesterday = now.subtract(const Duration(days: 1));
                final yesterdayKey = '${yesterday.year}-${_two(yesterday.month)}-${_two(yesterday.day)}';
                if (dateKey == todayKey) {
                  label = 'Today';
                } else if (dateKey == yesterdayKey) label = 'Yesterday';
                else label = dateKey;

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                        (ctx, index) {
                      final item = listForDate[index];
                      final vehicleNumber = item['vehicle_number'] ?? item['veh_no'] ?? item['vehicleNo'] ?? item['vehicle'] ?? item['vehicle_no'] ?? '';
                      final driverName = item['driver_name'] ?? item['driver'] ?? item['name'] ?? '';
                      final dlNumber = item['dl_number'] ?? item['dl'] ?? '';
                      final rcNumber = item['rc_number'] ?? item['rc'] ?? '';
                      final status = item['status'] ?? item['result'] ?? item['verification'] ?? item['dl_status'] ?? '';
                      final ts = item['timestamp'] ?? item['time'] ?? item['created_at'] ?? item['date'] ?? '';
                      final imageField = item['driver_image'] ?? item['vehicle_image'] ?? item['image'] ?? item['photo'];

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                        child: Card(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildImageWidget(imageField, 84.0, onTap: () => _showImageFullscreen(imageField)),
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
                                              color: _statusColor(status.toString()).withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              status.toString().isNotEmpty ? status.toString() : 'N/A',
                                              style: TextStyle(
                                                color: _statusColor(status.toString()),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      if (driverName.toString().isNotEmpty) Text('Driver: ${driverName.toString()}', style: const TextStyle(fontSize: 14)),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          if (dlNumber.toString().isNotEmpty)
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  Flexible(child: Text('DL: ${dlNumber.toString()}', style: TextStyle(fontSize: 13, color: textGray))),
                                                  IconButton(
                                                    icon: const Icon(Icons.copy, size: 18),
                                                    tooltip: 'Copy DL',
                                                    onPressed: () => _copyToClipboard('DL', dlNumber.toString()),
                                                  )
                                                ],
                                              ),
                                            ),
                                          if (rcNumber.toString().isNotEmpty)
                                            Expanded(
                                              child: Row(
                                                children: [
                                                  Flexible(child: Text('RC: ${rcNumber.toString()}', style: TextStyle(fontSize: 13, color: textGray))),
                                                  IconButton(
                                                    icon: const Icon(Icons.copy, size: 18),
                                                    tooltip: 'Copy RC',
                                                    onPressed: () => _copyToClipboard('RC', rcNumber.toString()),
                                                  )
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(_formatTimestamp(ts), style: const TextStyle(fontSize: 12, color: textGray)),
                                          Row(
                                            children: [
                                              TextButton(
                                                onPressed: () => _showRawJson(item),
                                                child: const Text('View raw', style: TextStyle(fontSize: 13)),
                                              ),
                                              const SizedBox(width: 4),
                                              IconButton(
                                                icon: const Icon(Icons.share, size: 20),
                                                tooltip: 'Copy JSON',
                                                onPressed: () {
                                                  final jsonStr = const JsonEncoder.withIndent('  ').convert(item);
                                                  Clipboard.setData(ClipboardData(text: jsonStr));
                                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('JSON copied to clipboard')));
                                                },
                                              )
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: listForDate.length,
                  ),
                );
              }),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}
