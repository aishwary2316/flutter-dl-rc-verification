// lib/pages/blacklist_management.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// A refined Blacklist Management UI with modern Flutter design patterns.
class BlacklistManagementPage extends StatefulWidget {
  const BlacklistManagementPage({super.key});

  @override
  State<BlacklistManagementPage> createState() => _BlacklistManagementPageState();
}

class _BlacklistManagementPageState extends State<BlacklistManagementPage>
    with SingleTickerProviderStateMixin {
  static const String _baseUrl =
      'https://ai-tollgate-surveillance-1.onrender.com';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchDLs();
    _fetchRCs();

    _dlScroll.addListener(() {
      if (_dlScroll.position.pixels > _dlScroll.position.maxScrollExtent - 200 && (_dlPage * _limit) < _dlTotal && !_loadingDL) {
        _fetchDLs(page: _dlPage + 1);
      }
    });

    _rcScroll.addListener(() {
      if (_rcScroll.position.pixels > _rcScroll.position.maxScrollExtent - 200 && (_rcPage * _limit) < _rcTotal && !_loadingRC) {
        _fetchRCs(page: _rcPage + 1);
      }
    });
  }

  @override
  void dispose() {
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
  /// Fetching functions
  /// -----------------------

  Future<void> _fetchDLs({int page = 1}) async {
    setState(() {
      _loadingDL = true;
      _errorDL = null;
    });

    final q = _dlSearchCtrl.text.trim();
    final uri = Uri.parse('$_baseUrl/api/blacklist/dl?page=$page&limit=$_limit${q.isNotEmpty ? '&search=${Uri.encodeQueryComponent(q)}' : ''}');
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final jsonBody = json.decode(res.body);
        final data = jsonBody['data'] as List? ?? [];
        final total = jsonBody['total'] as int? ?? data.length;
        setState(() {
          if (page == 1) {
            _dlList = List<Map<String, dynamic>>.from(data);
          } else {
            _dlList.addAll(List<Map<String, dynamic>>.from(data));
          }
          _dlTotal = total;
          _dlPage = page;
        });
      } else {
        setState(() => _errorDL = 'Failed to load DL blacklist (${res.statusCode})');
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
    final uri = Uri.parse('$_baseUrl/api/blacklist/rc?page=$page&limit=$_limit${q.isNotEmpty ? '&search=${Uri.encodeQueryComponent(q)}' : ''}');
    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final jsonBody = json.decode(res.body);
        final data = jsonBody['data'] as List? ?? [];
        final total = jsonBody['total'] as int? ?? data.length;
        setState(() {
          if (page == 1) {
            _rcList = List<Map<String, dynamic>>.from(data);
          } else {
            _rcList.addAll(List<Map<String, dynamic>>.from(data));
          }
          _rcTotal = total;
          _rcPage = page;
        });
      } else {
        setState(() => _errorRC = 'Failed to load RC blacklist (${res.statusCode})');
      }
    } catch (e) {
      setState(() => _errorRC = 'Error loading RC blacklist: $e');
    } finally {
      setState(() => _loadingRC = false);
    }
  }

  /// -----------------------
  /// Add & Remove
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

    final uri = Uri.parse('$_baseUrl/api/blacklist');

    try {
      final res = await http.post(uri, headers: {'Content-Type': 'application/json'}, body: json.encode(payload)).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 || res.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to blacklist successfully!'), backgroundColor: Colors.green));
        }
        if (type == 'dl') {
          _fetchDLs(page: 1);
        } else {
          _fetchRCs(page: 1);
        }
        Navigator.of(context).pop();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add: ${res.body.isNotEmpty ? res.body : res.statusCode}'), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _markValidAndRemove(String type, String id) async {
    final uri = Uri.parse('$_baseUrl/api/blacklist/$type/$id');
    try {
      final res = await http.put(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry marked valid (removed from blacklist)'), backgroundColor: Colors.green));
        }
        if (type == 'dl') {
          _fetchDLs(page: 1);
        } else {
          _fetchRCs(page: 1);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: ${res.statusCode}'), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Remove failed: $e'), backgroundColor: Colors.red));
      }
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
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(type == 'dl' ? Icons.no_accounts : Icons.directions_car, size: 60, color: Colors.black38),
        const SizedBox(height: 16),
        Text('No blacklisted ${type.toUpperCase()}s found.', style: const TextStyle(fontSize: 18, color: Colors.black54)),
      ]));
    }

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
          final title = type == 'dl' ? (entry['dl_number'] ?? entry['dl'] ?? 'Unknown DL') : (entry['regn_number'] ?? entry['rc_number'] ?? entry['regnNo'] ?? 'Unknown RC');
          final subtitle = _buildSubtitle(entry, type);
          final status = (entry['verification'] ?? entry['Verification'] ?? '').toString();

          return Dismissible(
            key: ValueKey(id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.delete_forever, color: Colors.red),
            ),
            confirmDismiss: (direction) async {
              return await _showConfirmDialog('Mark this ${type.toUpperCase()} as valid (remove from blacklist)?');
            },
            onDismissed: (_) => _markValidAndRemove(type, id),
            child: Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                leading: CircleAvatar(backgroundColor: type == 'dl' ? Colors.blue.shade50 : Colors.teal.shade50, child: Icon(type == 'dl' ? Icons.badge : Icons.directions_car, color: type == 'dl' ? Colors.blue : Colors.teal)),
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
    final reason = (entry['crime_involved'] ?? '').toString();

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
                  TextFormField(controller: _formCtrls['crime'], decoration: const InputDecoration(labelText: 'Reason for Blacklisting (optional)', border: OutlineInputBorder())),
                  const SizedBox(height: 16),
                  TextFormField(controller: _formCtrls['name'], decoration: InputDecoration(labelText: _typeCtrl.text == 'dl' ? 'Name (optional)' : 'Owner Name (optional)', border: const OutlineInputBorder())),
                  const SizedBox(height: 16),
                  if (_typeCtrl.text == 'dl') ...[
                    TextFormField(controller: _formCtrls['phone'], decoration: const InputDecoration(labelText: 'Phone Number (optional)', border: OutlineInputBorder())),
                  ],
                  if (_typeCtrl.text == 'rc') ...[
                    TextFormField(controller: _formCtrls['maker'], decoration: const InputDecoration(labelText: 'Maker Class (optional)', border: OutlineInputBorder())),
                    const SizedBox(height: 16),
                    TextFormField(controller: _formCtrls['vehicle'], decoration: const InputDecoration(labelText: 'Vehicle Class (optional)', border: OutlineInputBorder())),
                    const SizedBox(height: 16),
                    TextFormField(controller: _formCtrls['wheel'], decoration: const InputDecoration(labelText: 'Wheel Type (optional)', border: OutlineInputBorder())),
                  ],
                  const SizedBox(height: 24),
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
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('${type.toUpperCase()} Details'),
          content: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(const JsonEncoder.withIndent('  ').convert(item)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blacklist Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _dlSearchCtrl.clear();
                  _rcSearchCtrl.clear();
                  _fetchDLs(page: 1);
                  _fetchRCs(page: 1);
                }
              });
            },
          ),
        ],
        bottom: _isSearching
            ? PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _tabController.index == 0 ? _dlSearchCtrl : _rcSearchCtrl,
              decoration: InputDecoration(
                hintText: _tabController.index == 0 ? 'Search DL number...' : 'Search RC number...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    if (_tabController.index == 0) {
                      _dlSearchCtrl.clear();
                      _fetchDLs(page: 1);
                    } else {
                      _rcSearchCtrl.clear();
                      _fetchRCs(page: 1);
                    }
                  },
                ),
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(30))),
                filled: true,
                fillColor: Colors.grey[200],
                contentPadding: const EdgeInsets.symmetric(vertical: 0.0, horizontal: 16.0),
              ),
              onSubmitted: (_) {
                if (_tabController.index == 0) {
                  _fetchDLs(page: 1);
                } else {
                  _fetchRCs(page: 1);
                }
              },
            ),
          ),
        )
            : TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'DL ($_dlTotal)'),
            Tab(text: 'RC ($_rcTotal)'),
          ],
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          indicatorWeight: 3.0,
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddBottomSheet,
        child: const Icon(Icons.add),
      ),
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