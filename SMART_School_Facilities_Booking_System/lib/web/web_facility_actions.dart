import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter, FilteringTextInputFormatter;
import 'package:flutter_screenutil/flutter_screenutil.dart';

enum FacView { add, view, edit }

/// ---------------------------------------------------------------------------
/// Small reusable box with sticky header (duplicated locally for independence)
/// ---------------------------------------------------------------------------
class _BoxPanel extends StatelessWidget {
  const _BoxPanel({
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

  static const Color _fill = Color(0xFFEDDFFF);
  static const Color _outline = Color(0xFF8620E2);


  @override
  Widget build(BuildContext context) {
    final List<Widget> kids = <Widget>[
      Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
      SizedBox(height: 8.h),
    ];
    if (header != null) {
      kids.add(header!);
      kids.add(SizedBox(height: 8.h));
    }
    kids.add(
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Scrollbar(
            thumbVisibility: true,
            child: child,
          ),
        ),
      ),
    );

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outline, width: 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Search header with + button
/// ---------------------------------------------------------------------------
class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    Key? key,
    required this.controller,
    required this.onChanged,
    required this.onAddTap,
  }) : super(key: key);

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onAddTap;

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
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
        ),
        SizedBox(width: 8.w),
        SizedBox(
          height: 36.h,
          width: 36.h,
          child: OutlinedButton(
            onPressed: onAddTap,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            child: const Icon(Icons.playlist_add, size: 18),
          ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// List row
/// ---------------------------------------------------------------------------
class _ListTileCard extends StatelessWidget {
  const _ListTileCard({
    Key? key,
    required this.label,
    required this.onTap,
  }) : super(key: key);

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
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
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

/// ===========================================================================
/// LEFT: Facilities list + search + add
/// ===========================================================================
class FacilityLeftList extends StatefulWidget {
  const FacilityLeftList({
    Key? key,
    required this.width,
    required this.height,
    required this.search,
    required this.onAddTap,
    required this.onSelect,
  }) : super(key: key);

  final double width;
  final double height;
  final TextEditingController search;

  final VoidCallback onAddTap;
  final void Function(String id, Map<String, dynamic> data) onSelect;

  @override
  State<FacilityLeftList> createState() => _FacilityLeftListState();
}

class _FacilityLeftListState extends State<FacilityLeftList> {
  Stream<QuerySnapshot<Map<String, dynamic>>> _facStream() {
    return FirebaseFirestore.instance.collection('Facilities').orderBy('name').snapshots();
  }

  String _clean(String s) => s.trim();



  @override
  Widget build(BuildContext context) {
    return _BoxPanel(
      width: widget.width,
      height: widget.height,
      title: 'Facility',
      header: _SearchHeader(
        controller: widget.search,
        onChanged: (_) => setState(() {}),
        onAddTap: widget.onAddTap,
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _facStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: Text('Loading...', style: TextStyle(fontSize: 14.sp)));
          }
          if (snap.hasError) {
            return Center(child: Text('Failed to load', style: TextStyle(fontSize: 14.sp)));
          }

          List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          if (snap.hasData) {
            docs = snap.data!.docs;
          }

          final String q = _clean(widget.search.text).toLowerCase();
          final List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

          for (final d in docs) {
            final Map<String, dynamic> m = d.data();

            bool del = false;
            if (m.containsKey('deleted') && m['deleted'] == true) {
              del = true;
            }

            String name = '';
            if (m.containsKey('name') && m['name'] != null) {
              name = m['name'].toString();
            }

            bool matches = true;
            if (q.isNotEmpty) {
              final String lower = name.toLowerCase();
              matches = lower.contains(q);
            }

            if (!del && matches) {
              filtered.add(d);
            }
          }

          if (filtered.isEmpty) {
            return Center(child: Text('empty', style: TextStyle(fontSize: 14.sp)));
          }

          return ListView.separated(
            itemCount: filtered.length,
            separatorBuilder: (_, __) => SizedBox(height: 8.h),
            itemBuilder: (context, i) {
              final doc = filtered[i];
              final Map<String, dynamic> data = doc.data();

              String name = '';
              if (data.containsKey('name') && data['name'] != null) {
                name = data['name'].toString();
              }

              return _ListTileCard(
                label: name,
                onTap: () => widget.onSelect(doc.id, data),
              );
            },
          );
        },
      ),
    );
  }
}

/// ===========================================================================
/// RIGHT: Facility Details Panel (add / view / edit)
/// ===========================================================================
class FacilityRightPanel extends StatefulWidget {
  const FacilityRightPanel({
    Key? key,
    required this.width,
    required this.height,
    required this.selectedFacilityId,
    required this.selectedFacilityData,
    required this.initialView,
    required this.onClose,
    required this.onFacilityUpdated,
  }) : super(key: key);

  final double width;
  final double height;

  final String? selectedFacilityId;
  final Map<String, dynamic>? selectedFacilityData;

  final FacView initialView;

  final VoidCallback onClose;
  final void Function(String? id, Map<String, dynamic>? data) onFacilityUpdated;

  @override
  State<FacilityRightPanel> createState() => _FacilityRightPanelState();
}

class _FacilityRightPanelState extends State<FacilityRightPanel> {
  // --- Form controllers ---
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _locationCtrl = TextEditingController();
  final TextEditingController _detailsCtrl = TextEditingController();
  final TextEditingController _durationCtrl = TextEditingController(text: '1');
  final TextEditingController _inactiveReasonCtrl = TextEditingController();
  final GlobalKey<FormFieldState> _slotFieldKey = GlobalKey<FormFieldState>();

  // --- Form runtime state ---
  int _slots = 1;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  // list of custom booking slots (each has startMin and endMin in minutes)
  List<Map<String, int>> _customSlots = <Map<String, int>>[];
  bool _requireApproval = false;
  bool _disableFacility = false;
  bool _isRangePickerOpen = false;
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  DateTimeRange? _inactiveRange;
  String? _slotError;
  // --- Picks ---
  String? _pickedImageName;

  // --- Dropdown selections ---
  String? _catId;
  String _catName = '';
  String? _managerId;
  String _managerName = '';

  // --- View mode ---
  FacView _view = FacView.view;

  // --- Assets base folder ---
  static const String _assetDir = 'asset/image';

  // ---------- lifecycle ----------
  @override
  void initState() {
    super.initState();
    _view = widget.initialView;   // mirror parent on first build
    _hydrateFromSelected();       // fill controllers from selectedFacilityData
    if (_view == FacView.add) {
      _resetAddDefaults();        // keep your add defaults behavior
    }
  }

  @override
  void didUpdateWidget(covariant FacilityRightPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If parent switches view (add/view/edit), follow it and refresh form state
    if (widget.initialView != _view) {
      _view = widget.initialView;
    }
    _hydrateFromSelected();
    if (_view == FacView.add) {
      _resetAddDefaults();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    _detailsCtrl.dispose();
    _durationCtrl.dispose();
    _inactiveReasonCtrl.dispose();
    super.dispose();
  }

  // ---------- utils ----------
  String _clean(String s) => s.trim();

  String _fmtDate(DateTime d) {
    final String y = d.year.toString();
    final String mo = d.month.toString().padLeft(2, '0');
    final String da = d.day.toString().padLeft(2, '0');
    return '$y-$mo-$da';
  }

  String _fmtTime(TimeOfDay t) {
    final String h = t.hour.toString().padLeft(2, '0');
    final String m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  int _toMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  String _showHHMM(int m) {
    final String h = (m ~/ 60).toString().padLeft(2, '0');
    final String mm = (m % 60).toString().padLeft(2, '0');
    return '$h:$mm';
  }

  /// Parse either minutes (int) or "HH:MM"/"HH:MM AM/PM" (String) into minutes.
  int _parseToMinutes(Object? v) {
    if (v == null) return -1;
    if (v is int) return v;
    if (v is String) {
      final String s = v.trim();

      final RegExpMatch? m24 = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s);
      if (m24 != null) {
        final int h = int.parse(m24.group(1)!);
        final int m = int.parse(m24.group(2)!);
        return h * 60 + m;
      }

      final RegExpMatch? m12 =
      RegExp(r'^(\d{1,2}):(\d{2})\s*(AM|PM)$', caseSensitive: false).firstMatch(s);
      if (m12 != null) {
        int h = int.parse(m12.group(1)!);
        final int m = int.parse(m12.group(2)!);
        final String ap = m12.group(3)!.toUpperCase();
        if (h == 12) h = 0;
        if (ap == 'PM') h = h + 12;
        return h * 60 + m;
      }
    }
    return -1;
  }

  /// Read working window (start/end minutes) from SystemInformation.
  Future<Map<String, int>?> _getWorkingMinutes() async {
    try {
      final CollectionReference<Map<String, dynamic>> col =
      FirebaseFirestore.instance.collection('SystemInformation');

      DocumentSnapshot<Map<String, dynamic>> doc = await col.doc('settings').get();
      if (!doc.exists) {
        final QuerySnapshot<Map<String, dynamic>> qs = await col.limit(1).get();
        if (qs.docs.isEmpty) return null;
        doc = qs.docs.first;
      }

      final Map<String, dynamic>? data = doc.data();
      if (data == null) return null;

      final int start = _parseToMinutes(data['start']);
      final int end = _parseToMinutes(data['end']);
      if (start < 0 || end < 0) return null;

      return <String, int>{'start': start, 'end': end};
    } catch (_) {
      return null;
    }
  }

  /// Turn a date into 23:59:59.999 of that day (inclusive end-of-day).
  DateTime _toEndOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  // --- image helpers ---
  String _assetPath(String? name) {
    if (name == null) return '';
    if (name.isEmpty) return '';
    return '$_assetDir/$name';
  }

  Widget _assetImageOrLabel(String? name) {
    final String path = _assetPath(name);
    if (path.isEmpty) {
      return const Center(child: Text('No image'));
    }
    return Image.asset(
      path,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        if (name == null || name.isEmpty) {
          return const Center(child: Text('No image'));
        } else {
          return Center(child: Text(name));
        }
      },
    );
  }

  // ---------- picks ----------
  /// Select an image file (we store only the filename string).
  Future<void> _pickImage() async {
    final FilePickerResult? res =
    await FilePicker.platform.pickFiles(type: FileType.image, withData: false);
    if (res == null) return;
    if (res.files.isEmpty) return;

    setState(() {
      _pickedImageName = res.files.first.name;
    });
  }

  /// Pick start time (button in the form).
  Future<void> _pickStartTime() async {
    final TimeOfDay? t =
    await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (t == null) return;
    setState(() => _startTime = t);
  }

  /// Pick end time (button in the form). Must be after start time.
  Future<void> _pickEndTime() async {
    final TimeOfDay? t =
    await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 17, minute: 0));
    if (t == null) return;

    if (_startTime != null) {
      final int endMin = t.hour * 60 + t.minute;
      final int startMin = _startTime!.hour * 60 + _startTime!.minute;
      if (endMin <= startMin) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End must be after start')));
        return;
      }
    }
    setState(() => _endTime = t);
  }

  /// Pick a future-only date range for temporary disable.
  Future<void> _pickInactiveRange() async {
    if (_isRangePickerOpen) return;
    _isRangePickerOpen = true;

    try {
      final DateTime now = DateTime.now();
      final DateTime first = DateTime(now.year, now.month, now.day); // today (no time)
      final DateTime last  = DateTime(now.year + 2, 12, 31);         // end-of-year 2y out

      // Clamp previous range (if any) so it's always within [first, last]
      DateTimeRange init;
      if (_inactiveRange != null) {
        DateTime s = _inactiveRange!.start.isBefore(first) ? first : _inactiveRange!.start;
        DateTime e = _inactiveRange!.end.isAfter(last) ? last : _inactiveRange!.end;
        if (e.isBefore(s)) e = s; // keep non-empty
        init = DateTimeRange(start: s, end: e);
      } else {
        init = DateTimeRange(start: first, end: first);
      }

      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: first,
        lastDate: last,
        initialDateRange: init,
      );

      if (picked != null) {
        setState(() => _inactiveRange = picked);
      }
    } finally {
      _isRangePickerOpen = false;
    }
  }


  // ---------- data hydrate / reset ----------
  /// Reset all inputs to defaults for "Add" mode.
  void _resetAddDefaults() {
    // reset the form UI
    _formKey.currentState?.reset();

    // clear all text fields
    _nameCtrl.clear();
    _locationCtrl.clear();
    _detailsCtrl.clear();
    _durationCtrl.text = '1';
    _inactiveReasonCtrl.clear();

    // set simple defaults for numbers and toggles
    _slots = 1;
    _requireApproval = false;
    _disableFacility = false;


    // clear time and slots
    _startTime = null;
    _endTime = null;
    _customSlots = <Map<String, int>>[];


    // clear inactive date range
    _inactiveRange = null;

    // clear picks / dropdowns
    _pickedImageName = null;
    _catId = null;
    _catName = '';
    _managerId = null;
    _managerName = '';

    // clear slot error
    _slotError = null;
  }

  /// Load the selected facility doc into the form for "View" / "Edit".
  void _hydrateFromSelected() {
    final Map<String, dynamic>? d = widget.selectedFacilityData;
    if (d == null) return;
    if (_view == FacView.add) return;

    // Text fields
    String nm = '';
    if (d.containsKey('name') && d['name'] != null) {
      nm = d['name'].toString();
    }
    _nameCtrl.text = nm;

    String loc = '';
    if (d.containsKey('location') && d['location'] != null) {
      loc = d['location'].toString();
    }
    _locationCtrl.text = loc;

    String det = '';
    if (d.containsKey('details') && d['details'] != null) {
      det = d['details'].toString();
    }
    _detailsCtrl.text = det;

    int dur = 1;
    if (d.containsKey('bookingDurationHours') && d['bookingDurationHours'] != null) {
      final dynamic v = d['bookingDurationHours'];
      if (v is int) {
        dur = v;
      } else {
        final int? parsed = int.tryParse(v.toString());
        if (parsed != null) {
          dur = parsed;
        }
      }
    }
    _durationCtrl.text = dur.toString();

    // Slots
    _slots = 1;
    if (d.containsKey('availableSlots') && d['availableSlots'] != null) {
      final dynamic v = d['availableSlots'];
      if (v is int) {
        _slots = v;
      } else {
        final int? parsed = int.tryParse(v.toString());
        if (parsed != null) _slots = parsed;
      }
    }
    if (_slots < 1) _slots = 1;

    // Available time
    Map at;
    if (d.containsKey('availableTime') && d['availableTime'] is Map) {
      at = d['availableTime'] as Map;
    } else {
      at = <String, dynamic>{};
    }

    String startStr = '';
    if (at.containsKey('start') && at['start'] != null) {
      startStr = at['start'].toString();
    }
    String endStr = '';
    if (at.containsKey('end') && at['end'] != null) {
      endStr = at['end'].toString();
    }

    TimeOfDay _parseHHMM(String s) {
      final List<String> p = s.split(':');
      if (p.length == 2) {
        final int? h = int.tryParse(p[0]);
        final int? m = int.tryParse(p[1]);
        if (h != null && m != null) {
          return TimeOfDay(hour: h, minute: m);
        }
      }
      return const TimeOfDay(hour: 8, minute: 0);
    }

    if (startStr.isNotEmpty) {
      _startTime = _parseHHMM(startStr);
    } else {
      _startTime = null;
    }

    if (endStr.isNotEmpty) {
      _endTime = _parseHHMM(endStr);
    } else {
      _endTime = null;
    }


    // Build _customSlots strictly from DB customTimeSlots (no fallback)
    _customSlots = <Map<String, int>>[];
    if (d.containsKey('customTimeSlots') && d['customTimeSlots'] is List) {
      final List raw = d['customTimeSlots'] as List;
      for (final s in raw) {
        if (s is Map) {
          final int? sMin = int.tryParse('${s['startMin']}');
          final int? eMin = int.tryParse('${s['endMin']}');
          if (sMin != null && eMin != null && eMin > sMin) {
            _customSlots.add(<String, int>{'startMin': sMin, 'endMin': eMin});
          }
        }
      }
      _customSlots.sort((a, b) => (a['startMin'] ?? 0).compareTo(b['startMin'] ?? 0));
    }




    // Category
    if (d.containsKey('categoryId')) {
      _catId = d['categoryId'];
    } else {
      _catId = null;
    }
    String catName = '';
    if (d.containsKey('categoryName') && d['categoryName'] != null) {
      catName = d['categoryName'].toString();
    }
    _catName = catName;

    // Manager
    if (d.containsKey('managerId')) {
      _managerId = d['managerId'];
    } else {
      _managerId = null;
    }
    String managerName = '';
    if (d.containsKey('managerName') && d['managerName'] != null) {
      managerName = d['managerName'].toString();
    }
    _managerName = managerName;

    // Approval
    _requireApproval = false;
    if (d.containsKey('requireApproval') && d['requireApproval'] == true) {
      _requireApproval = true;
    }

    // Active / disable + inactive info
    // --- Active / disable + inactive info (supports scheduled disable) ---
    final Timestamp? fromTs = (d['inactiveFrom'] is Timestamp) ? d['inactiveFrom'] as Timestamp : null;
    final Timestamp? toTs   = (d['inactiveTo']   is Timestamp) ? d['inactiveTo']   as Timestamp : null;

// Reason & range fields (prefill if present)
    _inactiveReasonCtrl.text = (d['inactiveReason'] ?? '').toString();
    if (fromTs != null && toTs != null) {
      _inactiveRange = DateTimeRange(start: fromTs.toDate(), end: toTs.toDate());
    } else {
      _inactiveRange = null;
    }

// Decide whether the toggle should appear ON in Edit
    final bool dbActive = (d['active'] != false);
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    final bool hasWindow = fromTs != null && toTs != null;
    final bool scheduledFuture = hasWindow && fromTs!.toDate().isAfter(today);
    final bool inWindowNow = hasWindow &&
        !today.isBefore(fromTs.toDate()) &&
        !today.isAfter(toTs!.toDate());

// Show the disable UI if the facility is currently disabled OR has a scheduled window
    _disableFacility = (!dbActive) || scheduledFuture || inWindowNow;


    // image: keep original unless a new one is picked later
    _pickedImageName = null;
  }


// ---------- custom slots helpers ----------

  /// Add a new custom slot using showTimePicker for the start time.
  /// The end time will be start + bookingDurationHours.
  /// Add a new custom slot using showTimePicker for the start time.
  /// Now we allow minutes too (e.g. 07:30 → 08:30) as long as within working hours.
  Future<void> _onAddCustomSlot() async {
    int dur = 1;
    final int? p = int.tryParse(_durationCtrl.text.trim());
    if (p != null) dur = p;
    if (dur <= 0) {
      setState(() => _slotError = 'Please set a valid booking duration');
      _slotFieldKey.currentState?.validate();
      return;
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Pick slot START time',
    );
    if (picked == null) return;

    final int sMin = picked.hour * 60 + picked.minute;
    final int eMin = sMin + (dur * 60);

    final Map<String, int>? sys = await _getWorkingMinutes();
    if (sys == null) {
      setState(() => _slotError = 'Working hours not found in SystemInformation');
      _slotFieldKey.currentState?.validate();
      return;
    }
    if (sMin < sys['start']! || eMin > sys['end']!) {
      setState(() => _slotError =
      'Slot must be within ${_showHHMM(sys['start']!)} – ${_showHHMM(sys['end']!)}');
      _slotFieldKey.currentState?.validate();
      return;
    }

    for (final m in _customSlots) {
      final int a = m['startMin'] ?? 0;
      final int b = m['endMin'] ?? 0;
      if (sMin < b && a < eMin) {
        setState(() => _slotError = 'Slot overlaps an existing one');
        _slotFieldKey.currentState?.validate();
        return;
      }
    }

    setState(() {
      _customSlots.add({'startMin': sMin, 'endMin': eMin});
      _customSlots.sort((x, y) => (x['startMin'] ?? 0).compareTo(y['startMin'] ?? 0));
      _slotError = null; // clear any previous error now that it’s valid
    });
    _slotFieldKey.currentState?.validate();
  }



  // ---------- streams ----------
  Stream<QuerySnapshot<Map<String, dynamic>>> _catsStream() {
    return FirebaseFirestore.instance
        .collection('FacilitiesCategory')
        .orderBy('name')
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _managersStream() {
    return FirebaseFirestore.instance
        .collection('UserInformation')
        .where('role', isEqualTo: 'Manager')
        .snapshots();
  }

  // ---------- existence checks ----------
  /// Check uniqueness of a facility name among non-deleted docs.
  Future<bool> _facilityNameExists(String name, {String? ignoreId}) async {
    final QuerySnapshot<Map<String, dynamic>> qs = await FirebaseFirestore.instance
        .collection('Facilities')
        .where('name', isEqualTo: _clean(name))
        .where('deleted', isEqualTo: false)
        .limit(2)
        .get();

    for (final d in qs.docs) {
      if (d.id != ignoreId) {
        return true;
      }
    }
    return false;
  }

  // ---------- saves ----------
  /// Create a new facility (validates all inputs, checks hours/name, writes Firestore).

  Future<void> _saveNew() async {
    // 1) Validate the form
    if (!(_formKey.currentState != null && _formKey.currentState!.validate())) return;

    // 2) Required picks
    if (!(_pickedImageName != null && _pickedImageName!.isNotEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please choose an image filename')));
      return;
    }
    if (_catId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a category')));
      return;
    }
    if (_managerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a manager')));
      return;
    }
    if (_customSlots.isEmpty) {
      setState(() => _slotError = 'Please add at least one time slot');
      _slotFieldKey.currentState?.validate();
      return;
    }

    // 3) Duration must be > 0  (DECLARE dur BEFORE using it below)
    int dur = int.tryParse(_durationCtrl.text.trim()) ?? 0;
    if (dur <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking duration must be > 0')));
      return;
    }

    // 4) Each slot must equal duration and be within working hours; compute earliest/latest
    final Map<String, int>? sys = await _getWorkingMinutes();
    if (sys == null) {
      setState(() => _slotError = 'Working hours not found in SystemInformation');
      _slotFieldKey.currentState?.validate();
      return;
    }
    final int step = dur * 60;
    int earliest = 999999;
    int latest = -1;
    for (final m in _customSlots) {
      final int s = m['startMin'] ?? -1;
      final int e = m['endMin'] ?? -1;
      if (s < 0 || e < 0) {
        setState(() => _slotError = 'Invalid slot data');
        _slotFieldKey.currentState?.validate();
        return;
      }
      if ((e - s) != step) {
        setState(() => _slotError = 'Every slot must be exactly equal to the booking duration');
        _slotFieldKey.currentState?.validate();
        return;
      }
      if (s < sys['start']! || e > sys['end']!) {
        setState(() => _slotError =
        'Slots must be within ${_showHHMM(sys['start']!)} – ${_showHHMM(sys['end']!)}');
        _slotFieldKey.currentState?.validate();
        return;
      }
      if (s < earliest) earliest = s;
      if (e > latest) latest = e;
    }
    setState(() => _slotError = null);
    _slotFieldKey.currentState?.validate();

    // 5) Slots capacity at least 1
    if (_slots < 1) _slots = 1;

    // 6) Unique name
    final String name = _clean(_nameCtrl.text);
    if (await _facilityNameExists(name)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Facility "$name" already exists')));
      return;
    }

    // 7) Create Firestore doc
    try {
      await FirebaseFirestore.instance.collection('Facilities').add(<String, dynamic>{
        'name': name,
        'imageName': _pickedImageName,
        'categoryId': _catId,
        'categoryName': _catName,
        'location': _locationCtrl.text.trim(),
        'details': _detailsCtrl.text.trim(),
        'availableSlots': _slots,
        'availableTime': <String, dynamic>{
          'start': _showHHMM(earliest),
          'end': _showHHMM(latest),
          'startMin': earliest,
          'endMin': latest,
        },
        'customTimeSlots': _customSlots
            .map((m) => <String, dynamic>{
          'start': _showHHMM(m['startMin'] ?? 0),
          'end': _showHHMM(m['endMin'] ?? 0),
          'startMin': m['startMin'] ?? 0,
          'endMin': m['endMin'] ?? 0,
        })
            .toList(),
        'bookingDurationHours': dur,
        'managerId': _managerId,
        'managerName': _managerName,
        'requireApproval': _requireApproval,
        'enabled': true,
        // lifecycle
        'active': !_disableFacility,
        'inactiveReason': null,
        'inactiveFrom': null,
        'inactiveTo': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      widget.onFacilityUpdated(null, null);
      widget.onClose();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Facility added')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add: $e')));
    }
  }


  /// Update an existing facility (validations + write Firestore).

  Future<void> _saveEdit() async {
    if (widget.selectedFacilityId == null) return;

    // 1) Validate the form
    if (!(_formKey.currentState != null && _formKey.currentState!.validate())) return;

    // 2) Required fields
    if (!(_catId != null && _managerId != null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please complete all fields')));
      return;
    }
    if (_customSlots.isEmpty) {
      setState(() => _slotError = 'Please add at least one time slot');
      _slotFieldKey.currentState?.validate();
      return;
    }

    // 3) Duration  (DECLARE dur BEFORE using it below)
    int dur = int.tryParse(_durationCtrl.text.trim()) ?? 0;
    if (dur <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking duration must be > 0')));
      return;
    }

    // 4) Validate slots vs working hours & duration; compute earliest/latest
    final Map<String, int>? sys = await _getWorkingMinutes();
    if (sys == null) {
      setState(() => _slotError = 'Working hours not found in SystemInformation');
      _slotFieldKey.currentState?.validate();
      return;
    }
    final int step = dur * 60;
    int earliest = 999999;
    int latest = -1;
    for (final m in _customSlots) {
      final int s = m['startMin'] ?? -1;
      final int e = m['endMin'] ?? -1;
      if ((e - s) != step) {
        setState(() => _slotError = 'Every slot must be exactly equal to the booking duration');
        _slotFieldKey.currentState?.validate();
        return;
      }
      if (s < sys['start']! || e > sys['end']!) {
        setState(() => _slotError =
        'Slots must be within ${_showHHMM(sys['start']!)} – ${_showHHMM(sys['end']!)}');
        _slotFieldKey.currentState?.validate();
        return;
      }
      if (s < earliest) earliest = s;
      if (e > latest) latest = e;
    }
    setState(() => _slotError = null);
    _slotFieldKey.currentState?.validate();

    // 5) Unique name (ignore this doc id)
    final String name = _clean(_nameCtrl.text);
    if (await _facilityNameExists(name, ignoreId: widget.selectedFacilityId)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Facility "$name" already exists')));
      return;
    }

    // 6) Image to save
    String imageToSave = _pickedImageName ??
        (widget.selectedFacilityData != null &&
            widget.selectedFacilityData!.containsKey('imageName') &&
            widget.selectedFacilityData!['imageName'] != null
            ? widget.selectedFacilityData!['imageName'].toString()
            : '');

    // 7) Build update map
    final Map<String, dynamic> update = <String, dynamic>{
      'name': name,
      'imageName': imageToSave,
      'categoryId': _catId,
      'categoryName': _catName,
      'location': _locationCtrl.text.trim(),
      'details': _detailsCtrl.text.trim(),
      'availableSlots': _slots,
      'availableTime': <String, dynamic>{
        'start': _showHHMM(earliest),
        'end': _showHHMM(latest),
        'startMin': earliest,
        'endMin': latest,
      },
      'customTimeSlots': _customSlots
          .map((m) => <String, dynamic>{
        'start': _showHHMM(m['startMin'] ?? 0),
        'end': _showHHMM(m['endMin'] ?? 0),
        'startMin': m['startMin'] ?? 0,
        'endMin': m['endMin'] ?? 0,
      })
          .toList(),
      'bookingDurationHours': dur,
      'managerId': _managerId,
      'managerName': _managerName,
      'requireApproval': _requireApproval,
    };

    // 8) Disable / re-enable
    if (_disableFacility) {
      // require reason + range
      final String reason = _inactiveReasonCtrl.text.trim();
      if (reason.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reason required')),
        );
        return;
      }
      if (_inactiveRange == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please pick a date range')),
        );
        return;
      }

      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);

      final DateTime startDay = DateTime(
        _inactiveRange!.start.year, _inactiveRange!.start.month, _inactiveRange!.start.day,
      );
      final DateTime endDay = DateTime(
        _inactiveRange!.end.year, _inactiveRange!.end.month, _inactiveRange!.end.day,
      );

      // ordering check
      if (endDay.isBefore(startDay)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End date cannot be before start date')),
        );
        return;
      }

      // read currently saved window
      final Timestamp? dbFromTs = (widget.selectedFacilityData?['inactiveFrom'] is Timestamp)
          ? widget.selectedFacilityData!['inactiveFrom'] as Timestamp
          : null;
      final Timestamp? dbToTs = (widget.selectedFacilityData?['inactiveTo'] is Timestamp)
          ? widget.selectedFacilityData!['inactiveTo'] as Timestamp
          : null;

      // allow mid-window edits that keep the same dates
      bool _isSameDay(DateTime a, DateTime b) =>
          a.year == b.year && a.month == b.month && a.day == b.day;

      final bool unchangedExistingRange =
          dbFromTs != null &&
              dbToTs != null &&
              _isSameDay(dbFromTs.toDate(), _inactiveRange!.start) &&
              _isSameDay(dbToTs.toDate(), _inactiveRange!.end);

      if (startDay.isBefore(today) && !unchangedExistingRange) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unavailable start date cannot be before today')),
        );
        return;
      }

      final bool startsInFuture = startDay.isAfter(today);
      update['active']         = startsInFuture ? true : false;
      update['inactiveReason'] = reason;
      update['inactiveFrom']   = Timestamp.fromDate(startDay);
      update['inactiveTo']     = Timestamp.fromDate(_toEndOfDay(endDay));
    } else {
      // switch is OFF → clear window
      update['active']         = true;
      update['inactiveReason'] = null;
      update['inactiveFrom']   = null;
      update['inactiveTo']     = null;
    }


    // 9) Write
    try {
      await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.selectedFacilityId)
          .update(update);

      final Map<String, dynamic> newMap = <String, dynamic>{};
      final Map<String, dynamic> old = widget.selectedFacilityData == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(widget.selectedFacilityData!);
      newMap.addAll(old);
      newMap.addAll(update);
      widget.onFacilityUpdated(widget.selectedFacilityId, newMap);

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Facility updated')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    }
  }



  /// Soft delete a facility (set deleted:true), then notify parent to clear selection.
  Future<void> _softDelete() async {
    if (widget.selectedFacilityId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.selectedFacilityId)
          .update(<String, dynamic>{'deleted': true});

      widget.onFacilityUpdated(null, null);
      widget.onClose();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Facility deleted')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  /// Confirm delete dialog (returns true only if user taps "Yes").
  Future<bool> _confirmDelete() async {
    final bool? res = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm delete'),
        content: const Text('Are you sure you want to delete this facility?'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('No')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (res == null) {
      return false;
    } else {
      return res;
    }
  }

  // ---------- small UI helpers ----------
  Widget _ro(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
        SizedBox(height: 6.h),
        TextFormField(
          key: ValueKey<String>('$label|$value'),
          initialValue: value,
          enabled: false,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
        ),
        SizedBox(height: 12.h),
      ],
    );
  }

  Widget _imagePreviewBox(String? name) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Facility Image', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
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
          child: _assetImageOrLabel(name),
        ),
        SizedBox(height: 12.h),
      ],
    );
  }

  String _statusLabel(bool dbActive) => dbActive ? 'Active' : 'Disabled';

  // ---------- build ----------
  @override
  Widget build(BuildContext context) {
    return _BoxPanel(
      width: widget.width,
      height: widget.height,
      title: 'Details',
      child: SingleChildScrollView(
        padding: EdgeInsets.only(right: 8.w, bottom: 8.h),
        child: _buildInner(),
      ),
    );
  }

  Widget _buildInner() {
    if (_view == FacView.add) {
      return _buildForm(isEdit: false);
    }
    if (_view == FacView.edit) {
      return _buildForm(isEdit: true);
    }

    // ---------- View mode ----------
    final Map<String, dynamic> d = widget.selectedFacilityData == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(widget.selectedFacilityData!);

    Map time;
    if (d.containsKey('availableTime') && d['availableTime'] is Map) {
      time = d['availableTime'] as Map;
    } else {
      time = <String, dynamic>{};
    }

    String startText = '-';
    if (time.containsKey('start') && time['start'] != null) {
      startText = time['start'].toString();
    }
    String endText = '-';
    if (time.containsKey('end') && time['end'] != null) {
      endText = time['end'].toString();
    }

    String catName = '';
    if (d.containsKey('categoryName') && d['categoryName'] != null) {
      catName = d['categoryName'].toString();
    }

    String slots = '';
    if (d.containsKey('availableSlots') && d['availableSlots'] != null) {
      slots = d['availableSlots'].toString();
    }

    String dur = '-';
    if (d.containsKey('bookingDurationHours') && d['bookingDurationHours'] != null) {
      dur = d['bookingDurationHours'].toString();
    }

    String mgr = '';
    if (d.containsKey('managerName') && d['managerName'] != null) {
      mgr = d['managerName'].toString();
    }

    String req = 'No';
    if (d.containsKey('requireApproval') && d['requireApproval'] == true) {
      req = 'Yes';
    }

    String name = '';
    if (d.containsKey('name') && d['name'] != null) {
      name = d['name'].toString();
    }

    String loc = '';
    if (d.containsKey('location') && d['location'] != null) {
      loc = d['location'].toString();
    }

    String det = '';
    if (d.containsKey('details') && d['details'] != null) {
      det = d['details'].toString();
    }

    String img = '';
    if (d.containsKey('imageName') && d['imageName'] != null) {
      img = d['imageName'].toString();
    }

    bool dbActive = true;
    if (d.containsKey('active') && d['active'] == false) {
      dbActive = false;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ro('Facility Name', name),
        _imagePreviewBox(img),
        _ro('Facility Category', catName),
        _ro('Facility Location', loc),
        _ro('Facility Details', det),
        _ro('Available Slots', slots),
        _ro('Available Time', '$startText – $endText'),
        _ro('Custom Slots', (() {
          if (d.containsKey('customTimeSlots') && d['customTimeSlots'] is List) {
            final List raw = d['customTimeSlots'] as List;
            final List<String> labels = <String>[];
            for (final s in raw) {
              if (s is Map) {
                String st = '';
                String en = '';
                if (s.containsKey('start') && s['start'] != null) st = s['start'].toString();
                if (s.containsKey('end') && s['end'] != null) en = s['end'].toString();
                if (st.isNotEmpty && en.isNotEmpty) labels.add('$st–$en');
              }
            }
            if (labels.isEmpty) return '-';
            return labels.join(', ');
          }
          return '-';
        })()),
        _ro('Booking Duration', '$dur hour'),
        _ro('Assign Manager', mgr),
        _ro('Require Approval', req),
        _ro('Status', _statusLabel(dbActive)),
        Row(
          children: [
            ElevatedButton(
              onPressed: () => setState(() {
                _hydrateFromSelected();  // refresh controllers before switching to edit
                _view = FacView.edit;
              }),
              child: const Text('Edit'),
            ),

            SizedBox(width: 8.w),
            TextButton(onPressed: widget.onClose, child: const Text('Close')),
          ],
        ),
      ],
    );
  }

  Widget _buildForm({required bool isEdit}) {
    // Extra inputs shown only when disabling a facility
    final List<Widget> disableExtras = <Widget>[];
    if (_disableFacility) {
      disableExtras.add(SizedBox(height: 6.h));
      disableExtras.add(
        TextFormField(
          controller: _inactiveReasonCtrl,
          validator: (v) {
            if (_disableFacility) {
              if (v == null) return 'Reason required';
              if (v.trim().isEmpty) return 'Reason required';
            }
            return null;
          },
          decoration: const InputDecoration(
            labelText: 'Reason',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );
      disableExtras.add(SizedBox(height: 8.h));
      disableExtras.add(
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _pickInactiveRange,
                child: Text(
                  _inactiveRange == null
                      ? 'Pick unavailable date range'
                      : '${_fmtDate(_inactiveRange!.start)} → ${_fmtDate(_inactiveRange!.end)}',
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Determine image to preview (picked > existing > empty/null)
    String? previewName;
    if (_pickedImageName != null) {
      previewName = _pickedImageName;
    } else {
      if (isEdit) {
        if (widget.selectedFacilityData != null &&
            widget.selectedFacilityData!.containsKey('imageName') &&
            widget.selectedFacilityData!['imageName'] != null) {
          previewName = widget.selectedFacilityData!['imageName'].toString();
        } else {
          previewName = '';
        }
      } else {
        previewName = null;
      }
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // name
          Text('Facility Name', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          TextFormField(
            controller: _nameCtrl,
            validator: (v) {
              if (v == null) return 'Required';
              if (v.trim().isEmpty) return 'Required';
              return null;
            },
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          ),
          SizedBox(height: 12.h),

          // image
          Text('Facility Image', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
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
            child: _assetImageOrLabel(previewName),
          ),
          SizedBox(height: 6.h),
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.upload_file, size: 16),
            label: const Text('Upload Image'),
          ),
          SizedBox(height: 12.h),

          // category
          Text('Facility Category', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _catsStream(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const SizedBox(
                  height: 40,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final List<QueryDocumentSnapshot<Map<String, dynamic>>> raw = snap.data!.docs;
              final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              for (final d in raw) {
                final Map<String, dynamic> m = d.data();
                if (m.containsKey('deleted') && m['deleted'] == true) {
                  // skip soft-deleted categories
                } else {
                  docs.add(d);
                }
              }

              String? value;
              bool found = false;
              for (final d in docs) {
                if (d.id == _catId) {
                  found = true;
                  break;
                }
              }
              if (found) {
                value = _catId;
              } else {
                value = null;
              }

              return SizedBox(
                width: 380.w,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: value,
                  items: docs.map((d) {
                    final Map<String, dynamic> m = d.data();
                    String nm = '';
                    if (m.containsKey('name') && m['name'] != null) {
                      nm = m['name'].toString();
                    }
                    return DropdownMenuItem<String>(
                      value: d.id,
                      child: Text(nm, overflow: TextOverflow.ellipsis),
                      onTap: () => _catName = nm,
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _catId = v),
                  validator: (v) {
                    if (v == null) return 'Required';
                    return null;
                  },
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                  hint: const Text('Option'),
                ),
              );
            },
          ),
          SizedBox(height: 12.h),

          // location
          Text('Facility Location', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          TextFormField(
            controller: _locationCtrl,
            validator: (v) {
              if (v == null) return 'Required';
              if (v.trim().isEmpty) return 'Required';
              return null;
            },
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          ),
          SizedBox(height: 12.h),

          // details
          Text('Facility Details', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          TextFormField(
            controller: _detailsCtrl,
            validator: (v) {
              if (v == null) return 'Required';
              if (v.trim().isEmpty) return 'Required';
              return null;
            },
            maxLines: 3,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          ),
          SizedBox(height: 12.h),

          // slots
          Text('Available Slots', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          Row(
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _slots = _slots - 1;
                    if (_slots < 1) _slots = 1;
                  });
                },
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 60.w,
                child: TextFormField(
                  key: ValueKey<int>(_slots),
                  initialValue: _slots.toString(),
                  onChanged: (v) {
                    int n = 1;
                    final int? parsed = int.tryParse(v);
                    if (parsed != null) n = parsed;
                    if (n < 1) n = 1;
                    _slots = n;
                  },
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    int val = 0;
                    if (v != null) {
                      final int? p = int.tryParse(v);
                      if (p != null) val = p;
                    }
                    if (val < 1) return 'Min 1';
                    return null;
                  },
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _slots = _slots + 1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          SizedBox(height: 12.h),

          // time

// duration (int hours) with - and + buttons
          Text('Booking Duration', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          Row(
            children: [
              IconButton(
                onPressed: () {
                  // decrease hours but not below 1
                  int val = 1;
                  final int? p = int.tryParse(_durationCtrl.text.trim());
                  if (p != null) { val = p; }
                  if (val > 1) { val = val - 1; }
                  _durationCtrl.text = val.toString();
                  setState(() {});
                },
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 100.w,
                child: TextFormField(
                  controller: _durationCtrl,
                  textAlign: TextAlign.center,
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    int val = 0;
                    if (v != null) {
                      final int? p = int.tryParse(v);
                      if (p != null) val = p;
                    }
                    if (val <= 0) return 'Required';
                    return null;
                  },
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                ),
              ),
              SizedBox(width: 8.w),
              const Text('hour'),
              IconButton(
                onPressed: () {
                  // increase hours by 1
                  int val = 1;
                  final int? p = int.tryParse(_durationCtrl.text.trim());
                  if (p != null) { val = p; }
                  val = val + 1;
                  _durationCtrl.text = val.toString();
                  setState(() {});
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          SizedBox(height: 12.h),

// custom booking slots (simple look)
          Text('Custom Booking Time Slots', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 8.h),

          FormField<bool>(
            key: _slotFieldKey,
            autovalidateMode: AutovalidateMode.always,
            validator: (_) => _slotError, // when non-null, shows red text
            builder: (field) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // simple container (no gradient, no glow)
                Container(
                  width: 1.0.sw,
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: _BoxPanel._fill, // same background as panel
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: const Color(0xFF8620E2).withOpacity(.25), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // header row with add button (positions unchanged)
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 18.sp, color: const Color(0xFF5B1BC2)),
                          SizedBox(width: 6.w),
                          Text('Add custom slot(s)', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          SizedBox(
                            height: 36.h,
                            child: OutlinedButton.icon(
                              onPressed: _onAddCustomSlot,
                              icon: const Icon(Icons.add),
                              label: const Text('Add time slot'),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: const Color(0xFF5B1BC2).withOpacity(.7), width: 1.2),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                              ),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 10.h),

                      // tiny hint (black text)
                      Text(
                        'Tip: Start time can be any minute, e.g. 07:30.',
                        style: TextStyle(fontSize: 10.sp, fontStyle: FontStyle.italic, color: Colors.black.withOpacity(.7)),
                      ),

                      SizedBox(height: 10.h),

                      // chips
                      if (_customSlots.isEmpty)
                        Container(
                          width: 1.0.sw,
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          alignment: Alignment.center,
                          child: Text('No slots yet. Tap "Add time slot".', style: TextStyle(fontSize: 12.sp, color: Colors.black)),
                        )
                      else
                        Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: List.generate(_customSlots.length, (int i) {
                            final int s = _customSlots[i]['startMin'] ?? 0;
                            final int e = _customSlots[i]['endMin'] ?? 0;

                            // simple pill: darker purple fill, black text, no shadow/glow
                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD9C9FF), // slightly darker than #EDDFFF
                                borderRadius: BorderRadius.circular(999.r),
                                border: Border.all(color: const Color(0xFF8620E2).withOpacity(.25), width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.access_time, size: 14.sp, color: Colors.black87),
                                  SizedBox(width: 6.w),
                                  Text(
                                    '${_showHHMM(s)} – ${_showHHMM(e)}',
                                    style: TextStyle(fontSize: 12.sp, color: Colors.black, fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(width: 8.w),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _customSlots.removeAt(i);
                                        // optional: if user removes last slot, you may set an error only on save
                                        // _setSlotError(null); // clear any previous error as they are editing
                                      });
                                    },
                                    child: Padding(
                                      padding: EdgeInsets.all(4.w),
                                      child: Icon(Icons.close, size: 14.sp, color: Colors.black87),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ),
                    ],
                  ),
                ),

                // red error line under the box
                if (field.errorText != null)
                  Padding(
                    padding: EdgeInsets.only(top: 6.h),
                    child: Text(
                      field.errorText!,
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: Theme.of(context).colorScheme.error,
                        height: 1.2,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: 12.h),



// manager
          Text('Assign Manager', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _managersStream(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const SizedBox(
                  height: 40,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final List<DropdownMenuItem<String>> items = <DropdownMenuItem<String>>[];
              for (final d in snap.data!.docs) {
                final Map<String, dynamic> m = d.data();
                String nm = 'Manager';
                if (m.containsKey('username') && m['username'] != null) {
                  nm = m['username'].toString();
                } else if (m.containsKey('name') && m['name'] != null) {
                  nm = m['name'].toString();
                }
                items.add(
                  DropdownMenuItem<String>(
                    value: d.id,
                    child: Text(nm),
                    onTap: () => _managerName = nm,
                  ),
                );
              }
              return DropdownButtonFormField<String>(
                value: _managerId,
                items: items,
                onChanged: (v) => setState(() => _managerId = v),
                validator: (v) {
                  if (v == null) return 'Required';
                  return null;
                },
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                hint: const Text('Option'),
              );
            },
          ),
          SizedBox(height: 12.h),

          // approval & disable toggle
          Row(
            children: [
              const Text('Require Approval'),
              const SizedBox(width: 8),
              Switch(
                value: _requireApproval,
                onChanged: (v) => setState(() => _requireApproval = v),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          if (isEdit) ...[
            Row(
              children: [
                const Text('Disable facility temporarily'),
                const SizedBox(width: 8),
                Switch(
                  value: _disableFacility,
                  onChanged: (v) => setState(() {
                    _disableFacility = v;
                    if (v) {
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      if (_inactiveRange == null || _inactiveRange!.end.isBefore(today)) {
                        _inactiveRange = DateTimeRange(start: today, end: today);
                      }
                    }
                  }),
                ),

              ],
            ),
            ...disableExtras,
          ],

          SizedBox(height: 16.h),

          // actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isEdit) ...[
                TextButton(
                  onPressed: () async {
                    final bool ok = await _confirmDelete();
                    if (ok) await _softDelete();
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
                SizedBox(width: 8.w),
                TextButton(onPressed: () => setState(() => _view = FacView.view), child: const Text('Cancel')),
                SizedBox(width: 8.w),
                ElevatedButton(onPressed: _saveEdit, child: const Text('Confirm')),
              ] else ...[
                TextButton(onPressed: widget.onClose, child: const Text('Cancel')),
                SizedBox(width: 8.w),
                ElevatedButton(onPressed: _saveNew, child: const Text('Add')),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// --- Auto-recover expired disabled facilities (run once on page open) ---
/// Goes through Facilities where active == false and inactiveTo <= now,
/// then flips them back to active and clears inactive fields. Batched writes.
Future<int> runFacilityHousekeepingOnce({
  BuildContext? context,
  bool showToast = false,
}) async {
  try {
    final DateTime now = DateTime.now();

    int appliedDisables = 0;
    int recovered = 0;

    // --- Pass A: apply scheduled disables (from <= now <= to) ---
        {
      final qs = await FirebaseFirestore.instance
          .collection('Facilities')
          .where('active', isEqualTo: true)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      int ops = 0;
      Future<void> commit() async {
        if (ops == 0) return;
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }

      for (final doc in qs.docs) {
        final m = doc.data();
        if (m['deleted'] == true) continue;
        if (m['inactiveFrom'] is! Timestamp || m['inactiveTo'] is! Timestamp) continue;

        final DateTime from = (m['inactiveFrom'] as Timestamp).toDate();
        final DateTime to   = (m['inactiveTo']   as Timestamp).toDate();
        final bool inWindow = !now.isBefore(from) && !now.isAfter(to); // from <= now <= to
        if (inWindow) {
          batch.update(doc.reference, {'active': false});
          ops++; appliedDisables++;
          if (ops >= 450) await commit();
        }
      }
      await commit();
    }

    // --- Pass B: recover expired disables (to <= now) ---
        {
      final qs = await FirebaseFirestore.instance
          .collection('Facilities')
          .where('active', isEqualTo: false)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      int ops = 0;
      Future<void> commit() async {
        if (ops == 0) return;
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }

      for (final doc in qs.docs) {
        final m = doc.data();
        if (m['deleted'] == true) continue;

        final ts = m['inactiveTo'];
        if (ts is! Timestamp) continue;

        final bool expired = !ts.toDate().isAfter(now); // inactiveTo <= now
        if (expired) {
          batch.update(doc.reference, {
            'active': true,
            'inactiveReason': null,
            'inactiveFrom': null,
            'inactiveTo': null,
          });
          ops++; recovered++;
          if (ops >= 450) await commit();
        }
      }
      await commit();
    }

    if (showToast && context != null) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(content: Text('Applied $appliedDisables scheduled disables, recovered $recovered')),
      );
    }

    return appliedDisables + recovered;
  } catch (e) {
    debugPrint('Housekeep error: $e');
    return 0;
  }
}

