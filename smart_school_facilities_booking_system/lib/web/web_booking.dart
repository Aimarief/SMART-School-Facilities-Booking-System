import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_school_facilities_booking_system/notification_service.dart';
import 'package:smart_school_facilities_booking_system/booking_service.dart';
import 'web_top_bar.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class WebBooking extends StatefulWidget {
  const WebBooking({Key? key}) : super(key: key);
  @override
  State<WebBooking> createState() => _WebBookingState();
}

class _WebBookingState extends State<WebBooking> {
  final _facSearch = TextEditingController();
  String? _userId;
  String _role = 'unknown';

  String? _selectedFacId;
  Map<String, dynamic>? _selectedFacData;

  @override
  void initState() {
    super.initState();
    _readUserAndRole();
  }

  @override
  void dispose() {
    _facSearch.dispose();
    super.dispose();
  }

  Future<void> _readUserAndRole() async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) {
      setState(() => {_userId = null, _role = 'unknown'});
      return;
    }
    String r = 'unknown';
    try {
      final doc = await FirebaseFirestore.instance.collection('UserInformation').doc(u.uid).get();
      r = (doc.data()?['role'] ?? 'unknown').toString();
    } catch (_) {}
    setState(() {
      _userId = u.uid;
      _role = r;
    });
  }

  void _selectFacility(String id, Map<String, dynamic> data) {
    setState(() {
      _selectedFacId = id;
      _selectedFacData = data;
    });
  }

  void _closeRight() {
    setState(() {
      _selectedFacId = null;
      _selectedFacData = null;
    });
  }
//---------------------------------------
// main build
//---------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PreferredSize(
        preferredSize: Size.fromHeight(70),
        child: WebCustomTopBar(use24HourFormat: true),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 1684.w),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _BookingLeftList(
                            width: 460.h,
                            height: 965.h,
                            search: _facSearch,
                            userId: _userId,
                            role: _role,
                            onSelect: _selectFacility,
                          ),
                          const SizedBox(width: 24),
                          _BookingRightPanel(
                            width: 1200.w,
                            height: 965.h,
                            selectedFacilityId: _selectedFacId,
                            selectedFacilityData: _selectedFacData,
                            onClose: _closeRight,
                          ),
                        ],
                      ),
                    ),
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

//---------------------------------------
// Build box design for left and right panel
//---------------------------------------
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

  static const _fill = Color(0xFFEDDFFF);
  static const _outline = Color(0xFF8620E2);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          if (header != null) ...[header!,  SizedBox(height: 8)],
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Scrollbar(thumbVisibility: true, child: child),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    Key? key,
    required this.controller,
    required this.onChanged,
  }) : super(key: key);

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search',
          prefixIcon: const Icon(Icons.search, size: 18),
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
//---------------------------------------
// list of facility
//---------------------------------------

class _ListTileCard extends StatelessWidget {
  const _ListTileCard({Key? key,
    required this.label,
    required this.onTap
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
//---------------------------------------
// Build the left list
//---------------------------------------
class _BookingLeftList extends StatefulWidget {
  const _BookingLeftList({
    Key? key,
    required this.width,
    required this.height,
    required this.search,
    required this.userId,
    required this.role,
    required this.onSelect,
  }) : super(key: key);

  final double width;
  final double height;
  final TextEditingController search;
  final String? userId;
  final String role;
  final void Function(String id, Map<String, dynamic> data) onSelect;

  @override
  State<_BookingLeftList> createState() => _BookingLeftListState();
}

class _BookingLeftListState extends State<_BookingLeftList> {
  Stream<QuerySnapshot<Map<String, dynamic>>> _facilitiesStream() =>
      FirebaseFirestore.instance.collection('Facilities').orderBy('name').snapshots();

//---------------------------------------
// left list that shows facilities base on manager
//---------------------------------------
  @override
  Widget build(BuildContext context) {
    return _BoxPanel(
      width: widget.width,
      height: widget.height,
      title: 'Facility',
      header: _SearchHeader(
        controller: widget.search,
        onChanged: (v) => setState(() {}),
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _facilitiesStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: Text('Loading...'));
          }
          if (snap.hasError) {
            return const Center(child: Text('Failed to load'));
          }
//---------------------------------------
// if it is deleted, not equal to the manager id , wll not display for user the facility for book
//---------------------------------------
          final q = widget.search.text.trim().toLowerCase();
          final results = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          for (final d in (snap.data?.docs ?? [])) {
            final m = d.data();
            final del = (m['deleted'] == true);
            final name = (m['name'] ?? '').toString();
            bool allowed;
            if (widget.role == 'Manager') {
              allowed = (m['managerId']) == (widget.userId);
            } else {
              allowed = widget.role != 'unknown';
            }
            final match = q.isEmpty || name.toLowerCase().contains(q);
            if (!del && allowed && match) results.add(d);
          }

          if (results.isEmpty) return const Center(child: Text('empty'));

          final List<Widget> children = <Widget>[];

          for (int i = 0; i < results.length; i++) {
            // take one document
            final doc = results[i];

            // get the map data safely
            final Map<String, dynamic> data = doc.data();

            // read the facility name (fallback to empty string)
            final String name = (data['name'] ?? '').toString();

            // add the tile
            children.add(
              _ListTileCard(
                label: name,
                onTap: () => widget.onSelect(doc.id, data), // onSelect
              ),
            );

            // add space except after the last item
            if (i < results.length - 1) {
              children.add(SizedBox(height: 8.h)); // use .h for scaling
            }
          }

// Return a normal ListView with our manually-built children
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: children,
          );
        },
      ),
    );
  }
}

//---------------------------------------
// build right list
//---------------------------------------
class _BookingRightPanel extends StatelessWidget {
  const _BookingRightPanel({
    Key? key,
    required this.width,
    required this.height,
    required this.selectedFacilityData,
    required this.onClose,
    this.selectedFacilityId,
  }) : super(key: key);

  final double width;
  final double height;
  final Map<String, dynamic>? selectedFacilityData;
  final VoidCallback onClose;
  final String? selectedFacilityId;

//---------------------------------------
// read if the field have value or not
//---------------------------------------
  String _s(Map<String, dynamic>? m, String k) => (m == null) ? '-' : (m[k]?.toString() ?? '-');

//---------------------------------------
//get start and end time
//---------------------------------------
  Map<String, String> _av(Map<String, dynamic>? m) {
    if (m != null && m['availableTime'] is Map) {
      final at = m['availableTime'] as Map;
      return {'start': (at['start'] ?? '-').toString(), 'end': (at['end'] ?? '-').toString()};
    }
    return {'start': '-', 'end': '-'};
  }

//---------------------------------------
// convert to hh mm
//---------------------------------------
  String _hhmm(String raw) {
    var s = raw.trim();
    if (s.isEmpty || s == '-') return '-';
    final p = s.split(':');
    final hh = (p.isNotEmpty ? p[0] : '0').padLeft(2, '0');
    final mm = (p.length > 1 ? p[1] : '0').padLeft(2, '0');
    return '$hh:$mm';
  }

//---------------------------------------
// build right side big box
//---------------------------------------
  @override
  Widget build(BuildContext context) {
    return _BoxPanel(
      width: width,
      height: height,
      title: 'Details',
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: _inner(context),
      ),
    );
  }

  Widget _inner(BuildContext context) {
    if (selectedFacilityData == null) {
      return SizedBox(
        height: 820,
        child: const Center(child: Text('Please pick an option', style: TextStyle(fontWeight: FontWeight.w600))),
      );
    }
//---------------------------------------
// get all the data and list here
//---------------------------------------
    final data = selectedFacilityData!;
    final name = _s(data, 'name');
    //---------------------------------------
// get all the custom slot
//---------------------------------------
    final at = _av(data);
    final start24 = _hhmm(at['start'] ?? '-');
    final end24 = _hhmm(at['end'] ?? '-');
    final timeline = (start24 != '-' && end24 != '-') ? '$start24 – $end24' : '-';
    final loc = _s(data, 'location');
    final det = _s(data, 'details');
    final dur = _s(data, 'bookingDurationHours');
    final imageName = _s(data, 'imageName');
    String facId = selectedFacilityId ?? _s(data, 'id');
    if (facId == '-' || facId.trim().isEmpty) facId = _s(data, 'facilityId');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        _buildFacilityImage(imageName),
        const SizedBox(height: 16),
        _row('Available Time', timeline),
        _row('Location', loc),
        _row('Description', det),
        _row('Duration per slot (hours)', dur),
        const SizedBox(height: 16),
        if (facId.trim().isNotEmpty && facId != '-')
          _MakeBookingSection(
            key: ValueKey('make-booking-$facId'),
            facilityId: facId,
            durationHoursText: dur,
            onClose: onClose,
          ),
      ],
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 300,
      height: 220,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: const Text('No Image', style: TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildFacilityImage(String imageName) {
    final raw = imageName.trim();
    if (raw.isEmpty || raw == '-') return _imagePlaceholder();

    // Build candidate paths to try in order.
    final bases = <String>[];
    if (raw.contains('/')) {
      // Already a path: try as-is.
      bases.add(raw);
    } else {
      // Try both common roots.
      bases.add('asset/image/$raw');   // your existing folder
    }

    List<String> variantsFor(String path) {
      final dot = path.lastIndexOf('.');
      final hasExt = dot >= 0;
      final base = hasExt ? path.substring(0, dot) : path;
      final ext  = hasExt ? path.substring(dot) : '';
      const exts = ['.jpg', '.png', '.jpeg'];

      final out = <String>[];
      if (hasExt) {
        // Try given ext, then swap others (lower + UPPER case)
        out.add(path);
        for (final e in exts) {
          if (e.toLowerCase() != ext.toLowerCase()) {
            out..add('$base$e')..add('$base${e.toUpperCase()}');
          }
        }
        // Also try the given ext in UPPER case, just in case.
        out.add('$base${ext.toUpperCase()}');
      } else {
        // No ext provided: try common ones (lower + UPPER)
        for (final e in exts) {
          out..add('$base$e')..add('$base${e.toUpperCase()}');
        }
      }
      return out;
    }

    final candidates = <String>[
      for (final b in bases) ...variantsFor(b),
    ];

    var i = 0;
    Widget tryNext() {
      if (i >= candidates.length) return _imagePlaceholder();
      final path = candidates[i++];
      return Image.asset(
        path,
        width: 300,
        height: 220,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => tryNext(),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: tryNext(),
    );
  }



  Widget _imageBox() => Container(
    width: 300,
    height: 220,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(.7),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.black12),
    ),
    child: const Text('No Image', style: TextStyle(fontWeight: FontWeight.w600)),
  );

//---------------------------------------
// show row details
//---------------------------------------
  Widget _row(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(v, style: const TextStyle(fontSize: 13)),
      ],
    ),
  );
}


class _UserPick {
  final String uid;
  final String username;
  final String email;
  final String role;
  _UserPick({required this.uid, required this.username, required this.email, required this.role});
}

//---------------------------------------
// Make Booking section
//---------------------------------------
class _MakeBookingSection extends StatefulWidget {
  const _MakeBookingSection({
    Key? key,
    required this.facilityId,
    required this.durationHoursText,
    required this.onClose,
  }) : super(key: key);

  final String facilityId;
  final String durationHoursText;
  final VoidCallback onClose;

  @override
  State<_MakeBookingSection> createState() => _MakeBookingSectionState();
}

class _MakeBookingSectionState extends State<_MakeBookingSection> {
  // colors
  final _cSelected = const Color(0xFFB779F1);
  final _cFull = Colors.red;
  final _cBorder = const Color(0xFFE5E7EB);

  // user field & suggestions
  final _userCtrl = TextEditingController();
  final _userFocus = FocusNode();
  bool _showDropdown = false;
  bool _loadingUsers = false;
  bool _searchingUser = false;
  final List<_UserPick> _all = [];
  final List<_UserPick> _sug = [];
  String? _validatedUid;

  // selection
  DateTime? _selectedDate;
  String _ymd = '';
  String _slotKey = '';
  int _seatIdx = -1;

  // facility config
  int _capacity = 0;
  String? _managerId;
  final List<Map<String, String>> _slots = [];
  final Map<String, int> _dayBooked = {};
  final List<bool> _seatTaken = [];

  // system rules
  List<bool> _weekdayOpen = List<bool>.filled(7, true);
  final Set<String> _offDays = {};

  // inactive window (inclusive) if both present
  DateTime? _inactiveFrom, _inactiveTo;

  // loading flags
  bool _loadingSettings = false;
  bool _loadingFacility = false;
  bool _loadingDayBooked = false;
  bool _loadingSeats = false;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndOffDays();
    _loadFacilityConfig();
    _userFocus.addListener(() {
      if (!_userFocus.hasFocus) {
        if (!mounted) return;
        setState(() {
          _showDropdown = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _userFocus.dispose();
    super.dispose();
  }

  void _toast(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  //---------------------------------------
// get hh:mm format
//---------------------------------------

  String _normalizeHHmm(String s) {
    var t = s.trim();
    final p = t.split(':');
    return '${(p.isNotEmpty ? p[0] : '0').padLeft(2, '0')}:${(p.length > 1 ? p[1] : '0').padLeft(2, '0')}';
  }
//---------------------------------------
// parse hour to min
//---------------------------------------

  int _hmToMin(String s) {
    final p = _normalizeHHmm(s).split(':');
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }
//---------------------------------------
// parse minute to hour
//---------------------------------------

  String _minToHHmm(int m) {
    final h = (m ~/ 60) % 24, mm = m % 60;
    return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }

//---------------------------------------
// make it . between the time
//---------------------------------------
  String _fmtDot(String s) {
    final p = _normalizeHHmm(s).split(':');
    return (p.length >= 2) ? '${p[0]}.${p[1]}' : s;
  }
//---------------------------------------
// turn them into slot key
//---------------------------------------
  String _slotKeyFromStart(String s) {
    final n = _normalizeHHmm(s);
    return n.replaceAll(':', '');
    // e.g. "09:30" -> "0930"
  }

//---------------------------------------
// convert to real year month and date
//---------------------------------------
  String _ymdOf(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _isHoliday(DateTime d) => _offDays.contains(_ymdOf(d));
  bool _isWorkingDay(DateTime d) {
    final idx = d.weekday - 1;
    return (idx >= 0 && idx < _weekdayOpen.length) ? _weekdayOpen[idx] : true;
  }
//---------------------------------------
// turn the unavailable date to date format
//---------------------------------------
  DateTime? _dateOnly(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) {
      final dt = v.toDate();
      return DateTime(dt.year, dt.month, dt.day);
    }
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    if (v is String) {
      final p = DateTime.tryParse(v);
      if (p != null) return DateTime(p.year, p.month, p.day);
    }
    return null;
  }

  String _endForStart(String startHHmm) {
    final s = _normalizeHHmm(startHHmm);
    final map = <String, String>{ for (final m in _slots) _normalizeHHmm(m['start'] ?? '') : _normalizeHHmm(m['end'] ?? '') };
    final e = (map[s] ?? _minToHHmm(_hmToMin(s) + 60));
    return _normalizeHHmm(e);
  }

  bool _isTodaySelected() {
    if (_selectedDate == null) return false;
    final n = DateTime.now(), d = _selectedDate!;
    return n.year == d.year && n.month == d.month && n.day == d.day;
  }
//---------------------------------------
// check if slot is past already
//---------------------------------------
  bool _slotIsPast(String key) {
    if (!_isTodaySelected() || key.length < 4) return false;
    final now = DateTime.now();
    final hh = int.tryParse(key.substring(0, 2)) ?? 0;
    final mm = int.tryParse(key.substring(2, 4)) ?? 0;
    final start = DateTime(now.year, now.month, now.day, hh, mm);
    return !now.isBefore(start);
  }

//---------------------------------------
// load the off days from system information
//---------------------------------------
  Future<void> _loadSettingsAndOffDays() async {
    setState(() => _loadingSettings = true);
    try {
      final setDoc = await FirebaseFirestore.instance.collection('SystemInformation').doc('Setting').get();
      final m = setDoc.data();
      if (m != null) {
        _weekdayOpen = [
          (m['Monday'] ?? true) == true,
          (m['Tuesday'] ?? true) == true,
          (m['Wednesday'] ?? true) == true,
          (m['Thursday'] ?? true) == true,
          (m['Friday'] ?? true) == true,
          (m['Saturday'] ?? true) == true,
          (m['Sunday'] ?? true) == true,
        ];
      }

      final off = await FirebaseFirestore.instance.collection('SystemInformation').doc('OffDays').get();
      final set = <String>{};
      final om = off.data();
      if (om != null && om['offDays'] is List) {
        for (final it in (om['offDays'] as List)) {
          if (it is String) set.add(it.trim());
          if (it is Timestamp) set.add(_ymdOf(it.toDate()));
          if (it is Map) {
            final v = it['date'] ?? it['dateYMD'];
            if (v is String) set.add(v.trim());
            if (v is Timestamp) set.add(_ymdOf(v.toDate()));
          }
        }
      }

      setState(() {
        _offDays
          ..clear()
          ..addAll(set);
      });
    } catch (_) {
      _toast('Failed to load system settings.');
    } finally {
      setState(() => _loadingSettings = false);
    }
  }
//---------------------------------------
// load the slot, unavailable date, and sort the slot, also load date that disable in facility
//---------------------------------------
  Future<void> _loadFacilityConfig() async {
    setState(() => _loadingFacility = true);
    try {
      final facDoc = await FirebaseFirestore.instance.collection('Facilities').doc(widget.facilityId).get();
      final fd = facDoc.data();

      _managerId = (fd?['managerId'] ?? '').toString();
//---------------------------------------
// get teh available slot
//---------------------------------------
      int cap = fd?['availableSlots'];
//---------------------------------------
// get the time slot
//---------------------------------------
      final tmp = <Map<String, String>>[];
       if (fd?['customTimeSlots'] is List) {
        for (final it in (fd?['customTimeSlots'] as List)) {
          if (it is Map<String, dynamic>) {
            final s = (it['start'] ?? '').toString().trim();
            final e = (it['end'] ?? '').toString().trim();
            if (s.isNotEmpty || e.isNotEmpty) tmp.add({'start': s, 'end': e, 'key': _slotKeyFromStart(s)});
          }
        }
      }
      tmp.sort((a, b) => (a['key'] ?? '').compareTo(b['key'] ?? ''));

      setState(() {
        _capacity = cap;
        _slots
          ..clear()
          ..addAll(tmp);
//---------------------------------------
// get the inactaive date for that facility
//---------------------------------------
        _inactiveFrom = _dateOnly(fd?['inactiveFrom']);
        _inactiveTo = _dateOnly(fd?['inactiveTo']);
      });
    } catch (_) {
      _toast('Failed to load facility settings.');
    } finally {
      setState(() => _loadingFacility = false);
    }
  }

//---------------------------------------
// load the the slot from database
//---------------------------------------
  Future<void> _loadDayBooked(String ymd) async {
    setState(() {
      _loadingDayBooked = true;
      _dayBooked.clear();
      _slotKey = '';
      _seatIdx = -1;
      _seatTaken.clear();
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('Facilities').doc(widget.facilityId)
          .collection('Days').doc(ymd)
          .collection('Slots').get();

      final tmp = <String, int>{};
      for (final d in snap.docs) {
        final m = d.data();
        int b = 0;
//---------------------------------------
// it find the document for each slot and find the booked quantity
//---------------------------------------
        final v = m['booked'];
        if (v is int)
          b = v;

        tmp[d.id] = b;
      }
      setState(() {
        _dayBooked
          ..clear()
          ..addAll(tmp);
      });
    } catch (_) {
      _toast('Failed to load day availability.');
    } finally {
      setState(() => _loadingDayBooked = false);
    }
  }
//---------------------------------------
// load the seats for the time slot that is pick
//---------------------------------------
  Future<void> _loadSeats(String ymd, String slotKey) async {
    setState(() {
      _loadingSeats = true;
      _seatTaken
        ..clear()
        ..addAll(List<bool>.filled(_capacity, false));
      _seatIdx = -1;
    });
    try {
      final seatsSnap = await FirebaseFirestore.instance
          .collection('Facilities').doc(widget.facilityId)
          .collection('Days').doc(ymd)
          .collection('Slots').doc(slotKey)
          .collection('Seats').get();

      //---------------------------------------
// loop all teh seat
//---------------------------------------
      for (final doc in seatsSnap.docs) {

        final int? idNum = int.tryParse(doc.id);
        if (idNum == null) continue;

        final int idx = idNum - 1;

        final Map<String, dynamic> data = doc.data();
        final bool taken = data['taken'] == true;
        if (taken) {
          _seatTaken[idx] = true;
        }
      }

      setState(() {});
    } catch (_) {
      _toast('Failed to load seats.');
    } finally {
      setState(() => _loadingSeats = false);
    }
  }
//---------------------------------------
// get student or lecturer role for booking
//---------------------------------------
  bool _isAllowedRole(String role) {
    final r = role.toLowerCase().trim();
    return r == 'student' || r == 'lecturer';
  }

//---------------------------------------
// load the user in userinformation and get email and username
//---------------------------------------

  Future<void> _loadUsersOnce() async {
    if (_loadingUsers || _all.isNotEmpty) return;
    setState(() => _loadingUsers = true);
    try {
      final qs = await FirebaseFirestore.instance
          .collection('UserInformation')
          .limit(300)
          .get();

      final tmp = <_UserPick>[];
      for (final d in qs.docs) {
        final m = d.data();
        final role = (m['role'] ?? '').toString();
        if (!_isAllowedRole(role)) continue;   // only Student / Lecturer
        tmp.add(_UserPick(
          uid: d.id,
          username: (m['username']).toString(),
          email: (m['email']).toString(),
          role: role,
        ));
      }

      setState(() {
        _all
          ..clear()
          ..addAll(tmp);
      });
    } finally {
      setState(() => _loadingUsers = false);
    }
  }
//---------------------------------------
// when search button press, search for the user
//---------------------------------------
  Future<String?> _findUserByQuery(String input) async {
    final q = input.trim();
    if (q.isEmpty) return null;

    Future<String?> tryField(String field, String value) async {
      final res = await FirebaseFirestore.instance
          .collection('UserInformation')
          .where(field, isEqualTo: value) // exact match only
          .get();

      for (final d in res.docs) {
        final m = d.data();
        final role = (m['role'] ?? '').toString();
        if (_isAllowedRole(role)) return d.id;// Student/Lecturer only
      }
      return null;
    }

    if (q.contains('@')) {
      return await tryField('email', q);// exact email
    } else {
      return await tryField('username', q);// exact username
    }
  }

//---------------------------------------
// while searching for user clears everything
//---------------------------------------
  Future<void> _onUserChanged(String value) async {
    setState(() {
      _validatedUid = null;
      _selectedDate = null;
      _ymd = '';
      _slotKey = '';
      _seatIdx = -1;
      _seatTaken.clear();
      _dayBooked.clear();
    });

    final q = value.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _showDropdown = false;
        _sug.clear();
      });
      return;
    }

    await _loadUsersOnce();

    final found = <_UserPick>[];
//---------------------------------------
// find max 8 user only that are closest to key word
//---------------------------------------
    for (final u in _all) {
      if (u.username.toLowerCase().contains(q) || u.email.toLowerCase().contains(q)) {
        found.add(u);
        if (found.length >= 8) break;
      }
    }

    setState(() {
      _sug
        ..clear()
        ..addAll(found);
      _showDropdown = true;
    });
  }

//---------------------------------------
// after u pick the user form drop down
//---------------------------------------
  void _pickSuggestion(_UserPick u) {
    if (!_isAllowedRole(u.role)) {
      _toast('Only Student or Lecturer can be booked.');
      setState(() => _validatedUid = null);
      return;
    }

    final txt = (u.email.isNotEmpty ? u.email : u.username).trim();

    // Put the value in the field right now and keep the caret at the end.
    _userCtrl.clear();
    _userCtrl.text = txt;
    _userCtrl.selection = TextSelection.collapsed(offset: txt.length);
    _userFocus.requestFocus();

    // close the dropdown and reset the rest.
    setState(() {
      _showDropdown = false;
      _validatedUid = null;
      _selectedDate = null;
      _ymd = '';
      _slotKey = '';
      _seatIdx = -1;
      _seatTaken.clear();
      _dayBooked.clear();
    });

    _toast('User placed. Press Search to validate.');
  }
//---------------------------------------
// search user text box
//---------------------------------------
  Future<void> _onSearchUser() async {
    final input = _userCtrl.text.trim();
    if (input.isEmpty) {
      _toast('Please enter an email or username.');
      return;
    }
    setState(() => _searchingUser = true);
    try {
      final uid = await _findUserByQuery(input);
      if (uid == null || uid.isEmpty) {
        setState(() => _validatedUid = null);
        _toast('No user exists for that email/username.');
        return;
      }
      // double-check role
      String role = '';
      try {
        final snap = await FirebaseFirestore.instance.collection('UserInformation').doc(uid).get();
        role = (snap.data()?['role'] ?? '').toString();
      } catch (_) {}
      if (!_isAllowedRole(role)) {
        setState(() => _validatedUid = null);
        _toast('Not allowed to book for Admin or Manager accounts.');
        return;
      }
//---------------------------------------
// when user is found, set the value
//---------------------------------------
      setState(() {
        _validatedUid = uid;
        _selectedDate = null;
        _ymd = '';
        _slotKey = '';
        _seatIdx = -1;
        _seatTaken.clear();
        _dayBooked.clear();
        _showDropdown = false;
      });
      _toast('User found.');
    } finally {
      if (mounted) setState(() => _searchingUser = false);
    }
  }

//---------------------------------------
// check if there are conflict while making booking
//---------------------------------------
  Future<String> _conflict({
    required String userId,
    required String dateYMD,
    required String newStartHHmm,
    required String newEndHHmm,
  }) async {
    try {
      final sN = _normalizeHHmm(newStartHHmm);
      var eN = _normalizeHHmm(newEndHHmm);
      if (eN.isEmpty) eN = _endForStart(sN);
      final sM = _hmToMin(sN), eM = _hmToMin(eN);

      final qs = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('userId', isEqualTo: userId)
          .where('bookingDate', isEqualTo: dateYMD)
          .get();

      for (final d in qs.docs) {
        final m = d.data();
//---------------------------------------
// make sure its no deleted
//---------------------------------------
        final del = m['deleted'];
        final isDeleted = del == 'true';
        if (isDeleted) continue;

        final ap = (m['approval'] ?? '').toString().toLowerCase().trim();
        if (!(ap == 'accepted' || ap == 'pending')) continue;

        var s = _normalizeHHmm((m['start'] ?? m['startTime'] ?? '').toString());
        if (s.isEmpty) continue;
        var e = _normalizeHHmm((m['end'] ?? m['endTime'] ?? '').toString());
        if (e.isEmpty) e = _endForStart(s);

        final es = _hmToMin(s), ee = _hmToMin(e);
        if (sM < ee && eM > es) { // check if there is overlap time
          //overlap time
          return 'Overlap with other booking ${_fmtDot(s)} - ${_fmtDot(e)}. '
          //new time
              'New time ${_fmtDot(sN)} - ${_fmtDot(eN)} is not allowed.';
        }
      }
      return '';
    } catch (_) {
      return 'Could not verify the other bookings. Please try again.';
    }
  }

//---------------------------------------
// show in calendar whcih date and day can be book
//---------------------------------------
  bool _selectable(DateTime d) {
    if (_isHoliday(d) || !_isWorkingDay(d)) return false;
    if (_inactiveFrom != null && _inactiveTo != null) {
      final x = DateTime(d.year, d.month, d.day);
      if (!x.isBefore(_inactiveFrom!) && !x.isAfter(_inactiveTo!)) return false;
    }
    return true;
  }

  DateTime? _firstSelectable(DateTime first, DateTime last, DateTime pref) {
    if (_selectable(pref)) return pref;
    var c = pref;
    while (!c.isAfter(last)) { if (_selectable(c)) return c; c = c.add(const Duration(days: 1)); }
    c = pref;
    while (!c.isBefore(first)) { if (_selectable(c)) return c; c = c.subtract(const Duration(days: 1)); }
    return null;
  }
//---------------------------------------
// allow user to pick a date which is not holiday and offday
//---------------------------------------
  Future<void> _pickDate() async {
    if (_offDays.isEmpty && !_loadingSettings) {
      _loadSettingsAndOffDays(); // fire-and-forget
    }
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day);
    final last = DateTime(now.year + 1, now.month, now.day);
    final init = _firstSelectable(first, last, _selectedDate ?? first);
    if (init == null) { _toast('No selectable dates available.'); return; }

    final picked = await showDatePicker(
      context: context,
      initialDate: init, //selectable date
      firstDate: first,// show today until last date only can be book
      lastDate: last, //last date show until next year
      selectableDayPredicate: _selectable,//for each day , it will check available or not
    );

    if (picked != null) {
      final y = _ymdOf(picked);
      setState(() {
        _selectedDate = picked;
        _ymd = y;
        _slotKey = '';
        _seatIdx = -1;
        _seatTaken.clear();
        _dayBooked.clear();
      });
      await _loadDayBooked(y);// start to checked the booked
    }
  }

//---------------------------------------
// when confirm booking is press
//---------------------------------------
  Future<void> _onConfirm() async {
//---------------------------------------
// check every thing is get or return false
//---------------------------------------
    if (_validatedUid == null || _validatedUid!.isEmpty) { _toast('Pick a user first.'); return; }
    if (_ymd.isEmpty) { _toast('Please pick a date.'); return; }
    if (_slotKey.isEmpty) { _toast('Please pick a time slot.'); return; }
    if (_seatIdx < 0) { _toast('Please pick a seat.'); return; }

    final me = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (me.isEmpty) { _toast('Please sign in.'); return; }

    final ts = _slots.firstWhere((m) => m['key'] == _slotKey, orElse: () => <String, String>{});

//---------------------------------------
// get start time and end time for the picked slot
//---------------------------------------
    final selStart = _normalizeHHmm((ts['start'] ?? '').trim());
    final selEndCheck = _normalizeHHmm((ts['end'] ?? '').trim().isEmpty ? _endForStart(selStart) : (ts['end'] ?? '').trim());

    if (!(_hmToMin(selStart) < _hmToMin(selEndCheck))) {
      _toast('End time must be after start time.');
      return;
    }

    final reason = await _conflict(
      userId: _validatedUid!,
      dateYMD: _ymd,
      newStartHHmm: selStart,
      newEndHHmm: selEndCheck,
    );
    if (reason.isNotEmpty) { _toast(reason); return; }

    final seat1 = _seatIdx + 1;
    try {
      final bookingBase = <String, dynamic>{
        'userId': _validatedUid!,
        'facilityId': widget.facilityId,
        'managerId': _managerId ?? '',
        'bookingDate': _ymd,
        'start': selStart,
        'end': selEndCheck,
        'slotKey': _slotKey,
        'seatIndex': seat1,
        'status': 'upcoming',
        'approval': 'accepted',
        'seen': false,
        'userSeen': false,
        'rated': false,
        'rejectedAt': null,
        'deleted': false,
        'createdAt': FieldValue.serverTimestamp(),
        if (_userCtrl.text.trim().isNotEmpty) 'bookedByEmail': _userCtrl.text.trim(),
      };
//---------------------------------------
// create new booking
//---------------------------------------

      final newId = await BookingService.createBookingPickSeatTx(
        facilityId: widget.facilityId,
        dateYMD: _ymd,
        slotKey: _slotKey,
        seatIndex: seat1,
        bookingBase: bookingBase,
      );
//---------------------------------------
// send notification
//---------------------------------------
      await NotificationService.sendBookingCreatedMails(
        bookingId: newId,
        userId: _validatedUid!,
        bookedBy: me,
        facilityId: widget.facilityId,
        managerId: _managerId ?? '-',
        approval: 'accepted',
        start: selStart,
        end: selEndCheck,
        bookingDate: _ymd,
        seatIndex: seat1,
      );

      _toast('Booking created.');
      if (mounted) widget.onClose();
    } catch (e) {
      _toast('Slot is taken');
    }
  }

//---------------------------------------
// main build for the booking panel
//---------------------------------------
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF9F4FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _cBorder),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Make a Booking', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),

              _title('Booked by'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        focusNode: _userFocus,
                        controller: _userCtrl,
                        onChanged: (v) => _onUserChanged(v),
                        onSubmitted: (_) => _onSearchUser(),
                        keyboardType: TextInputType.text,
                        inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'email or username',
                          prefixIcon: const Icon(Icons.person_search, size: 18),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),

                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: _searchingUser ? null : _onSearchUser,
                      icon: _searchingUser
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.search, size: 18),
                      label: const Text('Search', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
//---------------------------------------
// if it shows drop down means there is user
//---------------------------------------
              if (_showDropdown) ...[
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 240),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _cBorder),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: _sug.isEmpty
                      ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Text(_loadingUsers ? 'Loading users...' : 'No matches', style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                  )
//---------------------------------------
// display all the name and email of drop down
//---------------------------------------
                      : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: _sug.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final u = _sug[i];
                      return Listener(
                        behavior: HitTestBehavior.opaque, // make the whole row clickable
//---------------------------------------
// on tap
//---------------------------------------
                        onPointerDown: (_) => _pickSuggestion(u), //fires BEFORE focus changes
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.account_circle, size: 20, color: Color(0xFF6B7280)),
                          title: Text(
                            u.username.isEmpty ? '(no username)' : u.username,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            u.email.isEmpty ? '(no email)' : u.email,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
//---------------------------------------
// if no user pick
//---------------------------------------
              if (_validatedUid == null)
                _hint('Pick a user first.')
//---------------------------------------
// allow u to pick date
//---------------------------------------
              else
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        child: Text('Pick Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _pill('Selected', _ymd.isEmpty ? '-' : _ymd)),
                  ],
                ),
              if (_loadingSettings) ...[
                const SizedBox(height: 10),
                _loading('Loading calendar rules...'),
              ],

              SizedBox(height: 16),
              Divider(height: 1),
              SizedBox(height: 12),
//---------------------------------------
// choose time slot
//---------------------------------------

              _title('2) Choose Time Slot'),
              const SizedBox(height: 8),
              if (_ymd.isEmpty)
                _hint('Pick a date first.')
              else
//---------------------------------------
// bring u to place that display time slot
//---------------------------------------
                _slotWrap(),

              if (_loadingFacility || _loadingDayBooked) ...[
                const SizedBox(height: 10),
                _loading('Loading time slots...'),
              ],

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
//---------------------------------------
// choose seat
//---------------------------------------

              _title('3) Choose Seat / Slot Number'),
              const SizedBox(height: 8),
              if (_slotKey.isEmpty)
                _hint('Pick a time slot first.')
              else
//---------------------------------------
// bring u to place that display seat slot
//---------------------------------------
                _seatWrap(),
              if (_loadingSeats) ...[
                const SizedBox(height: 10),
                _loading('Loading seats...'),
              ],

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: widget.onClose,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text('Close', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
//---------------------------------------
// when confirm button press
//---------------------------------------
                  ElevatedButton(
                    onPressed: (_validatedUid == null) ? null : _onConfirm,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Text('Confirm', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

//---------------------------------------
// widget decoration
//---------------------------------------
  Widget _title(String s) => Text(s, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF111827)));
  Widget _hint(String s) => Text(s, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)));
  Widget _loading(String s) => Row(children: [const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: 8), Expanded(child: Text(s, style: const TextStyle(fontSize: 12)))]);

  //---------------------------------------
// show date box
//---------------------------------------
  Widget _pill(String k, String v) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(color: const Color(0xFFFBFBFF), borderRadius: BorderRadius.circular(10), border: Border.all(color: _cBorder)),
    child: Row(children: [Text('$k: ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), Expanded(child: Text(v, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))]),
  );

  Widget _slotWrap() {
    if (_slots.isEmpty && !_loadingFacility) return _hint('No time slots configured for this facility.');

    final List<Widget> slotWidgets = <Widget>[];

    for (int i = 0; i < _slots.length; i++) {
      final Map<String, String> slotMap = _slots[i];

      slotWidgets.add(_slotBox(slotMap));
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xFFFBFBFF), borderRadius: BorderRadius.circular(10), border: Border.all(color: _cBorder)),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: slotWidgets,
      ),
    );
  }

//---------------------------------------
// show each time slot box
//---------------------------------------
  Widget _slotBox(Map<String, String> s) {
    final start = s['start'] ?? '';
    final end = s['end'] ?? '';
    final key = s['key'] ?? '';

    final past = _slotIsPast(key);
    final booked = _dayBooked[key] ?? 0;
//---------------------------------------
// since we got the daybooked key then we check if the capacity which is the available slot is bigger than the booked in the slot
// list all the time slot with colour
//---------------------------------------
    final full = _capacity > 0 && booked >= _capacity;
    final selected = _slotKey == key;

    Color bg; Color fg; BoxDecoration deco;
    if (past) {
      bg = const Color(0xFFE5E7EB); fg = const Color(0xFF9CA3AF);
      deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _cBorder));
    } else if (full) {
      bg = _cFull; fg = Colors.white;
      deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10));
    } else if (selected) {
      bg = _cSelected; fg = Colors.white; deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10));
    } else {
      bg = Colors.white; fg = const Color(0xFF111827); deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _cBorder));
    }
//---------------------------------------
// display the time in each slot
//---------------------------------------
    final label = start.isNotEmpty
        ? (end.isNotEmpty ? '${_fmtDot(start)} - ${_fmtDot(end)}' : _fmtDot(start))
        : key;

    return InkWell(
      onTap: () async {
        if (past) { _toast('This time slot has already passed.'); return; }
        if (full) { _toast('This time slot is full.'); return; }

//---------------------------------------
// so it will hold the slot key for now when it was selected
//---------------------------------------
        setState(() {
          _slotKey = key;
          _seatIdx = -1;
          _seatTaken.clear();
        });
        await _loadSeats(_ymd, key); // load the seat slot
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: deco,
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }
//---------------------------------------
// display a space for seat slot
//---------------------------------------
  Widget _seatWrap() {
    if (_capacity <= 0 && !_loadingSeats) return _hint('No seat capacity set for this facility.');
    final List<Widget> seatWidgets = <Widget>[];

    for (int i = 0; i < _capacity; i++) {
      seatWidgets.add(_seatBox(i));
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xFFFBFBFF), borderRadius: BorderRadius.circular(10), border: Border.all(color: _cBorder)),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: seatWidgets,
      ),
    );
  }
//---------------------------------------
// list all the seat slot with colour
//---------------------------------------
  Widget _seatBox(int index) {
    final taken = (index < _seatTaken.length) ? (_seatTaken[index] == true) : false;
    final selected = (_seatIdx == index);

    Color bg; Color fg; BoxDecoration deco;
    if (taken) {
      bg = _cFull; fg = Colors.white; deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10));
    } else if (selected) {
      bg = _cSelected; fg = Colors.white; deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10));
    } else {
      bg = Colors.white; fg = const Color(0xFF111827); deco = BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _cBorder));
    }

    return InkWell(
      onTap: () {
        if (taken) { _toast('This seat is already taken.'); return; }
        setState(() => _seatIdx = index);
      },
      child: Container(
        width: 56,
        height: 44,
        alignment: Alignment.center,
        decoration: deco,
        //becasue always start from 0 so +1 to see the correct slots
        child: Text('${index + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      ),
    );
  }
}
