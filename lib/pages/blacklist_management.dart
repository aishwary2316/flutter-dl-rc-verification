import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Blacklist Management (wired to ApiService)
class BlacklistManagementPage extends StatefulWidget {
  final String role; // <-- Add this line

  const BlacklistManagementPage({super.key, required this.role});

  @override
  State<BlacklistManagementPage> createState() => _BlacklistManagementPageState();
}

class _BlacklistManagementPageState extends State<BlacklistManagementPage>
    with SingleTickerProviderStateMixin { // <-- Corrected mixin name
  final ApiService _api = ApiService();

  final int _limit = 20;

  bool _loadingDL = false;
  bool _loadingRC = false;
  String? _errorDL;
  String? _errorRC;

  List<Map<String, dynamic>> _dlList = [];
  List<Map<String, dynamic>> _rcList = [];
  int _dlTotal = 0;
  int _rcTotal = 0;
  int _dlPage = 1;
  int _rcPage = 1;
  bool _isSearching = false;

  final TextEditingController _dlSearchCtrl = TextEditingController();
  final TextEditingController _rcSearchCtrl = TextEditingController();

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _typeCtrl = TextEditingController(text: 'dl');
  final Map<String, TextEditingController> _formCtrls = {
    'number': TextEditingController(),
    'name': TextEditingController(),
    'phone': TextEditingController(),
    'crime': TextEditingController(),
    'owner': TextEditingController(),
    'maker': TextEditingController(),
    'vehicle': TextEditingController(),
    'wheel': TextEditingController(),
  };

  late TabController _tabController;
  final ScrollController _dlScroll = ScrollController();
  final ScrollController _rcScroll = ScrollController();

  // debounce timers
  Timer? _dlDebounce;
  Timer? _rcDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {})); // ensure UI updates on tab change

    // search listeners (debounce)
    _dlSearchCtrl.addListener(() {
      _dlDebounce?.cancel();
      _dlDebounce = Timer(const Duration(milliseconds: 400), () => _fetchDLs(page: 1));
    });
    _rcSearchCtrl.addListener(() {
      _rcDebounce?.cancel();
      _rcDebounce = Timer(const Duration(milliseconds: 400), () => _fetchRCs(page: 1));
    });

    _fetchDLs();
    _fetchRCs();

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
    _dlSearchCtrl.dispose();
    _rcSearchCtrl.dispose();
    _formCtrls.forEach((key, ctrl) => ctrl.dispose());
    _typeCtrl.dispose();
    _tabController.dispose();
    _dlScroll.dispose();
    _rcScroll.dispose();
    super.dispose();
  }

  /// -----------------------
  /// Fetching functions (use ApiService)
  /// -----------------------
  Future<void> _fetchDLs({int page = 1}) async {
    setState(() {
      _loadingDL = true;
      _errorDL = null;
    });

    final q = _dlSearchCtrl.text.trim();
    try {
      final resp = await _api.getBlacklistedDLs(page: page, limit: _limit, search: q);
      if (resp['ok'] == true) {
        final body = resp['data'];
        // Defensive parsing
        List<Map<String, dynamic>> dataList = [];
        int pageGot = page;
        int pagesGot = 1;
        int totalGot = 0;

        if (body is Map) {
          final rawList = body['data'] ?? body['items'] ?? body['results'] ?? body;
          if (rawList is List) {
            dataList = List<Map<String, dynamic>>.from(rawList.map((e) => Map<String, dynamic>.from(e as Map)));
          }
          pageGot = body['page'] ?? page;
          pagesGot = body['pages'] ?? body['totalPages'] ?? 1;
          totalGot = body['total'] ?? dataList.length;
        } else if (body is List) {
          dataList = List<Map<String, dynamic>>.from(body.map((e) => Map<String, dynamic>.from(e as Map)));
          totalGot = dataList.length;
        }

        setState(() {
          if (page == 1) _dlList = dataList;
          else _dlList.addAll(dataList);
          _dlTotal = totalGot;
          _dlPage = pageGot;
        });
      } else {
        setState(() => _errorDL = resp['message'] ?? 'Failed to load DL blacklist');
      }
    } catch (e) {
      setState(() => _errorDL = 'Error loading DL blacklist: $e');
    } finally {
      setState(() => _loadingDL = false);
    }
  }

  Future<void> _fetchRCs({int page = 1}) async {
    setState(() {
      _loadingRC = true;
      _errorRC = null;
    });

    final q = _rcSearchCtrl.text.trim();
    try {
      final resp = await _api.getBlacklistedRCs(page: page, limit: _limit, search: q);
      if (resp['ok'] == true) {
        final body = resp['data'];
        List<Map<String, dynamic>> dataList = [];
        int pageGot = page;
        int pagesGot = 1;
        int totalGot = 0;

        if (body is Map) {
          final rawList = body['data'] ?? body['items'] ?? body['results'] ?? body;
          if (rawList is List) {
            dataList = List<Map<String, dynamic>>.from(rawList.map((e) => Map<String, dynamic>.from(e as Map)));
          }
          pageGot = body['page'] ?? page;
          pagesGot = body['pages'] ?? body['totalPages'] ?? 1;
          totalGot = body['total'] ?? dataList.length;
        } else if (body is List) {
          dataList = List<Map<String, dynamic>>.from(body.map((e) => Map<String, dynamic>.from(e as Map)));
          totalGot = dataList.length;
        }

        setState(() {
          if (page == 1) _rcList = dataList;
          else _rcList.addAll(dataList);
          _rcTotal = totalGot;
          _rcPage = pageGot;
        });
      } else {
        setState(() => _errorRC = resp['message'] ?? 'Failed to load RC blacklist');
      }
    } catch (e) {
      setState(() => _errorRC = 'Error loading RC blacklist: $e');
    } finally {
      setState(() => _loadingRC = false);
    }
  }

  /// -----------------------
  /// Add & Remove (use ApiService)
  /// -----------------------
  Future<void> _addToBlacklist() async {
    if (!_formKey.currentState!.validate()) return;

    final type = _typeCtrl.text.trim();
    final payload = <String, dynamic>{
      'type': type,
      'number': _formCtrls['number']!.text.trim(),
      if (type == 'dl') ...{
        'name': _formCtrls['name']!.text.trim().isEmpty ? null : _formCtrls['name']!.text.trim(),
        'phone_number': _formCtrls['phone']!.text.trim().isEmpty ? null : _formCtrls['phone']!.text.trim(),
        'crime_involved': _formCtrls['crime']!.text.trim().isEmpty ? null : _formCtrls['crime']!.text.trim(),
      },
      if (type == 'rc') ...{
        'owner_name': _formCtrls['name']!.text.trim().isEmpty ? null : _formCtrls['name']!.text.trim(),
        'maker_class': _formCtrls['maker']!.text.trim().isEmpty ? null : _formCtrls['maker']!.text.trim(),
        'vehicle_class': _formCtrls['vehicle']!.text.trim().isEmpty ? null : _formCtrls['vehicle']!.text.trim(),
        'wheel_type': _formCtrls['wheel']!.text.trim().isEmpty ? null : _formCtrls['wheel']!.text.trim(),
        'crime_involved': _formCtrls['crime']!.text.trim().isEmpty ? null : _formCtrls['crime']!.text.trim(),
      },
    }..removeWhere((k, v) => v == null);

    setState(() {
      if (type == 'dl') _loadingDL = true;
      else _loadingRC = true;
    });

    try {
      final resp = await _api.addToBlacklist(payload);
      if (resp['ok'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to blacklist successfully!'), backgroundColor: Colors.green));
        }
        if (type == 'dl') await _fetchDLs(page: 1);
        else await _fetchRCs(page: 1);
        Navigator.of(context).pop(); // close bottom sheet
      } else {
        if (mounted) {
          final msg = resp['message'] ?? 'Failed to add';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add failed: $e'), backgroundColor: Colors.red));
    } finally {
      setState(() {
        _loadingDL = false;
        _loadingRC = false;
      });
    }
  }

  /// Call API to mark valid. Returns true on success.
  Future<bool> _markValid(String type, String id) async {
    try {
      final resp = await _api.markBlacklistValid(type: type, id: id);
      if (resp['ok'] == true) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry marked valid (removed)'), backgroundColor: Colors.green));
        if (type == 'dl') await _fetchDLs(page: 1);
        else await _fetchRCs(page: 1);
        return true;
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(resp['message'] ?? 'Failed to mark valid'), backgroundColor: Colors.red));
        return false;
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Remove failed: $e'), backgroundColor: Colors.red));
      return false;
    }
  }

  /// -----------------------
  /// UI pieces
  /// -----------------------
  Widget _buildListContent(List<Map<String, dynamic>> list, String type, String? error, bool loading, ScrollController scrollController) {
    if (loading && list.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && list.isEmpty) {
      return Center(child: Text(error, style: const TextStyle(color: Colors.red)));
    }
    if (list.isEmpty) {
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(type == 'dl' ? Icons.no_accounts : Icons.directions_car, size: 60, color: Colors.black38),
            const SizedBox(height: 16),
            Text('No blacklisted ${type.toUpperCase()}s found.', style: const TextStyle(fontSize: 18, color: Colors.black54)),
          ]));
    }

    // Determine if swipe-to-remove should be enabled
    final isSuperAdmin = widget.role == 'superadmin';
    final dismissDirection = isSuperAdmin ? DismissDirection.endToStart : DismissDirection.none;

    return RefreshIndicator(
      onRefresh: () => type == 'dl' ? _fetchDLs(page: 1) : _fetchRCs(page: 1),
      child: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: list.length + (loading && list.isNotEmpty ? 1 : 0),
        itemBuilder: (ctx, i) {
          if (i == list.length) {
            return const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()));
          }

          final entry = list[i];
          final id = (entry['_id'] is Map)
              ? (entry['_id']['\$oid'] ?? entry['_id'].toString())
              : entry['_id']?.toString() ?? '';
          final title = type == 'dl'
              ? (entry['dl_number'] ?? entry['dl'] ?? 'Unknown DL')
              : (entry['regn_number'] ?? entry['rc_number'] ?? entry['regnNo'] ?? 'Unknown RC');
          final subtitle = _buildSubtitle(entry, type);
          final status = (entry['verification'] ?? entry['Verification'] ?? entry['status'] ?? '').toString();

          return Dismissible(
            key: ValueKey(id + '-$i'),
            direction: dismissDirection, // Use the determined dismiss direction
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.delete_forever, color: Colors.red),
            ),
            confirmDismiss: (direction) async {
              final confirmed = await _showConfirmDialog('Mark this ${type.toUpperCase()} as valid (remove from blacklist)?');
              if (confirmed != true) return false;
              // perform API call here and only allow dismiss if success
              final ok = await _markValid(type, id.toString());
              return ok;
            },
            child: Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                leading: CircleAvatar(
                    backgroundColor: type == 'dl' ? Colors.blue.shade50 : Colors.teal.shade50,
                    child: Icon(type == 'dl' ? Icons.badge : Icons.directions_car, color: type == 'dl' ? Colors.blue : Colors.teal)),
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: subtitle,
                trailing: Chip(
                  label: Text(status.isNotEmpty ? status : '-', style: TextStyle(color: status.toLowerCase().contains('black') ? Colors.red.shade700 : Colors.green.shade700)),
                  backgroundColor: status.toLowerCase().contains('black') ? Colors.red.shade50 : Colors.green.shade50,
                ),
                onTap: () => _showEntryDetails(entry, type: type),
              ),
            ),
          );
        },
      ),
    );
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
      children.add(Padding(padding: const EdgeInsets.only(top: 6), child: Text('Reason: $reason', style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic))));
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
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Confirm')),
        ],
      ),
    );
  }

  void _showAddBottomSheet() {
    _formCtrls.forEach((key, ctrl) => ctrl.clear());
    _typeCtrl.text = _tabController.index == 0 ? 'dl' : 'rc';

    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom, top: 20, left: 20, right: 20),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Add New Blacklist Entry', style: Theme.of(context).textTheme.titleLarge),
                    IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close)),
                  ]),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Entry Type', border: OutlineInputBorder()),
                    value: _typeCtrl.text,
                    items: const [
                      DropdownMenuItem(value: 'dl', child: Text('Driving License (DL)')),
                      DropdownMenuItem(value: 'rc', child: Text('Registration Certificate (RC)')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _typeCtrl.text = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _formCtrls['number'],
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'This field is required' : null,
                    decoration: InputDecoration(labelText: _typeCtrl.text == 'dl' ? 'DL Number' : 'RC Number', border: const OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(controller: _formCtrls['crime'], decoration: const InputDecoration(labelText: 'Reason for Blacklisting (optional)', border: const OutlineInputBorder())),
                  const SizedBox(height: 16),
                  TextFormField(controller: _formCtrls['name'], decoration: InputDecoration(labelText: _typeCtrl.text == 'dl' ? 'Name (optional)' : 'Owner Name (optional)', border: const OutlineInputBorder())),
                  const SizedBox(height: 16),
                  if (_typeCtrl.text == 'dl') ...[
                    TextFormField(controller: _formCtrls['phone'], decoration: const InputDecoration(labelText: 'Phone Number (optional)', border: const OutlineInputBorder())),
                    const SizedBox(height: 16),
                  ],
                  if (_typeCtrl.text == 'rc') ...[
                    TextFormField(controller: _formCtrls['maker'], decoration: const InputDecoration(labelText: 'Maker Class (optional)', border: const OutlineInputBorder())),
                    const SizedBox(height: 16),
                    TextFormField(controller: _formCtrls['vehicle'], decoration: const InputDecoration(labelText: 'Vehicle Class (optional)', border: const OutlineInputBorder())),
                    const SizedBox(height: 16),
                    TextFormField(controller: _formCtrls['wheel'], decoration: const InputDecoration(labelText: 'Wheel Type (optional)', border: const OutlineInputBorder())),
                    const SizedBox(height: 16),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _addToBlacklist,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                      child: const Text('Add to Blacklist'),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showEntryDetails(Map<String, dynamic> item, {required String type}) {
    // Helper to safely read possible image fields
    String? _getImageUrl(Map<String, dynamic> it) {
      final keys = ['photo', 'image', 'photoUrl', 'image_url', 'photo_url'];
      for (final k in keys) {
        final v = it[k];
        if (v != null && v is String && v.trim().isNotEmpty) return v;
      }
      // sometimes nested structures exist
      if (it['images'] is List && (it['images'] as List).isNotEmpty) {
        final first = (it['images'] as List).first;
        if (first is String && first.isNotEmpty) return first;
        if (first is Map && first['url'] is String) return first['url'];
      }
      return null;
    }

    // Helper to show one row
    Widget row(String label, String? value) {
      if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: Text(value)),
        ]),
      );
    }

    final imageUrl = _getImageUrl(item);
    showDialog(
      context: context,
      builder: (ctx) {
        bool _isRemoving = false;
        return StatefulBuilder(builder: (ctx2, setState2) {
          // Build display fields depending on type
          final List<Widget> content = [];

          // ID
          final idVal = (item['_id'] is Map) ? (item['_id']['\$oid'] ?? item['_id'].toString()) : (item['_id']?.toString() ?? '');
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
            // rc
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

          // remove empty items
          final filtered = content.where((w) => w is! SizedBox).toList();

          return AlertDialog(
            title: Text('${type.toUpperCase()} Details'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (imageUrl != null) ...[
                      GestureDetector(
                        onTap: () {
                          // full-screen view
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
                            child: Image.network(imageUrl, height: 140, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image, size: 64)),
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
                onPressed: _isRemoving
                    ? null
                    : () {
                  Navigator.of(ctx2).pop();
                },
                child: const Text('Close'),
              ),
              // Only show remove button if user is superadmin
              if (widget.role == 'superadmin')
                OutlinedButton.icon(
                  icon: _isRemoving
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.red, // red spinner instead of white
                    ),
                  )
                      : const Icon(Icons.check, color: Colors.red),
                  label: const Text(
                    'Remove from blacklist',
                    style: TextStyle(color: Colors.red),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red, width: 1.5), // red border
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
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
                            child: const Text('Cancel'),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.red, width: 1.5),
                              foregroundColor: Colors.red,
                            ),
                            onPressed: () => Navigator.of(c).pop(true),
                            child: const Text('Confirm'),
                          ),
                        ],
                      ),
                    );
                    if (confirm != true) return;
                    setState2(() => _isRemoving = true);
                    final ok = await _markValid(type, idVal);
                    setState2(() => _isRemoving = false);
                    if (ok) Navigator.of(ctx2).pop(); // close details dialog after success
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
    // Choose the search controller for the currently active tab
    final TextEditingController activeSearchController = _tabController.index == 0 ? _dlSearchCtrl : _rcSearchCtrl;

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
        // IMPORTANT: keep TabBar visible always; show search field above it when searching.
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
                      hintText: _tabController.index == 0 ? 'Search DL number...' : 'Search RC number...',
                      prefixIcon: const Icon(Icons.search),
                      // single close icon inside the search bar that closes the search
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _isSearching = false;
                            _dlSearchCtrl.clear();
                            _rcSearchCtrl.clear();
                            _fetchDLs(page: 1);
                            _fetchRCs(page: 1);
                          });
                        },
                        tooltip: 'Close search',
                      ),
                      border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(30))),
                      filled: true,
                      fillColor: Colors.grey[200],
                      contentPadding: const EdgeInsets.symmetric(vertical: 0.0, horizontal: 16.0),
                    ),
                    onSubmitted: (_) {
                      if (_tabController.index == 0) _fetchDLs(page: 1);
                      else _fetchRCs(page: 1);
                    },
                  ),
                ),
              // TabBar remains visible and interactive even when searching
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: 'DL ($_dlTotal)'),
                  Tab(text: 'RC ($_rcTotal)'),
                ],
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                indicatorWeight: 3.0,
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: widget.role == 'superadmin' // <-- Role check to show/hide button
          ? FloatingActionButton(
        onPressed: _showAddBottomSheet,
        child: const Icon(Icons.add),
      )
          : null, // Hide FAB for other roles
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildListContent(_dlList, 'dl', _errorDL, _loadingDL, _dlScroll),
          _buildListContent(_rcList, 'rc', _errorRC, _loadingRC, _rcScroll),
        ],
      ),
    );
  }
}