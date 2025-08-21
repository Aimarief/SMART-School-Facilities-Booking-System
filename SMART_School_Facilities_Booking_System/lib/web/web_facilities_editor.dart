/*import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'web_top_bar.dart';
import 'dart:convert';
import 'package:flutter/services.dart'
    show TextInputFormatter, FilteringTextInputFormatter, rootBundle;





class FacilitiesPage extends StatefulWidget {
  const FacilitiesPage({Key? key}) : super(key: key);

  @override
  State<FacilitiesPage> createState() => _FacilitiesPageState();
}

// NEW: which UI to show in the Details panel
enum DetailsView { idle, addCategory, viewCategory, editCategory, addFacility, viewFacility, editFacility }


class _FacilitiesPageState extends State<FacilitiesPage> {

  // search controllers
  final _catSearch = TextEditingController();
  final _facSearch = TextEditingController();
  final _editCategoryCtrl = TextEditingController();
  final _facilityFormKey = GlobalKey<FormState>();
  final _facilityNameCtrl = TextEditingController();
  final _facilityLocationCtrl = TextEditingController();
  final _facilityDetailsCtrl = TextEditingController();
  final _bookingDurationCtrl = TextEditingController(text: '1');
  final _inactiveReasonCtrl = TextEditingController();
  Map<String, dynamic>? _selectedFacilityData;
  String? _selectedCatId;
  String _selectedCatName = '';
  String? _selectedFacilityId;
  bool _selectedCatAvailable = true;
  int _availableSlots = 1;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _disableFacility = false;
  DateTimeRange? _inactiveRange;

  String? _selCatIdForFacility;
  String _selCatNameForFacility = '';

  String? _selManagerId;
  String _selManagerName = '';

  bool _requireApproval = false;


  String? _pickedImageName;

  static const String _assetDir = 'asset/image';

  final _newCategoryCtrl = TextEditingController();

  // NEW: current details view
  DetailsView _details = DetailsView.idle;


  // colors
  static const _fill = Color(0xFFEDDFFF);
  static const _outline = Color(0xFF8620E2);


  // NEW: write category to Firestore (and update local list)
  Future<void> _addCategory() async {
    final name = _clean(_newCategoryCtrl.text);
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a category name')),
      );
      return;
    }

    if (await _categoryNameExists(name)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Category "$name" already exists')),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('FacilitiesCategory').add({
      'name': name,
      'available': true,
      'createdAt': FieldValue.serverTimestamp(),
    });

    setState(() { _newCategoryCtrl.clear(); _details = DetailsView.idle; });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Category "$name" added')),
    );
  }



  Stream<QuerySnapshot<Map<String, dynamic>>> get _catsStream =>
      FirebaseFirestore.instance
          .collection('FacilitiesCategory')
          .orderBy('name')
          .snapshots();

  Future<void> _toggleAvailability(bool value) async {
    if (_selectedCatId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('FacilitiesCategory')
          .doc(_selectedCatId)
          .update({'available': value});
      setState(() => _selectedCatAvailable = value);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    }
  }

  void _startEdit() {
    _editCategoryCtrl.text = _selectedCatName;
    setState(() => _details = DetailsView.editCategory);
  }

  Future<void> _saveEdit() async {
    if (_selectedCatId == null) return;

    final newName = _clean(_editCategoryCtrl.text);
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    if (await _categoryNameExists(newName, ignoreId: _selectedCatId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Category "$newName" already exists')),
      );
      return;
    }

    await FirebaseFirestore.instance
        .collection('FacilitiesCategory')
        .doc(_selectedCatId)
        .update({'name': newName});

    setState(() { _selectedCatName = newName; _details = DetailsView.viewCategory; });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Category updated')),
    );
  }


  Stream<QuerySnapshot<Map<String, dynamic>>> get _facilitiesStream =>
      FirebaseFirestore.instance
          .collection('Facilities')
          .orderBy('name')
          .snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> get _managersStream =>
      FirebaseFirestore.instance
          .collection('UserInformation')
          .where('role', isEqualTo: 'Manager')
          .snapshots();


  void _openAddFacility() {
    // reset form
    _facilityFormKey.currentState?.reset();
    _facilityNameCtrl.clear();
    _facilityLocationCtrl.clear();
    _facilityDetailsCtrl.clear();
    _bookingDurationCtrl.text = '1';
    _availableSlots = 1;
    _startTime = null;
    _endTime = null;
    _selCatIdForFacility = null;
    _selCatNameForFacility = '';
    _selManagerId = null;
    _selManagerName = '';
    _requireApproval = false;
    _pickedImageName = null;

    setState(() => _details = DetailsView.addFacility);
  }

  Future<void> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: false, // we only need the filename
    );
    if (res == null || res.files.isEmpty) return;
    setState(() => _pickedImageName = res.files.first.name);
  }

  Future<void> _pickStartTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (t == null) return;
    setState(() => _startTime = t);
  }

  Future<void> _pickEndTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 17, minute: 0),
    );
    if (t == null) return;
    // optional UX: prevent end <= start immediately
    if (_startTime != null && (t.hour * 60 + t.minute) <=
        (_startTime!.hour * 60 + _startTime!.minute)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End must be after start')),
      );
      return;
    }
    setState(() => _endTime = t);
  }


  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(
          2, '0')}';

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _saveNewFacility() async {
    // --- basic form checks ---
    if (!(_facilityFormKey.currentState?.validate() ?? false)) return;


    if ((_pickedImageName == null) || _pickedImageName!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose an image filename')),
      );
      return;
    }

    if (_selCatIdForFacility == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a category')));
      return;
    }
    if (_selManagerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a manager')));
      return;
    }
    if (_startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please choose available time')));
      return;
    }
    if (_toMinutes(_startTime!) >= _toMinutes(_endTime!)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Start time must be before end time')));
      return;
    }
    final duration = int.tryParse(_bookingDurationCtrl.text.trim()) ?? 0;
    if (duration <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking duration must be > 0')));
      return;
    }
    if (_availableSlots < 1) _availableSlots = 1;

    // --- fetch working hours NOW (no reliance on cached state) ---
    int parseToMinutes(Object? v) {
      if (v == null) return -1;
      if (v is int) return v;
      if (v is String) {
        final s = v.trim();
        final m24 = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
        if (m24 != null) {
          final h = int.parse(m24.group(1)!);
          final m = int.parse(m24.group(2)!);
          return h * 60 + m;
        }
        final m12 = RegExp(
            r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false).firstMatch(
            s);
        if (m12 != null) {
          var h = int.parse(m12.group(1)!);
          final m = int.parse(m12.group(2)!);
          final ap = m12.group(3)!.toUpperCase();
          if (h == 12) h = 0;
          if (ap == 'PM') h += 12;
          return h * 60 + m;
        }
      }
      return -1;
    }

    String showHHMM(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(
            2, '0')}';

    // Adjust path if your doc id != 'settings'
    final col = FirebaseFirestore.instance.collection('SystemInformation');
    DocumentSnapshot<Map<String, dynamic>> sysDoc;
    try {
      sysDoc = await col.doc('settings').get();
      if (!sysDoc.exists) {
        final qs = await col.limit(1).get();
        if (qs.docs.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text(
                  'Working hours not found in SystemInformation')));
          return;
        }
        sysDoc = qs.docs.first;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load working hours: $e')));
      return;
    }

    final data = sysDoc.data()!;
    final sysStartMin = parseToMinutes(data['start']); // e.g. "08:00"
    final sysEndMin = parseToMinutes(data['end']); // e.g. "17:00"
    if (sysStartMin < 0 || sysEndMin < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(
              'Invalid working hours format in SystemInformation')));
      return;
    }

    // --- compare once, cleanly ---
    final s = _toMinutes(_startTime!);
    final e = _toMinutes(_endTime!);
    if (s < sysStartMin || e > sysEndMin) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              'Time must be within ${showHHMM(sysStartMin)} – ${showHHMM(
                  sysEndMin)}')));
      return;
    }
    final facilityName = _clean(_facilityNameCtrl.text);
    if (await _facilityNameExists(facilityName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Facility "$facilityName" already exists')),
      );
      return;
    }


    // --- save ---
    try {
      await FirebaseFirestore.instance.collection('Facilities').add({
        'name': facilityName,
        'imageName': _pickedImageName,
        // NOTE: only the name; no Storage upload here
        'categoryId': _selCatIdForFacility,
        'categoryName': _selCatNameForFacility,
        'location': _facilityLocationCtrl.text.trim(),
        'details': _facilityDetailsCtrl.text.trim(),
        'availableSlots': _availableSlots,
        'availableTime': {
          'start': _fmtTime(_startTime!),
          'end': _fmtTime(_endTime!),
          // optional: also store minutes for easier future logic:
          'startMin': s,
          'endMin': e,

        },
        'bookingDurationHours': duration,
        'managerId': _selManagerId,
        'managerName': _selManagerName,
        'requireApproval': _requireApproval,
        'enabled': true,

        'active': true,
        'deleted': false,
        'inactiveReason': null,
        'inactiveFrom': null,
        'inactiveTo': null,

        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() => _details = DetailsView.idle);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Facility added')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add: $e')));
    }
  }

  Future<void> _pickInactiveRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _inactiveRange,
    );
    if (picked != null) setState(() => _inactiveRange = picked);
  }

  void _startEditFacility() {
    final d = _selectedFacilityData ?? {};
    _facilityNameCtrl.text = (d['name'] ?? '').toString();
    _facilityLocationCtrl.text = (d['location'] ?? '').toString();
    _facilityDetailsCtrl.text = (d['details'] ?? '').toString();
    _bookingDurationCtrl.text = ((d['bookingDurationHours'] ?? 1)).toString();
    _availableSlots = (d['availableSlots'] ?? 1) as int;

    final at = (d['availableTime'] ?? {}) as Map;
    final start = (at['start'] ?? '') as String;
    final end = (at['end'] ?? '') as String;
    TimeOfDay _parseHHMM(String s) {
      final p = s.split(':');
      if (p.length == 2) {
        final h = int.tryParse(p[0]) ?? 0;
        final m = int.tryParse(p[1]) ?? 0;
        return TimeOfDay(hour: h, minute: m);
      }
      return const TimeOfDay(hour: 8, minute: 0);
    }
    _startTime = start.isNotEmpty ? _parseHHMM(start) : null;
    _endTime = end.isNotEmpty ? _parseHHMM(end) : null;

    _selCatIdForFacility = d['categoryId'];
    _selCatNameForFacility = (d['categoryName'] ?? '').toString();
    _selManagerId = d['managerId'];
    _selManagerName = (d['managerName'] ?? '').toString();
    _requireApproval = d['requireApproval'] == true;

    final active = d['active'] != false;
    _disableFacility = !active;
    _inactiveReasonCtrl.text = (d['inactiveReason'] ?? '').toString();
    _inactiveRange = (d['inactiveFrom'] != null && d['inactiveTo'] != null)
        ? DateTimeRange(
      start: (d['inactiveFrom'] as Timestamp).toDate(),
      end: (d['inactiveTo'] as Timestamp).toDate(),
    )
        : null;

    setState(() => _details = DetailsView.editFacility);
  }

  Future<void> _saveFacilityEdit() async {
    if (_selectedFacilityId == null) return;

    // Reuse the same validations as _saveNewFacility (name/location/details/...).
    if (!(_facilityFormKey.currentState?.validate() ?? false)) return;
    if (_selCatIdForFacility == null || _selManagerId == null ||
        _startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please complete all fields')));
      return;
    }
    final sys = await _getWorkingMinutes();
    if (sys == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Working hours not found in SystemInformation')),
      );
      return;
    }
    final s = _toMinutes(_startTime!);
    final e = _toMinutes(_endTime!);
    if (s < sys['start']! || e > sys['end']!) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Time must be within ${_showHHMM(sys['start']!)} – ${_showHHMM(sys['end']!)}')),
      );
      return;
    }
    if (_toMinutes(_startTime!) >= _toMinutes(_endTime!)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Start must be before end')));
      return;
    }
    final duration = int.tryParse(_bookingDurationCtrl.text.trim()) ?? 0;
    if (duration <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking duration must be > 0')));
      return;
    }
    if (_availableSlots < 1) _availableSlots = 1;
    final facilityName = _clean(_facilityNameCtrl.text);
    if (await _facilityNameExists(facilityName, ignoreId: _selectedFacilityId)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Facility "$facilityName" already exists')),
      );
      return;
    }


    // Build update map
    final update = <String, dynamic>{
      'name': facilityName,
      'imageName': _pickedImageName ?? _selectedFacilityData?['imageName'],
      'categoryId': _selCatIdForFacility,
      'categoryName': _selCatNameForFacility,
      'location': _facilityLocationCtrl.text.trim(),
      'details': _facilityDetailsCtrl.text.trim(),
      'availableSlots': _availableSlots,
      // 'deleted': _selectedFacilityData?['deleted'] ?? false,
      'availableTime': {
        'start': _fmtTime(_startTime!),
        'end': _fmtTime(_endTime!),
        'startMin': _toMinutes(_startTime!),
        'endMin': _toMinutes(_endTime!),
      },
      'bookingDurationHours': duration,
      'managerId': _selManagerId,
      'managerName': _selManagerName,
      'requireApproval': _requireApproval,
    };

    if (_disableFacility) {
      if (_inactiveReasonCtrl.text
          .trim()
          .isEmpty || _inactiveRange == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Reason and date range are required')));
        return;
      }
      update.addAll({
        'active': false,
        'inactiveReason': _inactiveReasonCtrl.text.trim(),
        'inactiveFrom': Timestamp.fromDate(_inactiveRange!.start),
        'inactiveTo': Timestamp.fromDate(_inactiveRange!.end),
      });
    } else {
      update.addAll({
        'active': true,
        'inactiveReason': null,
        'inactiveFrom': null,
        'inactiveTo': null,
      });
    }

    try {
      await FirebaseFirestore.instance.collection('Facilities')
          .doc(_selectedFacilityId).update(update);

      // refresh local
      _selectedFacilityData = {...?_selectedFacilityData, ...update};
      setState(() => _details = DetailsView.viewFacility);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Facility updated')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')));
    }
  }

  Future<void> _softDeleteFacility() async {
    if (_selectedFacilityId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(_selectedFacilityId)
          .update({'deleted': true});
      setState(() {
        _details = DetailsView.idle;
        _selectedFacilityId = null;
        _selectedFacilityData = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Facility deleted')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')));
    }
  }


  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day
          .toString()
          .padLeft(2, '0')}';


  String _fmtMin(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(
          2, '0')}';

  Widget _roField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
        SizedBox(height: 6.h),
        TextFormField(
          key: ValueKey('$label|$value'), // <- force rebuild when value changes
          initialValue: value,
          enabled: false,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        SizedBox(height: 12.h),
      ],
    );
  }



  Widget _viewImageBox(Map<String, dynamic> d) {
    final name = (d['imageName'] ?? '').toString(); // e.g. "court.png"
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Facility Image',
            style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
        SizedBox(height: 6.h),
        Container(
          width: 180.w,
          height: 120.h,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black26),
            borderRadius: BorderRadius.circular(6),
          ),
          clipBehavior: Clip.antiAlias,
          child: _assetImageOrLabel(name), // <-- uses asset/image/<name>
        ),
        SizedBox(height: 12.h),
      ],
    );
  }


  String _assetPath(String? name) =>
      (name == null || name.isEmpty) ? '' : '$_assetDir/$name';

  Widget _assetImageOrLabel(String? name) {
    final path = _assetPath(name);
    if (path.isEmpty) {
      return const Center(child: Text('No image'));
    }
    return Image.asset(
      path,
      fit: BoxFit.cover,
      // show filename if the asset is missing or not listed in pubspec
      errorBuilder: (_, __, ___) =>
          Center(child: Text(name?.isEmpty ?? true ? 'No image' : name!)),
    );
  }

  String _clean(String s) => s.trim();

  Future<bool> _categoryNameExists(String name, {String? ignoreId}) async {
    final qs = await FirebaseFirestore.instance
        .collection('FacilitiesCategory')        // <-- keep your actual name
        .where('name', isEqualTo: _clean(name))
        .limit(2)
        .get();

    // if ignoreId is provided (editing), allow the one with that id
    return qs.docs.any((d) => d.id != ignoreId);
  }

  Future<bool> _facilityNameExists(String name, {String? ignoreId}) async {
    final qs = await FirebaseFirestore.instance
        .collection('Facilities')
        .where('name', isEqualTo: _clean(name))   // case-sensitive exact match
        .where('deleted', isEqualTo: false)       // ⬅️ ignore soft-deleted docs
        .limit(2)                                  // safer for edit case
        .get();

    return qs.docs.any((d) => d.id != ignoreId);
  }

  Future<void> backfillDeletedFalse() async {
    final col = FirebaseFirestore.instance.collection('Facilities');
    final snap = await col.limit(500).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final d in snap.docs) {
      if (d.data()['deleted'] == null) {
        batch.update(d.reference, {'deleted': false});
      }
    }
    await batch.commit();
  }

  int _parseToMinutes(Object? v) {
    if (v == null) return -1;
    if (v is int) return v;
    if (v is String) {
      final s = v.trim();
      final m24 = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
      if (m24 != null) {
        final h = int.parse(m24.group(1)!);
        final m = int.parse(m24.group(2)!);
        return h * 60 + m;
      }
      final m12 = RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false).firstMatch(s);
      if (m12 != null) {
        var h = int.parse(m12.group(1)!);
        final m = int.parse(m12.group(2)!);
        final ap = m12.group(3)!.toUpperCase();
        if (h == 12) h = 0;
        if (ap == 'PM') h += 12;
        return h * 60 + m;
      }
    }
    return -1;
  }

  String _showHHMM(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<Map<String,int>?> _getWorkingMinutes() async {
    try {
      final col = FirebaseFirestore.instance.collection('SystemInformation');
      var doc = await col.doc('settings').get();
      if (!doc.exists) {
        final qs = await col.limit(1).get();
        if (qs.docs.isEmpty) return null;
        doc = qs.docs.first;
      }
      final data = doc.data()!;
      final startMin = _parseToMinutes(data['start']);
      final endMin = _parseToMinutes(data['end']);
      if (startMin < 0 || endMin < 0) return null;
      return {'start': startMin, 'end': endMin};
    } catch (_) {
      return null;
    }
  }




  @override
  void dispose() {
    _catSearch.dispose();
    _editCategoryCtrl.dispose();
    _newCategoryCtrl.dispose();
    _facilityNameCtrl.dispose();
    _facilityLocationCtrl.dispose();
    _facilityDetailsCtrl.dispose();
    _bookingDurationCtrl.dispose();
    _inactiveReasonCtrl.dispose(); // NEW
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery
        .of(context)
        .size
        .height; // not used, safe to keep

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: const WebCustomTopBar(use24HourFormat: true),
      ),

      // ✅ whole page can scroll (prevents overflow on zoom)
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(16.w),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ---------------- LEFT COLUMN ----------------
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Categories box
                          _Box(
                            width: 460.w,
                            height: 400.h,
                            title: 'Categories',
                            header: _SearchHeader(
                              controller: _catSearch,
                              hint: 'Search',
                              onChanged: (_) => setState(() {}),
                              onAdd: () =>
                                  setState(() =>
                                  _details = DetailsView.addCategory),
                            ),
                            child: StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>>(
                              stream: _catsStream,
                              builder: (context, snap) {
                                if (snap.connectionState ==
                                    ConnectionState.waiting) {
                                  return const _EmptyCenter(text: 'Loading...');
                                }
                                if (snap.hasError) {
                                  return const _EmptyCenter(
                                      text: 'Failed to load');
                                }

                                final docs = snap.data?.docs ?? [];
                                final q = _catSearch.text.trim().toLowerCase();

                                final filtered = docs.where((d) {
                                  final name = (d.data()['name'] ?? '')
                                      .toString();
                                  return q.isEmpty ||
                                      name.toLowerCase().contains(q);
                                }).toList();

                                if (filtered.isEmpty)
                                  return const _EmptyCenter(text: 'empty');

                                return ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) =>
                                      SizedBox(height: 8.h),
                                  itemBuilder: (context, i) {
                                    final doc = filtered[i];
                                    final data = doc.data();
                                    final name = (data['name'] ?? '')
                                        .toString();
                                    final available = data['available'] is bool
                                        ? data['available'] as bool
                                        : true;

                                    return _ListTileCard(
                                      label: name,
                                      onTap: () {
                                        setState(() {
                                          _selectedCatId = doc.id;
                                          _selectedCatName = name;
                                          _selectedCatAvailable = available;
                                          _details = DetailsView.viewCategory;
                                        });
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ),

                          SizedBox(height: 16.h),

                          // Facility box  ✅ (this was missing in your last paste)
                          _Box(
                            width: 460.w,
                            height: 550.h,
                            title: 'Facility',
                            header: _SearchHeader(
                              controller: _facSearch,
                              hint: 'Search',
                              onChanged: (_) => setState(() {}),
                              onAdd: _openAddFacility,
                            ),
                            child: StreamBuilder<
                                QuerySnapshot<Map<String, dynamic>>>(
                              stream: _facilitiesStream,
                              builder: (context, snap) {
                                if (snap.connectionState ==
                                    ConnectionState.waiting) {
                                  return const _EmptyCenter(text: 'Loading...');
                                }
                                if (snap.hasError) return const _EmptyCenter(
                                    text: 'Failed to load');

                                final docs = snap.data?.docs ?? [];
                                final q = _facSearch.text.trim().toLowerCase();

                                final filtered = docs.where((d) {
                                  final data = d.data();
                                  if (data['deleted'] == true)
                                    return false; // hide soft-deleted
                                  final name = (data['name'] ?? '').toString();
                                  return q.isEmpty ||
                                      name.toLowerCase().contains(q);
                                }).toList();

                                if (filtered.isEmpty)
                                  return const _EmptyCenter(text: 'empty');

                                return ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) =>
                                      SizedBox(height: 8.h),
                                  itemBuilder: (context, i) {
                                    final doc = filtered[i];
                                    final data = doc.data();
                                    final name = (data['name'] ?? '')
                                        .toString();

                                    return _ListTileCard(
                                      label: name,
                                      onTap: () {
                                        setState(() {
                                          _selectedFacilityId = doc.id;
                                          _selectedFacilityData = data;
                                          _details = DetailsView.viewFacility;
                                        });
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),


                      SizedBox(width: 16.w),

                      // Column 2 (Details)
                      _Box(
                        width: 1200.w,
                        height: 965.h,
                        title: 'Details',
                        header: null,
                        child: SingleChildScrollView(
                          padding: EdgeInsets.only(right: 8.w, bottom: 8.h),
                          child: Builder(
                            builder: (_) {
                              // ⬇️ keep your existing details views
                              if (_details == DetailsView.addCategory) {
                                return _AddCategoryForm(
                                  controller: _newCategoryCtrl,
                                  onAdd: _addCategory,
                                  onCancel: () =>
                                      setState(() =>
                                      _details = DetailsView.idle),
                                );
                              }

                              if (_details == DetailsView.viewCategory) {
                                return Container(
                                  padding: EdgeInsets.all(12.w),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1E6FF),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFF8620E2)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment
                                        .start,
                                    children: [
                                      Text('Category', style: TextStyle(
                                          fontSize: 15.sp,
                                          fontWeight: FontWeight.w500)),
                                      SizedBox(height: 6.h),
                                      Text(_selectedCatName, style: TextStyle(
                                          fontSize: 16.sp,
                                          fontWeight: FontWeight.w600)),
                                      SizedBox(height: 12.h),
                                      Row(
                                        children: [
                                          Text('Enabled', style: TextStyle(
                                              fontSize: 15.sp)),
                                          SizedBox(width: 8.w),
                                          Switch(
                                            value: _selectedCatAvailable,
                                            onChanged: (v) =>
                                                _toggleAvailability(v),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 12.h),
                                      Row(
                                        children: [
                                          ElevatedButton(onPressed: _startEdit,
                                              child: const Text('Edit')),
                                          SizedBox(width: 8.w),
                                          TextButton(
                                            onPressed: () =>
                                                setState(() =>
                                                _details = DetailsView.idle),
                                            child: const Text('Close'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }

                              if (_details == DetailsView.editCategory) {
                                return Container(
                                  padding: EdgeInsets.all(12.w),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1E6FF),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFF8620E2)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment
                                        .start,
                                    children: [
                                      Text('Edit Category Name',
                                          style: TextStyle(fontSize: 12.sp,
                                              fontWeight: FontWeight.w500)),
                                      SizedBox(height: 6.h),
                                      SizedBox(
                                        height: 40.h,
                                        child: TextField(
                                          controller: _editCategoryCtrl,
                                          style: TextStyle(fontSize: 14.sp),
                                          decoration: const InputDecoration(
                                              isDense: true,
                                              border: OutlineInputBorder()),
                                        ),
                                      ),
                                      SizedBox(height: 12.h),
                                      Row(
                                        children: [
                                          ElevatedButton(onPressed: _saveEdit,
                                              child: const Text('Confirm')),
                                          SizedBox(width: 8.w),
                                          TextButton(
                                            onPressed: () =>
                                                setState(() =>
                                                _details =
                                                    DetailsView.viewCategory),
                                            child: const Text('Cancel'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }
                              if (_details == DetailsView.addFacility) {
                                return Container(
                                  padding: EdgeInsets.all(12.w),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1E6FF),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFF8620E2)),
                                  ),
                                  child: Form(
                                    key: _facilityFormKey,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment
                                          .start,
                                      children: [
                                        // Facility Name
                                        Text('Facility Name', style: TextStyle(
                                            fontSize: 12.sp,
                                            fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        TextFormField(
                                          controller: _facilityNameCtrl,
                                          validator: (v) =>
                                          (v == null || v
                                              .trim()
                                              .isEmpty) ? 'Required' : null,
                                          decoration: const InputDecoration(
                                              border: OutlineInputBorder(),
                                              isDense: true),
                                        ),
                                        SizedBox(height: 12.h),

                                        // Image + Upload
                                        Text('Facility Image', style: TextStyle(
                                            fontSize: 12.sp,
                                            fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        Container(
                                          width: 180.w,
                                          height: 120.h,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            border: Border.all(
                                                color: Colors.black26),
                                            borderRadius: BorderRadius.circular(
                                                6),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: _assetImageOrLabel(
                                              _pickedImageName), // <- show chosen asset
                                        ),
                                        SizedBox(height: 6.h),
                                        OutlinedButton.icon(
                                          onPressed: _pickImage,
                                          icon: const Icon(
                                              Icons.photo_library, size: 16),
                                          label: const Text('Upload Image'),
                                        ),

                                        // Category dropdown
                                        Text('Facility Category',
                                            style: TextStyle(fontSize: 12.sp,
                                                fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        StreamBuilder<QuerySnapshot<
                                            Map<String, dynamic>>>(
                                          stream: _catsStream,
                                          builder: (context, snap) {
                                            if (!snap.hasData) {
                                              return const SizedBox(height: 40,
                                                  child: Center(
                                                      child: CircularProgressIndicator()));
                                            }
                                            final items = snap.data!.docs.map((
                                                d) {
                                              final name = (d.data()['name'] ??
                                                  '').toString();
                                              return DropdownMenuItem<String>(
                                                value: d.id,
                                                child: Text(name),
                                                onTap: () =>
                                                _selCatNameForFacility = name,
                                              );
                                            }).toList();

                                            return SizedBox(
                                              width: 380.w,
                                              // pick a width that fits your panel
                                              child: DropdownButtonFormField<
                                                  String>(
                                                isExpanded: true,
                                                // make it use the available width
                                                value: _selCatIdForFacility,
                                                items: snap.data!.docs.map((d) {
                                                  final name = (d
                                                      .data()['name'] ?? '')
                                                      .toString();
                                                  return DropdownMenuItem<
                                                      String>(
                                                    value: d.id,
                                                    child: Text(name,
                                                        overflow: TextOverflow
                                                            .ellipsis),
                                                    onTap: () =>
                                                    _selCatNameForFacility =
                                                        name,
                                                  );
                                                }).toList(),
                                                onChanged: (v) =>
                                                    setState(() =>
                                                    _selCatIdForFacility = v),
                                                validator: (v) =>
                                                v == null
                                                    ? 'Required'
                                                    : null,
                                                decoration: const InputDecoration(
                                                    border: OutlineInputBorder(),
                                                    isDense: true),
                                                hint: const Text('Option'),
                                              ),
                                            );
                                          },
                                        ),
                                        SizedBox(height: 12.h),

                                        // Location
                                        Text('Facility Location',
                                            style: TextStyle(fontSize: 12.sp,
                                                fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        TextFormField(
                                          controller: _facilityLocationCtrl,
                                          validator: (v) =>
                                          (v == null || v
                                              .trim()
                                              .isEmpty) ? 'Required' : null,
                                          decoration: const InputDecoration(
                                              border: OutlineInputBorder(),
                                              isDense: true),
                                        ),
                                        SizedBox(height: 12.h),

                                        // Details (multiline, wraps)
                                        Text('Facility Details',
                                            style: TextStyle(fontSize: 12.sp,
                                                fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        TextFormField(
                                          controller: _facilityDetailsCtrl,
                                          validator: (v) =>
                                          (v == null || v
                                              .trim()
                                              .isEmpty) ? 'Required' : null,
                                          maxLines: 3,
                                          decoration: const InputDecoration(
                                              border: OutlineInputBorder(),
                                              isDense: true),
                                        ),
                                        SizedBox(height: 12.h),

                                        // Available Slots (min 1)
                                        Text('Available Slots',
                                            style: TextStyle(fontSize: 12.sp,
                                                fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        Row(
                                          children: [
                                            IconButton(
                                              onPressed: () =>
                                                  setState(() {
                                                    _availableSlots =
                                                        (_availableSlots - 1)
                                                            .clamp(1, 9999);
                                                  }),
                                              icon: const Icon(Icons.remove),
                                            ),
                                            SizedBox(
                                              width: 60.w,
                                              child: TextFormField(
                                                key: ValueKey(_availableSlots),
                                                // keep caret sane on rebuild
                                                initialValue: _availableSlots
                                                    .toString(),
                                                onChanged: (v) {
                                                  final n = int.tryParse(v) ??
                                                      1;
                                                  _availableSlots =
                                                  n < 1 ? 1 : n;
                                                },
                                                inputFormatters: [
                                                  FilteringTextInputFormatter
                                                      .digitsOnly
                                                ],
                                                keyboardType: TextInputType
                                                    .number,
                                                validator: (v) =>
                                                (int.tryParse(v ?? '') ?? 0) < 1
                                                    ? 'Min 1'
                                                    : null,
                                                textAlign: TextAlign.center,
                                                decoration: const InputDecoration(
                                                    isDense: true,
                                                    border: OutlineInputBorder()),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () =>
                                                  setState(() => _availableSlots++),
                                              icon: const Icon(Icons.add),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 12.h),

                                        // Available Time
                                        Text('Available Time', style: TextStyle(
                                            fontSize: 12.sp,
                                            fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        Row(
                                          children: [

                                            Expanded(
                                              child: OutlinedButton(
                                                onPressed: _pickStartTime,
                                                child: Text(_startTime == null
                                                    ? 'from'
                                                    : _fmtTime(_startTime!)),
                                              ),
                                            ),
                                            SizedBox(width: 8.w),
                                            Expanded(
                                              child: OutlinedButton(
                                                onPressed: _pickEndTime,
                                                child: Text(_endTime == null
                                                    ? 'to'
                                                    : _fmtTime(_endTime!)),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 12.h),

                                        // Booking Duration (hours, int)
                                        Text('Booking Duration',
                                            style: TextStyle(fontSize: 12.sp,
                                                fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        Row(
                                          children: [
                                            SizedBox(
                                              width: 100.w,
                                              child: TextFormField(
                                                controller: _bookingDurationCtrl,
                                                inputFormatters: [
                                                  FilteringTextInputFormatter
                                                      .digitsOnly
                                                ],
                                                keyboardType: TextInputType
                                                    .number,
                                                validator: (v) =>
                                                (int.tryParse(v ?? '') ?? 0) <=
                                                    0
                                                    ? 'Required'
                                                    : null,
                                                decoration: const InputDecoration(
                                                    border: OutlineInputBorder(),
                                                    isDense: true),
                                              ),
                                            ),
                                            SizedBox(width: 8.w),
                                            const Text('hour'),
                                          ],
                                        ),
                                        SizedBox(height: 12.h),

                                        // Assign Manager
                                        Text('Assign Manager', style: TextStyle(
                                            fontSize: 12.sp,
                                            fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        StreamBuilder<QuerySnapshot<
                                            Map<String, dynamic>>>(
                                          stream: _managersStream,
                                          builder: (context, snap) {
                                            if (!snap.hasData) {
                                              return const SizedBox(height: 40,
                                                  child: Center(
                                                      child: CircularProgressIndicator()));
                                            }
                                            final items = snap.data!.docs.map((
                                                d) {
                                              final data = d.data();
                                              final name = (data['username'] ??
                                                  data['name'] ?? 'Manager')
                                                  .toString();
                                              return DropdownMenuItem<String>(
                                                value: d.id,
                                                child: Text(name),
                                                onTap: () =>
                                                _selManagerName = name,
                                              );
                                            }).toList();

                                            return DropdownButtonFormField<
                                                String>(
                                              value: _selManagerId,
                                              items: items,
                                              onChanged: (v) =>
                                                  setState(() =>
                                                  _selManagerId = v),
                                              validator: (v) =>
                                              v == null
                                                  ? 'Required'
                                                  : null,
                                              decoration: const InputDecoration(
                                                  border: OutlineInputBorder(),
                                                  isDense: true),
                                              hint: const Text('Option'),
                                            );
                                          },
                                        ),
                                        SizedBox(height: 12.h),

                                        // Require Approval
                                        Row(
                                          children: [
                                            const Text('Require Approval'),
                                            const SizedBox(width: 8),
                                            Switch(value: _requireApproval,
                                                onChanged: (v) =>
                                                    setState(() =>
                                                    _requireApproval = v)),
                                          ],
                                        ),
                                        SizedBox(height: 16.h),

                                        // Actions
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment
                                              .end,
                                          children: [
                                            ElevatedButton(
                                                onPressed: _saveNewFacility,
                                                child: const Text('Add')),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }
                              if (_details == DetailsView.viewFacility &&
                                  _selectedFacilityData != null) {
                                final d = _selectedFacilityData!;
                                final time = (d['availableTime'] ?? {}) as Map;
                                final statusActive = d['active'] != false;

                                return Container(
                                  padding: EdgeInsets.all(12.w),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1E6FF),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFF8620E2)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment
                                        .start,
                                    children: [
                                      // same sections as "Add", but read-only
                                      _roField('Facility Name',
                                          (d['name'] ?? '').toString()),
                                      _viewImageBox(d),
                                      _roField('Facility Category',
                                          (d['categoryName'] ?? '').toString()),
                                      _roField('Facility Location',
                                          (d['location'] ?? '').toString()),
                                      _roField('Facility Details',
                                          (d['details'] ?? '').toString()),
                                      _roField('Available Slots',
                                          (d['availableSlots'] ?? '')
                                              .toString()),
                                      _roField('Available Time',
                                          '${time['start'] ??
                                              '-'} – ${time['end'] ?? '-'}'),
                                      _roField('Booking Duration',
                                          '${d['bookingDurationHours'] ??
                                              '-'} hour'),
                                      _roField('Assign Manager',
                                          (d['managerName'] ?? '').toString()),
                                      _roField('Require Approval',
                                          (d['requireApproval'] == true)
                                              ? 'Yes'
                                              : 'No'),
                                      _roField('Status',
                                          statusActive ? 'Active' : 'Disabled'),
                                      if (!statusActive) ...[
                                        _roField('Reason',
                                            (d['inactiveReason'] ?? '-')
                                                .toString()),
                                        if (d['inactiveFrom'] != null &&
                                            d['inactiveTo'] != null)
                                          _roField('Unavailable',
                                              '${_fmtDate(
                                                  (d['inactiveFrom'] as Timestamp)
                                                      .toDate())} → ${_fmtDate(
                                                  (d['inactiveTo'] as Timestamp)
                                                      .toDate())}'),
                                      ],
                                      Row(
                                        children: [
                                          ElevatedButton(
                                              onPressed: _startEditFacility,
                                              child: const Text('Edit')),
                                          SizedBox(width: 8.w),
                                          TextButton(onPressed: () =>
                                              setState(() =>
                                              _details = DetailsView.idle),
                                              child: const Text('Close')),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }

                              if (_details == DetailsView.editFacility &&
                                  _selectedFacilityId != null) {
                                return Container(
                                  padding: EdgeInsets.all(12.w),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF1E6FF),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFF8620E2)),
                                  ),
                                  child: Form(
                                    key: _facilityFormKey,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment
                                          .start,
                                      children: [
                                        // === SAME FIELDS AS ADD (copy from your addFacility block) ===

                                        // Name
                                        Text('Facility Name', style: TextStyle(
                                            fontSize: 12.sp,
                                            fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        TextFormField(
                                          controller: _facilityNameCtrl,
                                          validator: (v) =>
                                          (v == null || v
                                              .trim()
                                              .isEmpty) ? 'Required' : null,
                                          decoration: const InputDecoration(
                                              border: OutlineInputBorder(),
                                              isDense: true),
                                        ),
                                        SizedBox(height: 12.h),

                                        // Image (show current if no new pick)
                                        Text('Facility Image', style: TextStyle(
                                            fontSize: 12.sp,
                                            fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        Container(
                                          width: 180.w,
                                          height: 120.h,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            border: Border.all(
                                                color: Colors.black26),
                                            borderRadius: BorderRadius.circular(
                                                6),
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: _assetImageOrLabel(
                                            _pickedImageName ??
                                                (_selectedFacilityData?['imageName'] ??
                                                    '').toString(),
                                          ),
                                        ),
                                        SizedBox(height: 6.h),

                                        SizedBox(height: 6.h),
                                        OutlinedButton.icon(
                                          onPressed: _pickImage,
                                          icon: const Icon(
                                              Icons.upload_file, size: 16),
                                          label: const Text('Upload Image'),
                                        ),
                                        SizedBox(height: 12.h),

                                        // Category
                                        Text('Facility Category',
                                            style: TextStyle(fontSize: 12.sp,
                                                fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        StreamBuilder<QuerySnapshot<
                                            Map<String, dynamic>>>(
                                          stream: _catsStream,
                                          builder: (context, snap) {
                                            if (!snap.hasData) {
                                              return const SizedBox(height: 40,
                                                  child: Center(
                                                      child: CircularProgressIndicator()));
                                            }
                                            return SizedBox(
                                              width: 380.w,
                                              child: DropdownButtonFormField<
                                                  String>(
                                                isExpanded: true,
                                                value: _selCatIdForFacility,
                                                items: snap.data!.docs.map((d) {
                                                  final name = (d
                                                      .data()['name'] ?? '')
                                                      .toString();
                                                  return DropdownMenuItem<
                                                      String>(
                                                    value: d.id,
                                                    child: Text(name,
                                                        overflow: TextOverflow
                                                            .ellipsis),
                                                    onTap: () =>
                                                    _selCatNameForFacility =
                                                        name,
                                                  );
                                                }).toList(),
                                                onChanged: (v) =>
                                                    setState(() =>
                                                    _selCatIdForFacility = v),
                                                validator: (v) =>
                                                v == null
                                                    ? 'Required'
                                                    : null,
                                                decoration: const InputDecoration(
                                                    border: OutlineInputBorder(),
                                                    isDense: true),
                                                hint: const Text('Option'),
                                              ),
                                            );
                                          },
                                        ),
                                        SizedBox(height: 12.h),

                                        // Location
                                        Text('Facility Location',
                                            style: TextStyle(fontSize: 12.sp,
                                                fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        TextFormField(
                                          controller: _facilityLocationCtrl,
                                          validator: (v) =>
                                          (v == null || v
                                              .trim()
                                              .isEmpty) ? 'Required' : null,
                                          decoration: const InputDecoration(
                                              border: OutlineInputBorder(),
                                              isDense: true),
                                        ),
                                        SizedBox(height: 12.h),

                                        // Details
                                        Text('Facility Details',
                                            style: TextStyle(fontSize: 12.sp,
                                                fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        TextFormField(
                                          controller: _facilityDetailsCtrl,
                                          validator: (v) =>
                                          (v == null || v
                                              .trim()
                                              .isEmpty) ? 'Required' : null,
                                          maxLines: 3,
                                          decoration: const InputDecoration(
                                              border: OutlineInputBorder(),
                                              isDense: true),
                                        ),
                                        SizedBox(height: 12.h),

                                        // Slots
                                        Text('Available Slots',
                                            style: TextStyle(fontSize: 12.sp,
                                                fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        Row(
                                          children: [
                                            IconButton(
                                              onPressed: () =>
                                                  setState(() =>
                                                  _availableSlots =
                                                      (_availableSlots - 1)
                                                          .clamp(1, 9999)),
                                              icon: const Icon(Icons.remove),
                                            ),
                                            SizedBox(
                                              width: 60.w,
                                              child: TextFormField(
                                                key: ValueKey(_availableSlots),
                                                initialValue: _availableSlots
                                                    .toString(),
                                                onChanged: (v) {
                                                  final n = int.tryParse(v) ??
                                                      1;
                                                  _availableSlots =
                                                  n < 1 ? 1 : n;
                                                },
                                                inputFormatters: [
                                                  FilteringTextInputFormatter
                                                      .digitsOnly
                                                ],
                                                keyboardType: TextInputType
                                                    .number,
                                                validator: (v) =>
                                                (int.tryParse(v ?? '') ?? 0) < 1
                                                    ? 'Min 1'
                                                    : null,
                                                textAlign: TextAlign.center,
                                                decoration: const InputDecoration(
                                                    isDense: true,
                                                    border: OutlineInputBorder()),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () =>
                                                  setState(() => _availableSlots++),
                                              icon: const Icon(Icons.add),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 12.h),

                                        // Time
                                        Text('Available Time', style: TextStyle(
                                            fontSize: 12.sp,
                                            fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton(
                                                onPressed: _pickStartTime,
                                                child: Text(_startTime == null
                                                    ? 'from'
                                                    : _fmtTime(_startTime!)),
                                              ),
                                            ),
                                            SizedBox(width: 8.w),
                                            Expanded(
                                              child: OutlinedButton(
                                                onPressed: _pickEndTime,
                                                child: Text(_endTime == null
                                                    ? 'to'
                                                    : _fmtTime(_endTime!)),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 12.h),

                                        // Duration
                                        Text('Booking Duration',
                                            style: TextStyle(fontSize: 12.sp,
                                                fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        Row(
                                          children: [
                                            SizedBox(
                                              width: 100.w,
                                              child: TextFormField(
                                                controller: _bookingDurationCtrl,
                                                inputFormatters: [
                                                  FilteringTextInputFormatter
                                                      .digitsOnly
                                                ],
                                                keyboardType: TextInputType
                                                    .number,
                                                validator: (v) =>
                                                (int.tryParse(v ?? '') ?? 0) <=
                                                    0
                                                    ? 'Required'
                                                    : null,
                                                decoration: const InputDecoration(
                                                    border: OutlineInputBorder(),
                                                    isDense: true),
                                              ),
                                            ),
                                            SizedBox(width: 8.w),
                                            const Text('hour'),
                                          ],
                                        ),
                                        SizedBox(height: 12.h),

                                        // Manager
                                        Text('Assign Manager', style: TextStyle(
                                            fontSize: 12.sp,
                                            fontWeight: FontWeight.w500)),
                                        SizedBox(height: 6.h),
                                        StreamBuilder<QuerySnapshot<
                                            Map<String, dynamic>>>(
                                          stream: _managersStream,
                                          builder: (context, snap) {
                                            if (!snap.hasData) {
                                              return const SizedBox(height: 40,
                                                  child: Center(
                                                      child: CircularProgressIndicator()));
                                            }
                                            final items = snap.data!.docs.map((
                                                d) {
                                              final data = d.data();
                                              final name = (data['username'] ??
                                                  data['name'] ?? 'Manager')
                                                  .toString();
                                              return DropdownMenuItem<String>(
                                                value: d.id,
                                                child: Text(name),
                                                onTap: () =>
                                                _selManagerName = name,
                                              );
                                            }).toList();

                                            return DropdownButtonFormField<
                                                String>(
                                              value: _selManagerId,
                                              items: items,
                                              onChanged: (v) =>
                                                  setState(() =>
                                                  _selManagerId = v),
                                              validator: (v) =>
                                              v == null
                                                  ? 'Required'
                                                  : null,
                                              decoration: const InputDecoration(
                                                  border: OutlineInputBorder(),
                                                  isDense: true),
                                              hint: const Text('Option'),
                                            );
                                          },
                                        ),
                                        SizedBox(height: 12.h),

                                        // Require approval
                                        Row(
                                          children: [
                                            const Text('Require Approval'),
                                            const SizedBox(width: 8),
                                            Switch(value: _requireApproval,
                                                onChanged: (v) =>
                                                    setState(() =>
                                                    _requireApproval = v)),
                                          ],
                                        ),

                                        // === Disable / delete / confirm ===
                                        SizedBox(height: 12.h),
                                        Row(
                                          children: [
                                            const Text(
                                                'Disable facility temporarily'),
                                            const SizedBox(width: 8),
                                            Switch(value: _disableFacility,
                                                onChanged: (v) =>
                                                    setState(() =>
                                                    _disableFacility = v)),
                                          ],
                                        ),
                                        if (_disableFacility) ...[
                                          SizedBox(height: 6.h),
                                          TextFormField(
                                            controller: _inactiveReasonCtrl,
                                            validator: (v) =>
                                            (v == null || v
                                                .trim()
                                                .isEmpty)
                                                ? 'Reason required'
                                                : null,
                                            decoration: const InputDecoration(
                                                labelText: 'Reason',
                                                border: OutlineInputBorder(),
                                                isDense: true),
                                          ),
                                          SizedBox(height: 8.h),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: OutlinedButton(
                                                  onPressed: _pickInactiveRange,
                                                  child: Text(
                                                    _inactiveRange == null
                                                        ? 'Pick unavailable date range'
                                                        : '${_fmtDate(
                                                        _inactiveRange!
                                                            .start)} → ${_fmtDate(
                                                        _inactiveRange!.end)}',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                        SizedBox(height: 16.h),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment
                                              .end,
                                          children: [
                                            TextButton(
                                                onPressed: _softDeleteFacility,
                                                style: TextButton.styleFrom(
                                                    foregroundColor: Colors
                                                        .red),
                                                child: const Text('Delete')),
                                            SizedBox(width: 8.w),
                                            ElevatedButton(
                                                onPressed: _saveFacilityEdit,
                                                child: const Text('Confirm')),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }


                              return const _EmptyCenter(
                                  text: 'Please select an option');
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
/// Reusable bordered box with fixed size, title, sticky header, and scrollable body
class _Box extends StatelessWidget {
  const _Box({
    Key? key,
    required this.width,
    required this.height,
    required this.title,
    required this.child,
    this.header,
  }) : super(key: key);

  final double width;
  final double height;
  final String title;
  final Widget child;
  final Widget? header;

  static const _fill = Color(0xFFEDDFFF);
  static const _outline = Color(0xFF8620E2);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _fill,
        border: Border.all(color: _outline, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 8.h),
          if (header != null) header!,
          if (header != null) SizedBox(height: 8.h),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Scrollbar(
                thumbVisibility: true,
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Search field + add button (header stays fixed)
class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    Key? key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    required this.onAdd,
  }) : super(key: key);

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 36.h,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: hint,
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding:
                EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 8.w),
        SizedBox(
          height: 36.h,
          width: 36.h,
          child: OutlinedButton(
            onPressed: onAdd,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            child: const Icon(Icons.playlist_add, size: 18),
          ),
        ),
      ],
    );
  }
}

/// A simple card-like row item
class _ListTileCard extends StatelessWidget {
  const _ListTileCard({Key? key, required this.label, required this.onTap})
      : super(key: key);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(.9),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 44.h,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style:
                  TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCenter extends StatelessWidget {
  const _EmptyCenter({Key? key, required this.text}) : super(key: key);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style:
        TextStyle(fontSize: 14.sp, color: Colors.black.withOpacity(0.6)),
      ),
    );
  }
}

// NEW: super simple form used in Details panel
class _AddCategoryForm extends StatelessWidget {
  const _AddCategoryForm({
    Key? key,
    required this.controller,
    required this.onAdd,
    required this.onCancel,
  }) : super(key: key);

  final TextEditingController controller;
  final VoidCallback onAdd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFFF1E6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF8620E2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Category Name',
              style:
              TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          SizedBox(
            height: 40.h,
            child: TextField(
              controller: controller,
              style: TextStyle(fontSize: 14.sp),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              ElevatedButton(onPressed: onAdd, child: const Text('Add')),
              SizedBox(width: 8.w),
              TextButton(onPressed: onCancel, child: const Text('Cancel')),
            ],
          ),
        ],
      ),
    );
  }
}*/
