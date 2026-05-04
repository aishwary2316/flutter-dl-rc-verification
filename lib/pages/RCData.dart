import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class RCDataPage extends StatefulWidget {
  final Map aishtrex;
  final Map backend;

  const RCDataPage({super.key, required this.aishtrex, required this.backend});

  @override
  State<RCDataPage> createState() => _RCDataPageState();
}

class _RCDataPageState extends State<RCDataPage>
    with SingleTickerProviderStateMixin {
  bool showRawJson = false;
  int jsonTab = 0;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Cache the future so it isn't re-triggered on every rebuild
  late final Future<List<String>> _vehicleImagesFuture;

  // ── DuckDuckGo Image Scraping ──────────────────────────────────────────────

  /// Master entry point — reads the full aishtrex map and builds the best query.
  String _buildVehicleQuery(Map vehicle) {
    // rc_vh_class_desc is the most reliable field: "Motor Car(LMV)", "Bus",
    // "Goods Vehicle", "Motor Cycle/Scooter", "Three Wheeler", etc.
    final classDesc  = vehicle['rc_vh_class_desc']?.toString() ?? '';
    final classShort = vehicle['rc_vhclass_desc']?.toString()  ?? '';
    final modelRaw   = vehicle['rc_maker_model']?.toString()   ?? '';
    final makerRaw   = vehicle['rc_maker_desc']?.toString()    ?? '';
    final colorRaw   = vehicle['rc_color']?.toString()         ?? '';
    final yearRaw    = vehicle['rc_manu_month_yr']?.toString() ?? '';

    final vtype  = _resolveVehicleType(classDesc, classShort, modelRaw, makerRaw);
    final maker  = _normalizeBrand(makerRaw, vtype);
    final model  = _extractModel(modelRaw, vtype);
    final color  = _normalizeColor(colorRaw);
    final year   = _extractYear(yearRaw);

    // Parts list — year and color are optional; drop when empty.
    // For three-wheelers the suffix is sharpened using the resolved model name
    // so "Bajaj RE auto rickshaw India" beats the old generic "auto rickshaw India".
    String suffix = vtype.searchSuffix;
    if (vtype == _VehicleType.threeWheeler) {
      // If the model already contains "rickshaw / e-rick" keep generic suffix,
      // otherwise append "auto" to anchor image results to the correct body style.
      final mLower = model.toLowerCase();
      if (mLower.contains('e-rick') || mLower.contains('e rick')) {
        suffix = 'electric rickshaw India';
      } else {
        suffix = 'auto rickshaw India';
      }
    }

    final parts = <String>[maker, model, color, year, suffix]
        .where((s) => s.isNotEmpty)
        .toList();

    return parts.join(' ');
  }

  // ── Vehicle type resolution ───────────────────────────────────────────────

  /// Canonical vehicle categories understood by the query builder.
  _VehicleType _resolveVehicleType(
      String classDesc,
      String classShort,
      String modelRaw,
      String makerRaw,
      ) {
    final cd = classDesc.toUpperCase();
    final cs = classShort.toUpperCase();
    final mo = modelRaw.toUpperCase();
    final ma = makerRaw.toUpperCase();

    // ── Two-wheelers ──
    if (cd.contains('MOTOR CYCLE') || cd.contains('MOTORCYCLE') ||
        cd.contains('SCOOTER')     || cs.contains('MOTOR CYCLE') ||
        cs.contains('MOTORCYCLE')  || cs.contains('SCOOTER')     ||
        cd.contains('MOPED')       || cs.contains('MOPED')) {
      return _VehicleType.motorcycle;
    }

    // ── Three-wheelers / Auto-rickshaw ──
    // Covers: class desc, short class, model name, and maker name.
    // Indian RTO data uses many variations: "THREE WHEELER", "3W", "AUTO",
    // "E-RICKSHAW", "TEMPU", or leaves class blank but model says "ALFA/APE/TREO" etc.
    if (cd.contains('THREE WHEELER') || cd.contains('3 WHEELER') || cd.contains('3W') ||
        cs.contains('THREE WHEELER') || cs.contains('3W') ||
        cd.contains('AUTO RICKSHAW')  || cs.contains('AUTO RICKSHAW') ||
        cd.contains('E-RICKSHAW')     || cs.contains('E-RICKSHAW') ||
        cd.contains('E RICKSHAW')     || cs.contains('E RICKSHAW') ||
        cd.contains('TEMPU')          || cs.contains('TEMPU') ||
        // Catch from model name when class is missing/vague
        mo.contains('AUTO')    || mo.contains('RICKSHAW') ||
        mo.contains('E-RICK')  || mo.contains('MAXIMA') ||
        mo.contains('TREO')    || mo.contains('CHAMPION') ||
        mo.contains('MAGIC')   || mo.contains('ALFA')  ||
        mo.contains('SUPRO')   && ma.contains('PIAGGIO') ||
        mo.contains('APE')     ||
        // Piaggio / Bajaj / TVS / Mahindra three-wheelers by maker+class hint
        (ma.contains('PIAGGIO') && !cd.contains('MOTOR CYCLE')) ||
        (ma.contains('BAJAJ')   && (cd.contains('THREE') || cd.contains('AUTO') || mo.contains('RE '))) ||
        (ma.contains('TVS')     && (cd.contains('THREE') || mo.contains('KING'))) ||
        (ma.contains('MAHINDRA') && (mo.contains('ALFA') || mo.contains('TREO') || mo.contains('CHAMPION')))) {
      return _VehicleType.threeWheeler;
    }

    // ── Buses ──
    if (cd.contains('BUS') || cs.contains('BUS') ||
        mo.contains('BUS') || ma.contains('BUS BODY')) {
      return _VehicleType.bus;
    }

    // ── Trucks / Heavy goods ──
    if (cd.contains('GOODS') || cs.contains('GOODS') ||
        cd.contains('TRUCK') || cs.contains('TRUCK') ||
        cd.contains('HGV')   || cd.contains('HMV')   ||
        mo.contains('TRUCK')) {
      return _VehicleType.truck;
    }

    // ── Tractors / Agricultural ──
    if (cd.contains('TRACTOR') || cs.contains('TRACTOR') ||
        mo.contains('TRACTOR') || ma.contains('TRACTOR')) {
      return _VehicleType.tractor;
    }

    // ── Light commercial / pickup / tempo ──
    if (cd.contains('LCV') || cs.contains('LCV') ||
        (cd.contains('LIGHT MOTOR VEHICLE') && (cd.contains('GOODS') || mo.contains('PICK UP') || mo.contains('PICKUP'))) ||
        mo.contains('ACE')   || mo.contains('YODHA') ||
        mo.contains('JEETO') || mo.contains('ULTRA') || mo.contains('BOLERO MAXI')) {
      return _VehicleType.lcv;
    }

    // ── Ambulance / specialised ──
    if (cd.contains('AMBULANCE') || mo.contains('AMBULANCE')) {
      return _VehicleType.ambulance;
    }

    // ── Default: car / LMV ──
    return _VehicleType.car;
  }

  // ── Brand normalisation (vehicle-type-aware) ─────────────────────────────

  String _normalizeBrand(String maker, _VehicleType vtype) {
    final u = maker.toUpperCase();

    // ── Three-wheeler brands (checked first — Bajaj/TVS/Mahindra also make cars) ──
    if (vtype == _VehicleType.threeWheeler) {
      if (u.contains('BAJAJ'))       return 'Bajaj';
      if (u.contains('PIAGGIO'))     return 'Piaggio';
      if (u.contains('TVS'))         return 'TVS';
      if (u.contains('MAHINDRA'))    return 'Mahindra';
      if (u.contains('ATUL'))        return 'Atul';
      if (u.contains('FORCE'))       return 'Force Motors';
      if (u.contains('SCOOTERS INDIA') || u.contains('SIL')) return 'Scooters India';
      if (u.contains('GREAVES'))     return 'Greaves';
      if (u.contains('EULER'))       return 'Euler';
      if (u.contains('YC'))          return 'YC Electric';
      // Generic fallback for 3W
      return maker.split(RegExp(r'[\s&]++')).first.trim();
    }

    // Two-wheeler brands
    if (vtype == _VehicleType.motorcycle) {
      if (u.contains('HERO'))       return 'Hero';
      if (u.contains('BAJAJ'))      return 'Bajaj';
      if (u.contains('TVS'))        return 'TVS';
      if (u.contains('HONDA'))      return 'Honda';
      if (u.contains('ROYAL ENFIELD') || u.contains('ROYAL')) return 'Royal Enfield';
      if (u.contains('YAMAHA'))     return 'Yamaha';
      if (u.contains('SUZUKI'))     return 'Suzuki';
      if (u.contains('KTM'))        return 'KTM';
      if (u.contains('JAWA'))       return 'Jawa';
    }
    // Bus/truck brands
    if (vtype == _VehicleType.bus || vtype == _VehicleType.truck) {
      if (u.contains('TATA'))       return 'Tata';
      if (u.contains('ASHOK'))      return 'Ashok Leyland';
      if (u.contains('LEYLAND'))    return 'Ashok Leyland';
      if (u.contains('EICHER'))     return 'Eicher';
      if (u.contains('MAHINDRA'))   return 'Mahindra';
      if (u.contains('VOLVO'))      return 'Volvo';
      if (u.contains('SCANIA'))     return 'Scania';
      if (u.contains('FORCE'))      return 'Force Motors';
      if (u.contains('SML'))        return 'SML Isuzu';
      if (u.contains('BHARAT'))     return 'Bharat Benz';
    }
    // Car / LMV brands (default)
    if (u.contains('MAHINDRA'))   return 'Mahindra';
    if (u.contains('MARUTI'))     return 'Maruti Suzuki';
    if (u.contains('HYUNDAI'))    return 'Hyundai';
    if (u.contains('TATA'))       return 'Tata';
    if (u.contains('TOYOTA'))     return 'Toyota';
    if (u.contains('KIA'))        return 'Kia';
    if (u.contains('HONDA'))      return 'Honda';
    if (u.contains('FORD'))       return 'Ford';
    if (u.contains('RENAULT'))    return 'Renault';
    if (u.contains('NISSAN'))     return 'Nissan';
    if (u.contains('VOLKSWAGEN') || u.contains('VW')) return 'Volkswagen';
    if (u.contains('SKODA'))      return 'Skoda';
    if (u.contains('MG'))         return 'MG';
    if (u.contains('JEEP'))       return 'Jeep';
    if (u.contains('BMW'))        return 'BMW';
    if (u.contains('MERCEDES'))   return 'Mercedes';
    if (u.contains('AUDI'))       return 'Audi';
    if (u.contains('CITROEN'))    return 'Citroen';
    if (u.contains('ISUZU'))      return 'Isuzu';
    // Generic fallback — first non-trivial word
    return maker.split(RegExp(r'[\s&]++')).first.trim();
  }

  // ── Model extraction (vehicle-type-aware) ────────────────────────────────

  String _extractModel(String model, _VehicleType vtype) {
    final u = model.toUpperCase();

    if (vtype == _VehicleType.motorcycle) {
      if (u.contains('SPLENDOR'))   return 'Splendor';
      if (u.contains('PASSION'))    return 'Passion';
      if (u.contains('GLAMOUR'))    return 'Glamour';
      if (u.contains('XTREME'))     return 'Xtreme';
      if (u.contains('PULSAR'))     return 'Pulsar';
      if (u.contains('DOMINAR'))    return 'Dominar';
      if (u.contains('AVENGER'))    return 'Avenger';
      if (u.contains('JUPITER'))    return 'Jupiter';
      if (u.contains('NTORQ'))      return 'NTORQ';
      if (u.contains('ACTIVA'))     return 'Activa';
      if (u.contains('SHINE'))      return 'Shine';
      if (u.contains('UNICORN'))    return 'Unicorn';
      if (u.contains('BULLET'))     return 'Bullet';
      if (u.contains('CLASSIC'))    return 'Classic 350';
      if (u.contains('METEOR'))     return 'Meteor';
      if (u.contains('HIMALAYAN'))  return 'Himalayan';
      if (u.contains('R15'))        return 'R15';
      if (u.contains('FZ'))         return 'FZ';
      if (u.contains('MT15'))       return 'MT-15';
      if (u.contains('DUKE'))       return 'Duke';
      if (u.contains('ADVENTURE'))  return 'Adventure';
    }

    if (vtype == _VehicleType.bus) {
      if (u.contains('STARBUS'))    return 'Starbus';
      if (u.contains('CITY RIDE'))  return 'City Ride';
      if (u.contains('ULTRA'))      return 'Ultra';
      if (u.contains('LP'))         return 'LP';    // Tata LP series
      if (u.contains('LPO'))        return 'LPO';
      if (u.contains('4020'))       return '4020';  // AL 4020
      if (u.contains('4923'))       return '4923';
      if (u.contains('9400'))       return '9400';  // Scania
      if (u.contains('TRAVELLER'))  return 'Traveller';
      if (u.contains('WINGER'))     return 'Winger';
      // Return first two words of model (e.g. "LP 1512")
      final words = model.trim().split(RegExp(r'\s+'));
      return words.take(2).join(' ');
    }

    if (vtype == _VehicleType.truck) {
      // Return first two words — truck model codes matter ("LPT 2518", "407")
      final words = model.trim().split(RegExp(r'\s+'));
      return words.take(2).join(' ');
    }

    if (vtype == _VehicleType.threeWheeler) {
      // Bajaj three-wheelers
      if (u.contains('RE COMPACT'))   return 'RE Compact';
      if (u.contains('RE 4S'))        return 'RE 4S';
      if (u.contains('RE'))           return 'RE';          // Bajaj RE series (most common)
      if (u.contains('MAXIMA Z'))     return 'Maxima Z';
      if (u.contains('MAXIMA C'))     return 'Maxima C';
      if (u.contains('MAXIMA'))       return 'Maxima';
      // Piaggio three-wheelers
      if (u.contains('APE CITY'))     return 'Ape City';
      if (u.contains('APE E-CITY'))   return 'Ape E-City';
      if (u.contains('APE HT'))       return 'Ape HT';
      if (u.contains('APE DX'))       return 'Ape DX';
      if (u.contains('APE AUTO'))     return 'Ape Auto';
      if (u.contains('APE XTRA'))     return 'Ape Xtra';
      if (u.contains('APE'))          return 'Ape';
      if (u.contains('PORTER'))       return 'Porter';
      // TVS three-wheelers
      if (u.contains('KING DURAMAX')) return 'King Duramax';
      if (u.contains('KING DELUXE'))  return 'King Deluxe';
      if (u.contains('KING'))         return 'King';
      // Mahindra three-wheelers
      if (u.contains('TREO ZIPPEE'))  return 'Treo Zippee';
      if (u.contains('TREO'))         return 'Treo';
      if (u.contains('ALFA LOAD'))    return 'Alfa Load';
      if (u.contains('ALFA PLUS'))    return 'Alfa Plus';
      if (u.contains('ALFA'))         return 'Alfa';
      if (u.contains('CHAMPION'))     return 'Champion';
      if (u.contains('SUPRO'))        return 'Supro';
      // Atul three-wheelers
      if (u.contains('GEM'))          return 'Gem';
      if (u.contains('SHAKTI'))       return 'Shakti';
      if (u.contains('SMART'))        return 'Smart';
      if (u.contains('ELITE'))        return 'Elite';
      // Force Motors three-wheelers
      if (u.contains('TRUMP'))        return 'Trump';
      // E-rickshaws (generic class)
      if (u.contains('E-RICK') || u.contains('ERICKSHAW') || u.contains('E RICK')) return 'E-Rickshaw';
      if (u.contains('MAGIC'))        return 'Magic';
      // First word fallback
      return model.trim().split(RegExp(r'\s+')).first;
    }

    // ── Car models ──
    // Mahindra
    if (u.contains('THAR'))       return 'Thar';
    if (u.contains('SCORPIO N'))  return 'Scorpio-N';
    if (u.contains('SCORPIO'))    return 'Scorpio';
    if (u.contains('BOLERO'))     return 'Bolero';
    if (u.contains('XUV 3XO') || u.contains('XUV3XO')) return 'XUV 3XO';
    if (u.contains('XUV700'))     return 'XUV700';
    if (u.contains('XUV500'))     return 'XUV500';
    if (u.contains('XUV400'))     return 'XUV400';
    if (u.contains('XUV300'))     return 'XUV300';
    if (u.contains('XUV'))        return 'XUV';
    if (u.contains('BE 6'))       return 'BE 6';
    if (u.contains('XEV 9E') || u.contains('XEV9E')) return 'XEV 9E';
    // Hyundai
    if (u.contains('CRETA'))      return 'Creta';
    if (u.contains('VENUE'))      return 'Venue';
    if (u.contains('I20'))        return 'i20';
    if (u.contains('I10'))        return 'Grand i10';
    if (u.contains('VERNA'))      return 'Verna';
    if (u.contains('TUCSON'))     return 'Tucson';
    if (u.contains('ALCAZAR'))    return 'Alcazar';
    if (u.contains('IONIQ'))      return 'Ioniq';
    if (u.contains('EXTER'))      return 'Exter';
    // Maruti
    if (u.contains('SWIFT'))      return 'Swift';
    if (u.contains('BALENO'))     return 'Baleno';
    if (u.contains('BREZZA'))     return 'Brezza';
    if (u.contains('ERTIGA'))     return 'Ertiga';
    if (u.contains('DZIRE'))      return 'Dzire';
    if (u.contains('ALTO'))       return 'Alto';
    if (u.contains('WAGON'))      return 'WagonR';
    if (u.contains('FRONX'))      return 'Fronx';
    if (u.contains('JIMNY'))      return 'Jimny';
    if (u.contains('GRAND VITARA') || u.contains('GRANDVITARA')) return 'Grand Vitara';
    if (u.contains('INVICTO'))    return 'Invicto';
    // Tata
    if (u.contains('NEXON'))      return 'Nexon';
    if (u.contains('HARRIER'))    return 'Harrier';
    if (u.contains('SAFARI'))     return 'Safari';
    if (u.contains('PUNCH'))      return 'Punch';
    if (u.contains('TIAGO'))      return 'Tiago';
    if (u.contains('CURVV'))      return 'Curvv';
    if (u.contains('ALTROZ'))     return 'Altroz';
    // Toyota
    if (u.contains('INNOVA CRYSTA') || u.contains('CRYSTA')) return 'Innova Crysta';
    if (u.contains('INNOVA HYCROSS') || u.contains('HYCROSS')) return 'Innova HyCross';
    if (u.contains('INNOVA'))     return 'Innova';
    if (u.contains('FORTUNER'))   return 'Fortuner';
    if (u.contains('GLANZA'))     return 'Glanza';
    if (u.contains('URBAN CRUISER') || u.contains('HYRYDER')) return 'Urban Cruiser Hyryder';
    if (u.contains('CAMRY'))      return 'Camry';
    if (u.contains('VELLFIRE'))   return 'Vellfire';
    // Kia
    if (u.contains('SELTOS'))     return 'Seltos';
    if (u.contains('SONET'))      return 'Sonet';
    if (u.contains('CARENS'))     return 'Carens';
    if (u.contains('EV6'))        return 'EV6';
    if (u.contains('EV9'))        return 'EV9';
    // Honda
    if (u.contains('CITY'))       return 'City';
    if (u.contains('AMAZE'))      return 'Amaze';
    if (u.contains('ELEVATE'))    return 'Elevate';
    if (u.contains('WRV') || u.contains('WR-V')) return 'WR-V';
    // Skoda / VW / Jeep / MG / others
    if (u.contains('KUSHAQ'))     return 'Kushaq';
    if (u.contains('SLAVIA'))     return 'Slavia';
    if (u.contains('SUPERB'))     return 'Superb';
    if (u.contains('OCTAVIA'))    return 'Octavia';
    if (u.contains('TAIGUN'))     return 'Taigun';
    if (u.contains('VIRTUS'))     return 'Virtus';
    if (u.contains('COMPASS'))    return 'Jeep Compass';
    if (u.contains('MERIDIAN'))   return 'Jeep Meridian';
    if (u.contains('WRANGLER'))   return 'Jeep Wrangler';
    if (u.contains('HECTOR'))     return 'MG Hector';
    if (u.contains('ASTOR'))      return 'MG Astor';
    if (u.contains('COMET'))      return 'MG Comet';
    if (u.contains('GLOSTER'))    return 'MG Gloster';
    // Renault / Nissan
    if (u.contains('KWID'))       return 'Kwid';
    if (u.contains('KIGER'))      return 'Kiger';
    if (u.contains('TRIBER'))     return 'Triber';
    if (u.contains('DUSTER'))     return 'Duster';
    if (u.contains('MAGNITE'))    return 'Magnite';
    // Fall back to first meaningful word of model string
    return model.trim().split(RegExp(r'\s+')).first;
  }

  String _normalizeColor(String color) {
    final u = color.toUpperCase();
    if (u.contains('WHT') || u.contains('WHITE'))              return 'white';
    if (u.contains('BLK') || u.contains('BLACK'))              return 'black';
    if (u.contains('RED'))                                      return 'red';
    if (u.contains('BLU') || u.contains('BLUE'))               return 'blue';
    if (u.contains('GRY') || u.contains('GREY') || u.contains('GRAY')) return 'grey';
    if (u.contains('SLV') || u.contains('SILV'))               return 'silver';
    if (u.contains('GRN') || u.contains('GREEN'))              return 'green';
    if (u.contains('YLW') || u.contains('YELL'))               return 'yellow';
    if (u.contains('ORG') || u.contains('ORAN'))               return 'orange';
    if (u.contains('BRN') || u.contains('BROW'))               return 'brown';
    if (u.contains('MRN') || u.contains('MARO'))               return 'maroon';
    if (u.contains('GOLD') || u.contains('GLD'))               return 'golden';
    if (u.contains('BEIGE') || u.contains('BGE'))              return 'beige';
    if (u.contains('WINE'))                                     return 'wine red';
    // Coded strings like "A3EVRSTWHT" — already matched above via 'WHT'
    // Any other opaque code — omit rather than pollute
    return '';
  }

  String _extractYear(String date) {
    if (date.contains('/')) return date.split('/').last.trim();
    final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(date);
    return match?.group(0) ?? '';
  }

  /// Fetches up to [limit] image URLs from DuckDuckGo image search.
  Future<List<String>> _fetchVehicleImages({int limit = 10}) async {
    final vehicle = widget.aishtrex;
    final query   = _buildVehicleQuery(vehicle);
    final encoded = Uri.encodeComponent(query);

    // Step 1 – obtain the vqd token DuckDuckGo requires
    final tokenRes = await http.get(
      Uri.parse('https://duckduckgo.com/?q=$encoded'),
      headers: {'User-Agent': 'Mozilla/5.0'},
    );
    final token =
    RegExp(r'vqd=([\d-]+)').firstMatch(tokenRes.body)?.group(1);
    if (token == null) throw Exception('DuckDuckGo: failed to obtain vqd token');

    // Step 2 – query the image endpoint
    final imgRes = await http.get(
      Uri.parse(
          'https://duckduckgo.com/i.js?l=us-en&o=json&q=$encoded&vqd=$token'),
      headers: {
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://duckduckgo.com/',
      },
    );

    final data    = jsonDecode(imgRes.body) as Map;
    final results = (data['results'] as List?) ?? [];
    return results
        .map<String>((img) => img['image'].toString())
        .where((url) => url.isNotEmpty)
        .take(limit)
        .toList();
  }

  // ── color derived from rc_color field ──────────────────────────────────────
  Color _accentFromVehicleColor(String? colorStr) {
    if (colorStr == null) return const Color(0xFF1E40AF);
    final s = colorStr.toLowerCase();
    if (s.contains('red'))                           return const Color(0xFFB91C1C);
    if (s.contains('blue') || s.contains('blu'))    return const Color(0xFF1D4ED8);
    if (s.contains('green') || s.contains('grn'))   return const Color(0xFF15803D);
    if (s.contains('black') || s.contains('blk'))   return const Color(0xFF1F2937);
    if (s.contains('white') || s.contains('wht'))   return const Color(0xFF475569);
    if (s.contains('silver') || s.contains('grey') ||
        s.contains('gray')  || s.contains('gry'))   return const Color(0xFF64748B);
    if (s.contains('yellow') || s.contains('ylw'))  return const Color(0xFFB45309);
    if (s.contains('orange') || s.contains('org'))  return const Color(0xFFC2410C);
    if (s.contains('brown')  || s.contains('maroon')) return const Color(0xFF92400E);
    if (s.contains('purple') || s.contains('violet')) return const Color(0xFF6D28D9);
    if (s.contains('pink'))                          return const Color(0xFFBE185D);
    return const Color(0xFF1E40AF);
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _fadeController.forward();

    // Fire the image fetch once and cache the result
    _vehicleImagesFuture = _fetchVehicleImages();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  // ── Expiry / validity helpers ──────────────────────────────────────────────

  /// Parses common Indian date formats: "25-Apr-2039", "25-04-2039",
  /// "13-03-2039", "2/2024" (manufacture month/year — treated differently).
  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    raw = raw.trim();

    // "25-Apr-2039"
    final long = RegExp(
        r'^(\d{1,2})[-/]([A-Za-z]{3,9})[-/](\d{4})$').firstMatch(raw);
    if (long != null) {
      const months = {
        'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5,  'jun': 6,
        'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10,'nov': 11, 'dec': 12,
      };
      final m = months[long.group(2)!.toLowerCase().substring(0, 3)];
      if (m != null) {
        return DateTime(int.parse(long.group(3)!), m, int.parse(long.group(1)!));
      }
    }

    // "25-04-2039" or "13-03-2039"
    final numeric = RegExp(r'^(\d{1,2})[-/](\d{1,2})[-/](\d{4})$').firstMatch(raw);
    if (numeric != null) {
      return DateTime(
        int.parse(numeric.group(3)!),
        int.parse(numeric.group(2)!),
        int.parse(numeric.group(1)!),
      );
    }

    return null;
  }

  /// Returns the expiry state of a date string.
  _ExpiryState _expiryState(String? raw) {
    final date = _parseDate(raw);
    if (date == null) return _ExpiryState.unknown;
    final now  = DateTime.now();
    final diff = date.difference(now).inDays;
    if (diff < 0)   return _ExpiryState.expired;
    if (diff <= 30) return _ExpiryState.expiringSoon;
    return _ExpiryState.valid;
  }

  /// Collects all compliance issues for the vehicle — used in the banner.
  List<_ComplianceIssue> _collectIssues(Map a, Map b) {
    final issues = <_ComplianceIssue>[];
    void check(String label, String? dateStr) {
      final state = _expiryState(dateStr);
      if (state == _ExpiryState.expired) {
        issues.add(_ComplianceIssue(label: label, date: dateStr, expired: true));
      } else if (state == _ExpiryState.expiringSoon) {
        issues.add(_ComplianceIssue(label: label, date: dateStr, expired: false));
      }
    }

    check('RC Registration', a['rc_regn_upto']?.toString());
    check('Fitness Certificate', a['rc_fit_upto']?.toString());
    check('PUCC Certificate', a['rc_pucc_upto']?.toString());
    check('Road Tax', a['rc_tax_upto']?.toString());

    // RC status field
    final status = a['rc_status']?.toString().toUpperCase() ?? '';
    if (status.isNotEmpty && status != 'ACTIVE') {
      issues.add(_ComplianceIssue(
          label: 'RC Status', date: status, expired: true, isStatus: true));
    }

    // Blacklist
    final bl = a['rc_blacklist_status']?.toString().trim() ?? '';
    if (bl.isNotEmpty) {
      issues.add(_ComplianceIssue(
          label: 'Blacklisted', date: bl, expired: true, isStatus: true));
    }

    // Crime
    final crime = b['crime_involved']?.toString().trim() ?? '';
    if (crime.isNotEmpty && crime.toLowerCase() != 'no' && crime.toLowerCase() != 'false') {
      issues.add(_ComplianceIssue(
          label: 'Crime Record', date: crime, expired: true, isStatus: true));
    }

    return issues;
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  /// Plain info row — no expiry logic.
  Widget _infoRow(String label, dynamic value,
      {IconData? icon, Color? accent}) {
    if (value == null || value.toString().trim().isEmpty) return const SizedBox();
    return _buildRow(
      label: label,
      value: value.toString(),
      icon: icon,
      accent: accent ?? const Color(0xFF1E40AF),
      valueColor: const Color(0xFF1A1A2E),
      iconBg: (accent ?? const Color(0xFF1E40AF)).withOpacity(0.1),
    );
  }

  /// Date row — automatically colours value based on expiry state.
  Widget _dateRow(String label, dynamic value,
      {IconData? icon, Color? accent}) {
    if (value == null || value.toString().trim().isEmpty) return const SizedBox();
    final state  = _expiryState(value.toString());
    final Color valueColor;
    final Color iconBg;
    final Color effectiveAccent = accent ?? const Color(0xFF1E40AF);

    switch (state) {
      case _ExpiryState.expired:
        valueColor = const Color(0xFFDC2626);
        iconBg     = const Color(0xFFDC2626).withOpacity(0.1);
      case _ExpiryState.expiringSoon:
        valueColor = const Color(0xFFD97706);
        iconBg     = const Color(0xFFD97706).withOpacity(0.1);
      case _ExpiryState.valid:
      case _ExpiryState.unknown:
        valueColor = const Color(0xFF1A1A2E);
        iconBg     = effectiveAccent.withOpacity(0.1);
    }

    return _buildRow(
      label: label,
      value: value.toString(),
      icon: icon,
      accent: state == _ExpiryState.expired
          ? const Color(0xFFDC2626)
          : state == _ExpiryState.expiringSoon
          ? const Color(0xFFD97706)
          : effectiveAccent,
      valueColor: valueColor,
      iconBg: iconBg,
      suffix: state == _ExpiryState.expired
          ? _pill('EXPIRED', const Color(0xFFDC2626))
          : state == _ExpiryState.expiringSoon
          ? _pill('EXPIRING SOON', const Color(0xFFD97706))
          : null,
    );
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.4)),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.4,
      ),
    ),
  );

  Widget _buildRow({
    required String label,
    required String value,
    IconData? icon,
    required Color accent,
    required Color valueColor,
    required Color iconBg,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null)
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: accent),
            ),
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: valueColor,
                    ),
                  ),
                ),
                if (suffix != null) ...[
                  const SizedBox(width: 6),
                  suffix,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(
      height: 1, thickness: 0.5, color: Colors.grey.shade200);

  Widget _section({
    required String title,
    required IconData sectionIcon,
    required List<Widget> children,
    required Color accent,
    bool hasAlert = false,
  }) {
    final filtered = children.where((w) => w is! SizedBox).toList();
    if (filtered.isEmpty) return const SizedBox();

    // Intersperse dividers
    final withDividers = <Widget>[];
    for (var i = 0; i < filtered.length; i++) {
      withDividers.add(filtered[i]);
      if (i < filtered.length - 1) withDividers.add(_divider());
    }

    final headerColor = hasAlert ? const Color(0xFFDC2626) : accent;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: hasAlert
            ? Border.all(color: const Color(0xFFDC2626).withOpacity(0.35), width: 1)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: headerColor.withOpacity(0.07),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(sectionIcon, size: 18, color: headerColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: headerColor,
                    letterSpacing: 0.5,
                  ),
                ),
                if (hasAlert) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'ATTENTION',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFDC2626),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Column(children: withDividers),
          ),
        ],
      ),
    );
  }

  Widget _jsonViewer(Map data) {
    final json = const JsonEncoder.withIndent('  ').convert(data);
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF0D1117),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF161B22),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.data_object,
                    size: 14, color: Color(0xFF58A6FF)),
                const SizedBox(width: 6),
                Text(
                  jsonTab == 0 ? 'aishtrex.json' : 'backend.json',
                  style: const TextStyle(
                    color: Color(0xFF8B949E),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: json));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  child: const Icon(Icons.copy,
                      size: 16, color: Color(0xFF8B949E)),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: SelectableText(
                json,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12.5,
                  color: Color(0xFF79C0FF),
                  height: 1.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero image widget (DuckDuckGo scraped) ─────────────────────────────────

  Widget _heroImage(Color accent, String? colorStr) {
    const height = 220.0;

    return FutureBuilder<List<String>>(
      future: _vehicleImagesFuture,
      builder: (context, snapshot) {
        // ── Loading state ──
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: height,
            color: accent.withOpacity(0.12),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: accent),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Loading vehicle image…',
                    style: TextStyle(
                        color: accent.withOpacity(0.7), fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }

        // ── Error / empty state ──
        if (snapshot.hasError ||
            !snapshot.hasData ||
            snapshot.data!.isEmpty) {
          return _fallbackImage(height, accent);
        }

        // ── Success: try URLs in order, fall through on failure ──
        return _NetworkImageWithFallback(
          urls: snapshot.data!,
          height: height,
          fallback: _fallbackImage(height, accent),
        );
      },
    );
  }

  Widget _fallbackImage(double height, Color accent) {
    return Container(
      height: height,
      width: double.infinity,
      color: accent.withOpacity(0.15),
      child: Center(
        child: Icon(
          Icons.directions_car_rounded,
          size: 72,
          color: accent.withOpacity(0.4),
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final a = widget.aishtrex;
    final b = widget.backend;
    final dealer = a['rc_dealer'];

    final colorStr = a['rc_color']?.toString();
    final modelStr = a['rc_maker_model']?.toString();
    final accent   = _accentFromVehicleColor(colorStr);

    final issues = _collectIssues(a, b);
    final hasIssues = issues.isNotEmpty;

    // Pre-compute which sections have date alerts so the section header can show ATTENTION
    bool regHasAlert = _expiryState(a['rc_regn_upto']?.toString()) != _ExpiryState.valid &&
        _expiryState(a['rc_regn_upto']?.toString()) != _ExpiryState.unknown;
    bool compHasAlert =
        _expiryState(a['rc_fit_upto']?.toString())  != _ExpiryState.valid &&
            _expiryState(a['rc_fit_upto']?.toString())  != _ExpiryState.unknown ||
            _expiryState(a['rc_pucc_upto']?.toString()) != _ExpiryState.valid &&
                _expiryState(a['rc_pucc_upto']?.toString()) != _ExpiryState.unknown ||
            _expiryState(a['rc_tax_upto']?.toString())  != _ExpiryState.valid &&
                _expiryState(a['rc_tax_upto']?.toString())  != _ExpiryState.unknown;

    final blacklist  = a['rc_blacklist_status']?.toString().trim() ?? '';
    final rcStatus   = a['rc_status']?.toString().toUpperCase()    ?? '';
    final crime      = b['crime_involved']?.toString().trim()      ?? '';
    bool secHasAlert = blacklist.isNotEmpty ||
        (rcStatus.isNotEmpty && rcStatus != 'ACTIVE') ||
        (crime.isNotEmpty && crime.toLowerCase() != 'no' && crime.toLowerCase() != 'false');

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: accent,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vehicle Details',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
            if (a['rc_regn_no'] != null)
              Text(
                a['rc_regn_no'].toString(),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w400),
              ),
          ],
        ),
        actions: [
          if (hasIssues)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${issues.length} ISSUE${issues.length > 1 ? 'S' : ''}',
                    style: const TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              showRawJson ? Icons.article_outlined : Icons.code,
              color: Colors.white,
            ),
            tooltip: showRawJson ? 'Show Details' : 'Raw JSON',
            onPressed: () => setState(() => showRawJson = !showRawJson),
          ),
        ],
      ),

      body: showRawJson
          ? Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            child: Row(
              children: [
                _jsonTabChip('AishTrex', 0, accent),
                const SizedBox(width: 10),
                _jsonTabChip('Backend', 1, accent),
              ],
            ),
          ),
          Expanded(
            child: jsonTab == 0
                ? _jsonViewer(widget.aishtrex)
                : _jsonViewer(widget.backend),
          ),
        ],
      )
          : FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // ── Hero image ──────────────────────────────────────────
              Stack(
                children: [
                  SizedBox(
                    height: 220,
                    width: double.infinity,
                    child: _heroImage(accent, colorStr),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withOpacity(0.55),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.image_search,
                              color: Colors.white70, size: 11),
                          SizedBox(width: 4),
                          Text('Web Image',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                  if (colorStr != null && colorStr.isNotEmpty)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.45),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              colorStr,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 14,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (modelStr != null)
                          Text(
                            modelStr,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        if (a['rc_owner_name'] != null)
                          Text(
                            a['rc_owner_name'].toString(),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),

              // ── Quick status banner ─────────────────────────────────
              _quickStatusBanner(issues, accent),

              // ── Sections ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  children: [

                    // BASIC DETAILS
                    _section(
                      title: 'BASIC DETAILS',
                      sectionIcon: Icons.directions_car_rounded,
                      accent: accent,
                      children: [
                        _infoRow('Owner', a['rc_owner_name'],
                            icon: Icons.person_outline, accent: accent),
                        _infoRow('Father / Guardian', a['rc_father_name'],
                            icon: Icons.people_outline, accent: accent),
                        _infoRow('Reg. Number', a['rc_regn_no'],
                            icon: Icons.confirmation_number_outlined, accent: accent),
                        _infoRow('Vehicle Class', a['rc_vh_class_desc'] ?? a['rc_vhclass_desc'],
                            icon: Icons.category_outlined, accent: accent),
                        _infoRow('Fuel Type', a['rc_fuel_desc'],
                            icon: Icons.local_gas_station_outlined, accent: accent),
                        _infoRow('Color', a['rc_color'],
                            icon: Icons.palette_outlined, accent: accent),
                        _infoRow('Manufacturer', a['rc_maker_desc'],
                            icon: Icons.factory_outlined, accent: accent),
                        _infoRow('Model', a['rc_maker_model'],
                            icon: Icons.car_repair_outlined, accent: accent),
                        _infoRow('Manufactured', a['rc_manu_month_yr'],
                            icon: Icons.precision_manufacturing_outlined, accent: accent),
                        _infoRow('Body Type', a['rc_body_type_desc'] ?? a['rc_body_type'],
                            icon: Icons.view_in_ar_outlined, accent: accent),
                        _infoRow('Norms', a['rc_norms_desc'],
                            icon: Icons.eco_outlined, accent: accent),
                        _infoRow('Seating Capacity', a['rc_seat_cap'],
                            icon: Icons.event_seat_outlined, accent: accent),
                        _infoRow('Unladen Weight', a['rc_unld_wt'],
                            icon: Icons.monitor_weight_outlined, accent: accent),
                        _infoRow('Gross Weight', a['rc_gross_wt'],
                            icon: Icons.monitor_weight_outlined, accent: accent),
                        _infoRow('Cylinders', a['rc_cyls_no'],
                            icon: Icons.settings_input_component_outlined, accent: accent),
                        _infoRow('Wheelbase', a['rc_wheelbase'],
                            icon: Icons.straighten_outlined, accent: accent),
                        _infoRow('Cubic Capacity', a['rc_cubic_cap'],
                            icon: Icons.compress_outlined, accent: accent),
                        _infoRow('Sleeper Capacity', a['rc_slpr_cap'],
                            icon: Icons.airline_seat_flat_outlined, accent: accent),
                        _infoRow('Standing Capacity', a['rc_stand_cap'],
                            icon: Icons.people_alt_outlined, accent: accent),
                      ],
                    ),

                    // OWNER & ADDRESS
                    _section(
                      title: 'OWNER & ADDRESS',
                      sectionIcon: Icons.home_outlined,
                      accent: accent,
                      children: [
                        _infoRow('Present Address', a['rc_present_address'],
                            icon: Icons.location_on_outlined, accent: accent),
                        _infoRow('Permanent Address', a['rc_permanent_address'],
                            icon: Icons.home_work_outlined, accent: accent),
                        _infoRow('State', a['rc_currentadd_statename'],
                            icon: Icons.map_outlined, accent: accent),
                        _infoRow('Pincode', a['rc_currentadd_pincode'],
                            icon: Icons.pin_drop_outlined, accent: accent),
                        _infoRow('Mobile', a['rc_mobile_no'],
                            icon: Icons.phone_outlined, accent: accent),
                      ],
                    ),

                    // REGISTRATION INFO
                    _section(
                      title: 'REGISTRATION',
                      sectionIcon: Icons.assignment_outlined,
                      accent: accent,
                      hasAlert: regHasAlert,
                      children: [
                        _infoRow('Registered At', a['rc_registered_at'],
                            icon: Icons.location_city_outlined, accent: accent),
                        _infoRow('Purchase Date', a['rc_purchase_dt'],
                            icon: Icons.shopping_cart_outlined, accent: accent),
                        _dateRow('Valid Until', a['rc_regn_upto'],
                            icon: Icons.event_outlined, accent: accent),
                        _infoRow('RC Status', a['rc_status'],
                            icon: Icons.verified_outlined, accent: accent),
                        _infoRow('Status As On', a['rc_status_as_on'],
                            icon: Icons.calendar_today_outlined, accent: accent),
                        _infoRow('Non-Use Declaration', a['rc_non_use'],
                            icon: Icons.do_not_disturb_outlined, accent: accent),
                        _infoRow('NOC Date', a['rc_noc_dt'],
                            icon: Icons.note_outlined, accent: accent),
                        _infoRow('NOC Issued To', a['rc_noc_issued_to'],
                            icon: Icons.person_pin_outlined, accent: accent),
                        _infoRow('Hypothecation', a['rc_hypothecation_by'],
                            icon: Icons.account_balance_outlined, accent: accent),
                      ],
                    ),

                    // COMPLIANCE & VALIDITY
                    _section(
                      title: 'COMPLIANCE & VALIDITY',
                      sectionIcon: Icons.verified_user_outlined,
                      accent: accent,
                      hasAlert: compHasAlert,
                      children: [
                        _dateRow('Fitness Valid Until', a['rc_fit_upto'],
                            icon: Icons.health_and_safety_outlined, accent: accent),
                        _dateRow('Road Tax Valid Until', a['rc_tax_upto'],
                            icon: Icons.receipt_long_outlined, accent: accent),
                        _infoRow('Tax Mode', a['rc_tax_mode'],
                            icon: Icons.payment_outlined, accent: accent),
                        _dateRow('PUCC Valid Until', a['rc_pucc_upto'],
                            icon: Icons.air_outlined, accent: accent),
                        _infoRow('PUCC Number', a['rc_pucc_no'],
                            icon: Icons.numbers_outlined, accent: accent),
                        _infoRow('PUCC Issued By', a['rc_pucc_issued_by'],
                            icon: Icons.store_outlined, accent: accent),
                        _dateRow('Insurance Valid Until', a['rc_insurance_upto'],
                            icon: Icons.security_outlined, accent: accent),
                        _infoRow('Insurance Company', a['rc_insurance_comp'],
                            icon: Icons.business_outlined, accent: accent),
                        _infoRow('Insurance Policy No.', a['rc_insurance_policy_no'],
                            icon: Icons.policy_outlined, accent: accent),
                        _dateRow('Permit Valid Until', a['rc_permit_upto'],
                            icon: Icons.approval_outlined, accent: accent),
                        _infoRow('Permit Type', a['rc_permit_type'],
                            icon: Icons.card_membership_outlined, accent: accent),
                        _infoRow('Permit No.', a['rc_permit_no'],
                            icon: Icons.confirmation_num_outlined, accent: accent),
                        _dateRow('National Permit Valid', a['rc_np_upto'],
                            icon: Icons.public_outlined, accent: accent),
                        _infoRow('National Permit No.', a['rc_np_no'],
                            icon: Icons.numbers_outlined, accent: accent),
                      ],
                    ),

                    // VEHICLE IDENTIFICATION
                    _section(
                      title: 'VEHICLE IDENTIFICATION',
                      sectionIcon: Icons.fingerprint,
                      accent: accent,
                      children: [
                        _infoRow('Engine No.', a['rc_eng_no'],
                            icon: Icons.settings_outlined, accent: accent),
                        _infoRow('Chassis No.', a['rc_chasi_no'],
                            icon: Icons.build_outlined, accent: accent),
                        _infoRow('Vehicle Type', a['rc_vh_class'],
                            icon: Icons.directions_car_outlined, accent: accent),
                        _infoRow('Sale Amount', a['rc_sale_amt'] != null &&
                            a['rc_sale_amt'].toString() != '0.0' &&
                            a['rc_sale_amt'].toString() != '0'
                            ? '₹ ${a['rc_sale_amt']}'
                            : null,
                            icon: Icons.currency_rupee_outlined, accent: accent),
                      ],
                    ),

                    // DEALER INFORMATION
                    if (dealer != null)
                      _section(
                        title: 'DEALER INFORMATION',
                        sectionIcon: Icons.store_outlined,
                        accent: accent,
                        children: [
                          _infoRow('Dealer Name', dealer['dealer_name'],
                              icon: Icons.storefront_outlined, accent: accent),
                          _infoRow('Code', dealer['dealer_code'],
                              icon: Icons.qr_code_outlined, accent: accent),
                          _infoRow('Address', [
                            dealer['dealer_add1'],
                            dealer['dealer_add2']
                          ].where((s) => s != null && s.toString().trim().isNotEmpty)
                              .join(', '),
                              icon: Icons.location_on_outlined, accent: accent),
                          _infoRow('Pincode', dealer['dealer_pincode'],
                              icon: Icons.pin_drop_outlined, accent: accent),
                          _infoRow('State', dealer['dealer_state'],
                              icon: Icons.map_outlined, accent: accent),
                          _infoRow('Contact', dealer['dealer_contact_no'] != null &&
                              dealer['dealer_contact_no'].toString() != '0'
                              ? dealer['dealer_contact_no']
                              : null,
                              icon: Icons.phone_outlined, accent: accent),
                          _infoRow('Email', dealer['dealer_email_id'],
                              icon: Icons.email_outlined, accent: accent),
                        ],
                      ),

                    // SECURITY STATUS
                    _section(
                      title: 'SECURITY STATUS',
                      sectionIcon: Icons.security,
                      accent: accent,
                      hasAlert: secHasAlert,
                      children: [
                        _infoRow('RC Status', a['rc_status'],
                            icon: Icons.verified_outlined, accent: accent),
                        if (blacklist.isNotEmpty)
                          _buildRow(
                            label: 'Blacklist Status',
                            value: blacklist,
                            icon: Icons.block_outlined,
                            accent: const Color(0xFFDC2626),
                            valueColor: const Color(0xFFDC2626),
                            iconBg: const Color(0xFFDC2626).withOpacity(0.1),
                            suffix: _pill('BLACKLISTED', const Color(0xFFDC2626)),
                          )
                        else
                          _buildRow(
                            label: 'Blacklist Status',
                            value: 'Clear',
                            icon: Icons.check_circle_outline,
                            accent: const Color(0xFF16A34A),
                            valueColor: const Color(0xFF16A34A),
                            iconBg: const Color(0xFF16A34A).withOpacity(0.1),
                          ),
                        _buildRow(
                          label: 'Crime Record',
                          value: (crime.isEmpty ||
                              crime.toLowerCase() == 'no' ||
                              crime.toLowerCase() == 'false')
                              ? 'None'
                              : crime,
                          icon: Icons.gavel_outlined,
                          accent: (crime.isNotEmpty &&
                              crime.toLowerCase() != 'no' &&
                              crime.toLowerCase() != 'false')
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF16A34A),
                          valueColor: (crime.isNotEmpty &&
                              crime.toLowerCase() != 'no' &&
                              crime.toLowerCase() != 'false')
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF16A34A),
                          iconBg: (crime.isNotEmpty &&
                              crime.toLowerCase() != 'no' &&
                              crime.toLowerCase() != 'false')
                              ? const Color(0xFFDC2626).withOpacity(0.1)
                              : const Color(0xFF16A34A).withOpacity(0.1),
                        ),
                        _infoRow('System Status', b['status'],
                            icon: Icons.shield_outlined, accent: accent),
                      ],
                    ),

                    // ISSUES SUMMARY (only if problems exist)
                    if (hasIssues) _issuesSummaryCard(issues),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Quick status banner (below hero) ──────────────────────────────────────
  Widget _quickStatusBanner(List<_ComplianceIssue> issues, Color accent) {
    if (issues.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        color: const Color(0xFF16A34A),
        child: const Row(
          children: [
            Icon(Icons.verified_rounded, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'All documents are valid — Vehicle is CLEAR',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    final expiredCount = issues.where((i) => i.expired).length;
    final soonCount    = issues.where((i) => !i.expired).length;
    final parts = <String>[
      if (expiredCount > 0) '$expiredCount expired',
      if (soonCount > 0)    '$soonCount expiring soon',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: expiredCount > 0
          ? const Color(0xFFDC2626)
          : const Color(0xFFD97706),
      child: Row(
        children: [
          Icon(
            expiredCount > 0
                ? Icons.warning_amber_rounded
                : Icons.info_outline_rounded,
            color: Colors.white,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${parts.join(' · ')} — see details below',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  // ── Issues summary card (bottom of page) ──────────────────────────────────
  Widget _issuesSummaryCard(List<_ComplianceIssue> issues) {
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFFDC2626).withOpacity(0.4), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFDC2626).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFDC2626).withOpacity(0.07),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.report_problem_outlined,
                    size: 18, color: Color(0xFFDC2626)),
                const SizedBox(width: 8),
                const Text(
                  'ISSUES SUMMARY',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFDC2626),
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${issues.length} PROBLEM${issues.length > 1 ? 'S' : ''}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFDC2626),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              children: issues.map((issue) {
                final isExpired = issue.expired;
                final color = isExpired
                    ? const Color(0xFFDC2626)
                    : const Color(0xFFD97706);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          issue.isStatus
                              ? Icons.block_outlined
                              : isExpired
                              ? Icons.event_busy_outlined
                              : Icons.schedule_outlined,
                          size: 16,
                          color: color,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              issue.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                            if (issue.date != null && !issue.isStatus)
                              Text(
                                isExpired
                                    ? 'Expired on ${issue.date}'
                                    : 'Expires on ${issue.date}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: color.withOpacity(0.8),
                                ),
                              ),
                            if (issue.isStatus && issue.date != null)
                              Text(
                                issue.date!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: color.withOpacity(0.8),
                                ),
                              ),
                          ],
                        ),
                      ),
                      _pill(
                        isExpired ? 'EXPIRED' : 'EXPIRING SOON',
                        color,
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _jsonTabChip(String label, int index, Color accent) {
    final selected = jsonTab == index;
    return GestureDetector(
      onTap: () => setState(() => jsonTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade600,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ── Expiry state enum ─────────────────────────────────────────────────────────

enum _ExpiryState { valid, expiringSoon, expired, unknown }

// ── Compliance issue data class ───────────────────────────────────────────────

class _ComplianceIssue {
  final String label;
  final String? date;
  final bool expired;       // true = expired, false = expiring soon
  final bool isStatus;      // true = not a date-based issue (blacklist, crime, etc.)

  const _ComplianceIssue({
    required this.label,
    this.date,
    required this.expired,
    this.isStatus = false,
  });
}

// ── Vehicle type enum ─────────────────────────────────────────────────────────

enum _VehicleType {
  car,
  motorcycle,
  threeWheeler,
  bus,
  truck,
  lcv,         // light commercial / pickup / tempo
  tractor,
  ambulance;

  /// The suffix appended to every DuckDuckGo query for this category.
  /// Keeps results on-type — "bus" prevents motorcycle images for a bus, etc.
  String get searchSuffix => switch (this) {
    _VehicleType.car          => 'car',
    _VehicleType.motorcycle   => 'motorcycle India',
    _VehicleType.threeWheeler => 'auto rickshaw India',
    _VehicleType.bus          => 'bus India',
    _VehicleType.truck        => 'truck India',
    _VehicleType.lcv          => 'light commercial vehicle India',
    _VehicleType.tractor      => 'tractor India',
    _VehicleType.ambulance    => 'ambulance India',
  };
}

// ── Helper widget: tries each URL in the list until one loads ─────────────────
class _NetworkImageWithFallback extends StatefulWidget {
  final List<String> urls;
  final double height;
  final Widget fallback;

  const _NetworkImageWithFallback({
    required this.urls,
    required this.height,
    required this.fallback,
  });

  @override
  State<_NetworkImageWithFallback> createState() =>
      _NetworkImageWithFallbackState();
}

class _NetworkImageWithFallbackState
    extends State<_NetworkImageWithFallback> {
  int _index = 0;

  void _tryNext() {
    if (_index < widget.urls.length - 1) {
      setState(() => _index++);
    }
    // If we've exhausted all URLs the errorBuilder will show the fallback
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) return widget.fallback;

    return Image.network(
      widget.urls[_index],
      height: widget.height,
      width: double.infinity,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return SizedBox(
          height: widget.height,
          child: Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                  loadingProgress.expectedTotalBytes!
                  : null,
              strokeWidth: 2,
            ),
          ),
        );
      },
      errorBuilder: (_, __, ___) {
        // Try the next URL silently; if none left, show fallback
        WidgetsBinding.instance.addPostFrameCallback((_) => _tryNext());
        return _index < widget.urls.length - 1
            ? const SizedBox.shrink()
            : widget.fallback;
      },
    );
  }
}