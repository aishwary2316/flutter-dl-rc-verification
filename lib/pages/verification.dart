// lib/pages/verification.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// High-level wrapper: creates ApiService and calls showVerificationDialog.
Future<void> verifyDriverAndShowDialog(
    BuildContext context, {
      String? dlNumber,
      String? rcNumber,
      File? driverImageFile,
      String location = 'Toll-Plaza-1',
      String tollgate = 'Gate-A',
    }) async {
  final api = ApiService();
  await showVerificationDialog(
    context,
    api: api,
    dlNumber: dlNumber,
    rcNumber: rcNumber,
    driverImage: driverImageFile,
    location: location,
    tollgate: tollgate,
  );
}

/// Performs the verification call via ApiService.verifyDriver and shows the rich dialog.
/// Note: we DO NOT require caller to provide a base URL — ApiService has backendBaseUrl.
Future<void> showVerificationDialog(
    BuildContext context, {
      required ApiService api,
      String? dlNumber,
      String? rcNumber,
      File? driverImage,
      String location = 'Toll-Plaza-1',
      String tollgate = 'Gate-A',
    }) async {
  // Validate at least one input provided
  if ((dlNumber == null || dlNumber.trim().isEmpty) &&
      (rcNumber == null || rcNumber.trim().isEmpty) &&
      driverImage == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please provide DL, RC, or Driver image to verify.')),
    );
    return;
  }

  // Show loading while contacting server
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
    ),
  );

  Map<String, dynamic> bodyMap = {};
  String? errorMessage;

  try {
    final result = await api.verifyDriver(
      dlNumber: dlNumber != null && dlNumber.trim().isNotEmpty ? dlNumber.trim() : null,
      rcNumber: rcNumber != null && rcNumber.trim().isNotEmpty ? rcNumber.trim() : null,
      location: location,
      tollgate: tollgate,
      driverImage: driverImage,
    );

    if (result['ok'] == true) {
      final d = result['data'];
      if (d is Map) {
        bodyMap = Map<String, dynamic>.from(d);
      } else {
        bodyMap = {'raw': d};
      }
    } else {
      // server returned ok=false
      errorMessage = result['message'] ??
          (result['body'] != null ? const JsonEncoder.withIndent(' ').convert(result['body']) : 'Verification failed');
    }
  } catch (e) {
    errorMessage = 'An error occurred during verification: $e';
  } finally {
    // Dismiss loading
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  if (errorMessage != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage)));
    return;
  }

  // Ensure bodyMap is non-empty; if empty, create a minimal body so dialog shows something useful
  if (bodyMap.isEmpty) {
    bodyMap = {
      'dlData': dlNumber != null && dlNumber.trim().isNotEmpty ? {'licenseNumber': dlNumber.trim(), 'status': 'N/A'} : null,
      'rcData': rcNumber != null && rcNumber.trim().isNotEmpty ? {'regn_number': rcNumber.trim(), 'status': 'N/A'} : null,
      'driverData': driverImage != null ? {'status': 'N/A', 'provided': true} : null,
      'suspicious': false,
      'note': 'Empty server body — showing local preview.',
    };
  }

  // Show the rich result dialog. bodyMap is guaranteed non-null Map<String,dynamic>.
  await showDialog<void>(
    context: context,
    builder: (ctx) => VerificationResultDialog(api: api, body: bodyMap),
  );
}

/// Dialog widget that displays verification result and allows DL-usage fetch.
/// (body must be a non-null Map<String,dynamic>)
class VerificationResultDialog extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic> body;

  const VerificationResultDialog({super.key, required this.api, required this.body});

  @override
  State<VerificationResultDialog> createState() => _VerificationResultDialogState();
}

class _VerificationResultDialogState extends State<VerificationResultDialog> {
  bool _fetchingUsage = false;

  Map<String, dynamic>? get dlData => widget.body['dlData'] is Map ? Map<String, dynamic>.from(widget.body['dlData']) : null;
  Map<String, dynamic>? get rcData => widget.body['rcData'] is Map ? Map<String, dynamic>.from(widget.body['rcData']) : null;
  Map<String, dynamic>? get driverData => widget.body['driverData'] is Map ? Map<String, dynamic>.from(widget.body['driverData']) : null;
  bool get suspiciousFlag => widget.body['suspicious'] == true;

  List<String> _suspiciousReasons() {
    final List<String> reasons = [];
    if (dlData != null) {
      final dlStatus = (dlData!['status'] ?? '').toString().toLowerCase();
      if (dlStatus == 'blacklisted') reasons.add('Driving License is BLACKLISTED');
      if (dlStatus == 'not_found') reasons.add('DL not found in DB');
    }
    if (rcData != null) {
      final rcStatus = (rcData!['status'] ?? rcData!['verification'] ?? '').toString().toLowerCase();
      if (rcStatus == 'blacklisted') reasons.add('Vehicle / RC is BLACKLISTED');
      if (rcStatus == 'not_found') reasons.add('RC / Vehicle not found in DB');
    }
    if (driverData != null) {
      final drvStatus = (driverData!['status'] ?? '').toString().toUpperCase();
      if (drvStatus == 'ALERT') reasons.add('Driver matched a SUSPECT (face recognition ALERT)');
      if (drvStatus == 'SERVICE_UNAVAILABLE') reasons.add('Face recognition service unavailable');
    }
    if (suspiciousFlag && reasons.isEmpty) reasons.add('System raised a suspicious flag (details in raw JSON)');
    return reasons;
  }

  Future<void> _fetchDLUsage(String dlNum) async {
    setState(() => _fetchingUsage = true);
    try {
      final usage = await widget.api.getDLUsage(dlNum);
      if (usage['ok'] == true) {
        final data = usage['data'] ?? [];
        _showDLUsageDialog(dlNum, data);
      } else {
        final msg = usage['message'] ?? 'Failed to fetch DL usage';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error fetching usage: $e')));
    } finally {
      setState(() => _fetchingUsage = false);
    }
  }

  void _showDLUsageDialog(String dlNumber, dynamic logs) {
    final List logsList = (logs is List) ? logs : [];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('DL Usage: $dlNumber (last 2 days)'),
        content: SizedBox(
          width: double.maxFinite,
          child: logsList.isEmpty
              ? const Text('No recent usage logs found for this DL in last 2 days.')
              : ListView.separated(
            shrinkWrap: true,
            itemCount: logsList.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (c, i) {
              final item = logsList[i] is Map ? Map<String, dynamic>.from(logsList[i]) : {'raw': logsList[i]};
              final ts = item['timestamp'] ?? item['time'] ?? '';
              return ListTile(
                title: Text(item['vehicle_number'] ?? item['vehicle'] ?? 'Vehicle: N/A'),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (item['dl_number'] != null) Text('DL: ${item['dl_number']}'),
                  if (item['alert_type'] != null) Text('Alert: ${item['alert_type']}'),
                  if (item['description'] != null) Text('Desc: ${item['description']}'),
                  if (ts != null) Text('Time: ${ts.toString()}'),
                ]),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close'))],
      ),
    );
  }

  Widget _twoColumn(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(child: Text(value == null ? 'N/A' : value.toString())),
      ]),
    );
  }

  Widget _optionalKeyList(Map<String, dynamic> map, List<String> ignoreKeys) {
    final displayed = <String>{
      'status',
      'licenseNumber',
      'dl_number',
      'name',
      'validity',
      'phone_number',
      'regn_number',
      'owner_name',
      'maker_class',
      'vehicle_class',
      'wheel_type',
      'engine_number',
      'chassis_number',
      'crime_involved',
      'verification',
      'message',
    };
    final extras = <String>[];
    for (final k in map.keys) {
      if (!displayed.contains(k) && !ignoreKeys.contains(k)) extras.add(k);
    }
    if (extras.isEmpty) return const SizedBox.shrink();
    final limited = extras.take(8);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      const Text('Other fields:', style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      for (final k in limited) _twoColumn(k, map[k]),
      if (extras.length > 8) Text('+ ${extras.length - 8} more fields'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final reasons = _suspiciousReasons();
    return AlertDialog(
      title: Row(children: [
        const Expanded(child: Text('Verification Result', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
        if (suspiciousFlag)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
            child: const Text('SUSPICIOUS', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
      ]),
      content: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (reasons.isNotEmpty) ...[
            const Text('Alerts / Reasons', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            for (final r in reasons) Row(children: [const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18), const SizedBox(width: 8), Expanded(child: Text(r, style: const TextStyle(fontWeight: FontWeight.w600)))]),
            const Divider(),
          ],

          const Text('Driving License (DL)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (dlData == null)
            const Text('No DL data returned.')
          else
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _twoColumn('Status', dlData!['status'] ?? 'N/A'),
              _twoColumn('License No', dlData!['licenseNumber'] ?? dlData!['dl_number'] ?? 'N/A'),
              _twoColumn('Name', dlData!['name'] ?? 'N/A'),
              _twoColumn('Validity', dlData!['validity'] ?? 'N/A'),
              _twoColumn('Phone', dlData!['phone_number'] ?? 'N/A'),
              _optionalKeyList(dlData!, ['other', 'extra']),
            ]),

          const SizedBox(height: 12),
          const Divider(),

          const Text('Vehicle / RC', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (rcData == null)
            const Text('No RC data returned.')
          else
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _twoColumn('Status', rcData!['status'] ?? rcData!['verification'] ?? 'N/A'),
              _twoColumn('Regn No', rcData!['regn_number'] ?? 'N/A'),
              _twoColumn('Owner', rcData!['owner_name'] ?? 'N/A'),
              _twoColumn('Maker Class', rcData!['maker_class'] ?? 'N/A'),
              _twoColumn('Vehicle Class', rcData!['vehicle_class'] ?? 'N/A'),
              _twoColumn('Wheel Type', rcData!['wheel_type'] ?? 'N/A'),
              _twoColumn('Engine No', rcData!['engine_number'] ?? 'N/A'),
              _twoColumn('Chassis No', rcData!['chassis_number'] ?? 'N/A'),
              if (rcData!['crime_involved'] != null) _twoColumn('Crime Involved', rcData!['crime_involved']),
              _optionalKeyList(rcData!, ['other', 'extra']),
            ]),

          const SizedBox(height: 12),
          const Divider(),

          const Text('Driver / Face Recognition', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (driverData == null)
            const Text('No driver image / face data returned.')
          else
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _twoColumn('Status', driverData!['status'] ?? 'N/A'),
              if (driverData!['name'] != null) _twoColumn('Name', driverData!['name']),
              if (driverData!['message'] != null) _twoColumn('Message', driverData!['message']),
              _optionalKeyList(driverData!, ['confidence', 'score', 'meta']),
            ]),

          const SizedBox(height: 12),
          const Divider(),

          const Text('Raw JSON Response', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
            child: SelectableText(const JsonEncoder.withIndent(' ').convert(widget.body)),
          ),

          const SizedBox(height: 12),

          if (dlData != null && (dlData!['licenseNumber'] ?? dlData!['dl_number']) != null)
            Row(children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.list_alt),
                label: const Text('View DL usage (2 days)'),
                onPressed: _fetchingUsage
                    ? null
                    : () {
                  final dlNum = (dlData!['licenseNumber'] ?? dlData!['dl_number']).toString();
                  _fetchDLUsage(dlNum);
                },
              ),
              const SizedBox(width: 8),
              if (reasons.isNotEmpty)
                TextButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder: (dctx) => AlertDialog(
                        title: const Text('Suspicious Reasons'),
                        content: SingleChildScrollView(child: Text(reasons.join('\n'))),
                        actions: [TextButton(onPressed: () => Navigator.of(dctx).pop(), child: const Text('Close'))],
                      ),
                    );
                  },
                  child: const Text('View Suspicious Reasons'),
                )
            ])
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}
