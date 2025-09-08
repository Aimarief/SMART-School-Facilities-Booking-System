import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'web_top_bar.dart';
import 'package:smart_school_facilities_booking_system/notification_service.dart';

class WebFacilities extends StatefulWidget {
  const WebFacilities({Key? key}) : super(key: key);

  @override
  State<WebFacilities> createState() => _WebFacilitiesState();
}

class _WebFacilitiesState extends State<WebFacilities> {
  final bool _use24HourFormat = true;

  // Left search (Facilities)
  final TextEditingController _facSearch = TextEditingController();

  // Selection for the right panel
  String? _facId;
  Map<String, dynamic>? _facData;

  // Right panel mode
  String _facInitial = 'view'; // 'add' | 'view' | 'edit'

  void _openAddFacility() {
    setState(() {
      _facInitial = 'add';
      _facId = null;
      _facData = null;
    });
  }

  void _selectFacility(String id, Map<String, dynamic> data) {
    setState(() {
      _facId = id;
      _facData = data;
      _facInitial = 'view';
    });
  }

  void _closeRight() {
    setState(() {
      _facId = null;
      _facData = null;
      _facInitial = 'view';
    });
  }

  void _onFacilityUpdated(String? id, Map<String, dynamic>? updated) {
    setState(() {
      _facId = id;
      _facData = updated;
      _facInitial = 'view';
    });
  }



  @override
  void dispose() {
    _facSearch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: WebCustomTopBar(use24HourFormat: _use24HourFormat),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 460.w + 24.w + 1200.w,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // LEFT: Facilities list
                          FacilityLeftList(
                            width: 460.w,
                            height: 965.h,
                            search: _facSearch,
                            onAddTap: _openAddFacility,
                            onSelect: _selectFacility,
                          ),
                          SizedBox(width: 24.w),
                          // RIGHT: Details
                          FacilityRightPanel(
                            width: 1200.w,
                            height: 965.h,
                            selectedFacilityId: _facId,
                            selectedFacilityData: _facData,
                            initialView: _facInitial,
                            onClose: _closeRight,
                            onFacilityUpdated: _onFacilityUpdated,
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
            height: 48.h,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search, size: 18),
                contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 8.w),
        SizedBox(
          height: 40.h,
          width: 40.h,
          child: OutlinedButton(
            onPressed: onAddTap,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            child: const Icon(Icons.add, size: 18),
          ),
        ),
      ],
    );
  }
}

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
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w500),
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
            if (m.containsKey('deleted')) {
              if (m['deleted'] == true) {
                del = true;
              }
            }

            String name = '';
            if (m.containsKey('name')) {
              if (m['name'] != null) {
                name = m['name'].toString();
              }
            }

            bool matches = true;
            if (q.isNotEmpty) {
              final String lower = name.toLowerCase();
              if (!lower.contains(q)) {
                matches = false;
              }
            }

            if (!del) {
              if (matches) {
                filtered.add(d);
              }
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
              if (data.containsKey('name')) {
                if (data['name'] != null) {
                  name = data['name'].toString();
                }
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

  final String initialView; // 'add' | 'view' | 'edit'

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

  // Capacities
  int _requiredCapacity = 1;
  int _maxCapacity = 1;

  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  List<Map<String, int>> _customSlots = <Map<String, int>>[];
  bool _requireApproval = false;
  bool _disableFacility = false;
  bool _isRangePickerOpen = false;
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
  String _view = 'view';

  // --- Assets base folder ---
  static const String _assetDir = 'asset/image';

  @override
  void initState() {
    super.initState();
    _view = widget.initialView;
    _hydrateFromSelected();
    if (_view == 'add') {
      _resetAddDefaults();
    }
  }

  @override
  void didUpdateWidget(covariant FacilityRightPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialView != _view) {
      _view = widget.initialView;
    }
    _hydrateFromSelected();
    if (_view == 'add') {
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

  int _safeParseInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v == null) return fallback;
    final int? p = int.tryParse(v.toString());
    return p ?? fallback;
  }

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
      final col = FirebaseFirestore.instance.collection('SystemInformation');

      // Correct doc id (capital S)
      DocumentSnapshot<Map<String, dynamic>> doc = await col.doc('Setting').get();

      // Optional legacy fallback (lowercase) if you really need it:
      if (!doc.exists) {
        final lower = await col.doc('settings').get();
        if (lower.exists) doc = lower;
      }

      // Last-resort fallback: find any doc that has start/end (without returning null in orElse)
      if (!doc.exists) {
        final qs = await col.get();
        QueryDocumentSnapshot<Map<String, dynamic>>? hit;
        for (final d in qs.docs) {
          final m = d.data();
          if (m.containsKey('start') && m.containsKey('end')) {
            hit = d;
            break;
          }
        }
        if (hit == null) return null;
        doc = hit; // QueryDocumentSnapshot extends DocumentSnapshot, so this is fine
      }

      final data = doc.data();
      if (data == null) return null;

      final start = _parseToMinutes(data['start']);
      final end   = _parseToMinutes(data['end']);
      if (start < 0 || end < 0) return null;

      return {'start': start, 'end': end};
    } catch (_) {
      return null;
    }
  }

  Future<void> _notifyBookingsInDisabledRange({
    required String facilityId,  // facility doc id
    required DateTime startDay,  // range start (00:00)
    required DateTime endDay,    // range end (23:59:59.999)
  }) async {
    try {
      // 1) read all bookings for this facility (simple, then filter in memory)
      final QuerySnapshot<Map<String, dynamic>> qs = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('facilityId', isEqualTo: facilityId)
          .get();

      // 2) loop every booking and decide if we should notify the user
      for (final doc in qs.docs) {
        final Map<String, dynamic> m = doc.data();

        // ignore soft-deleted bookings
        if (m.containsKey('deleted')) {
          if (m['deleted'] is bool) {
            if (m['deleted'] == true) {
              continue;
            }
          }
        }

        // ignore status = ended
        String statusStr = '';
        if (m.containsKey('status') && m['status'] != null) {
          statusStr = m['status'].toString().toLowerCase().trim();
        }
        if (statusStr == 'ended') {
          continue;
        }

        // read booking date (supports Timestamp or "YYYY-MM-DD")
        final DateTime? bd = _readBookingDate(m);
        if (bd == null) continue;

        // compare by date only
        final DateTime only = DateTime(bd.year, bd.month, bd.day);
        if (only.isBefore(startDay)) continue;
        if (only.isAfter(endDay)) continue;

        // ignore approval = rejected
        final String approval = _readApprovalLower(m);
        if (approval == 'rejected') continue;

        // read userId (several possible keys)
        String userId = '';
        if (m.containsKey('userId') && m['userId'] != null) {
          userId = m['userId'].toString().trim();
        } else if (m.containsKey('bookBy') && m['bookBy'] != null) {
          userId = m['bookBy'].toString().trim();
        } else if (m.containsKey('bookedBy') && m['bookedBy'] != null) {
          userId = m['bookedBy'].toString().trim();
        }
        if (userId.isEmpty) continue; // nothing to notify

        // seatIndex (int; default 0 if missing)
        int seatIndex = 0;
        if (m.containsKey('seatIndex') && m['seatIndex'] != null) {
          final int? si = int.tryParse(m['seatIndex'].toString());
          if (si != null) seatIndex = si;
        }

        // start/end in "HH:MM" (try to parse minutes or "HH:MM"/"HH:MM AM/PM")
        String startStr = '-';
        if (m.containsKey('start') && m['start'] != null) {
          final int min = _parseToMinutes(m['start']);
          if (min >= 0) startStr = _showHHMM(min);
        }
        String endStr = '-';
        if (m.containsKey('end') && m['end'] != null) {
          final int min = _parseToMinutes(m['end']);
          if (min >= 0) endStr = _showHHMM(min);
        }

        // send to inbox (ONLY user)
        await NotificationService.sendRequestUpdateMails(
          bookingId: doc.id,
          userId: userId,
          seatIndex: seatIndex,
          start: startStr,
          end: endStr,
          facilityId: facilityId,
          bookingDate: _fmtDate(only), // "YYYY-MM-DD"
        );
      }
    } catch (_) {
      // be silent here; disable still goes through even if notification fails
    }
  }



  DateTime _toEndOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  // --- image helpers ---
  String _assetPath(String? name) {
    if (name == null || name.isEmpty) return '';
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
  Future<void> _pickImage() async {
    final FilePickerResult? res =
    await FilePicker.platform.pickFiles(type: FileType.image, withData: false);
    if (res == null || res.files.isEmpty) return;

    setState(() {
      _pickedImageName = res.files.first.name;
    });
  }

  Future<void> _pickStartTime() async {
    final TimeOfDay? t =
    await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 8, minute: 0));
    if (t == null) return;
    setState(() => _startTime = t);
  }

  Future<void> _pickEndTime() async {
    final TimeOfDay? t =
    await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 17, minute: 0));
    if (t == null) return;

    if (_startTime != null) {
      final int endMin = t.hour * 60 + t.minute;
      final int startMin = _startTime!.hour * 60 + _startTime!.minute;
      if (endMin <= startMin) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('End must be after start')));
        return;
      }
    }
    setState(() => _endTime = t);
  }

  Future<void> _pickInactiveRange() async {
    if (_isRangePickerOpen) return;
    _isRangePickerOpen = true;

    try {
      final DateTime now = DateTime.now();
      final DateTime first = DateTime(now.year, now.month, now.day);
      final DateTime last = DateTime(now.year + 2, 12, 31);

      DateTimeRange init;
      if (_inactiveRange != null) {
        DateTime s = _inactiveRange!.start.isBefore(first) ? first : _inactiveRange!.start;
        DateTime e = _inactiveRange!.end.isAfter(last) ? last : _inactiveRange!.end;
        if (e.isBefore(s)) e = s;
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

  Widget _emptyPlaceholder() {
    return SizedBox(
      height: 820.h,
      child: Center(
        child: Text(
          'Please pick an option',
          style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // ---------- data hydrate / reset ----------
  void _resetAddDefaults() {
    _formKey.currentState?.reset();

    _nameCtrl.clear();
    _locationCtrl.clear();
    _detailsCtrl.clear();
    _durationCtrl.text = '1';
    _inactiveReasonCtrl.clear();

    _slots = 1;
    _requiredCapacity = 1;
    _maxCapacity = 1;
    _requireApproval = false;
    _disableFacility = false;

    _startTime = null;
    _endTime = null;
    _customSlots = <Map<String, int>>[];

    _inactiveRange = null;

    _pickedImageName = null;
    _catId = null;
    _catName = '';
    _managerId = null;
    _managerName = '';

    _slotError = null;
  }

  void _hydrateFromSelected() {
    final Map<String, dynamic>? d = widget.selectedFacilityData;
    if (d == null || _view == 'add') return;

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

    if (d.containsKey('categoryId') && d['categoryId'] != null) {
      _catId = d['categoryId'].toString();
    } else {
      _catId = null;
    }

    _catName = '';
    if (d.containsKey('categoryName') && d['categoryName'] != null) {
      _catName = d['categoryName'].toString();
    }

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

    _requiredCapacity = 1;
    if (d.containsKey('requiredCapacity') && d['requiredCapacity'] != null) {
      final dynamic v = d['requiredCapacity'];
      if (v is int) {
        _requiredCapacity = v;
      } else {
        final int? p = int.tryParse(v.toString());
        if (p != null) _requiredCapacity = p;
      }
    }
    if (_requiredCapacity < 1) _requiredCapacity = 1;

    _maxCapacity = 1;
    if (d.containsKey('maxCapacity') && d['maxCapacity'] != null) {
      final dynamic v = d['maxCapacity'];
      if (v is int) {
        _maxCapacity = v;
      } else {
        final int? p = int.tryParse(v.toString());
        if (p != null) _maxCapacity = p;
      }
    }
    if (_maxCapacity < 1) _maxCapacity = 1;

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

    _startTime = startStr.isNotEmpty ? _parseHHMM(startStr) : null;
    _endTime = endStr.isNotEmpty ? _parseHHMM(endStr) : null;

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
      _customSlots.sort((a, b) {
        final int aStart = _safeParseInt(a['startMin'], 0);
        final int bStart = _safeParseInt(b['startMin'], 0);
        return aStart.compareTo(bStart);
      });
    }

    if (d.containsKey('managerId')) {
      _managerId = d['managerId']?.toString();
    } else {
      _managerId = null;
    }

    String managerName = '';
    if (d.containsKey('managerName') && d['managerName'] != null) {
      managerName = d['managerName'].toString();
    }
    _managerName = managerName;

    _requireApproval = (d['requireApproval'] == true);

    final Timestamp? fromTs =
    (d['inactiveFrom'] is Timestamp) ? d['inactiveFrom'] as Timestamp : null;
    final Timestamp? toTs =
    (d['inactiveTo'] is Timestamp) ? d['inactiveTo'] as Timestamp : null;

    _inactiveReasonCtrl.text = (d['inactiveReason'] ?? '').toString();
    if (fromTs != null && toTs != null) {
      _inactiveRange = DateTimeRange(start: fromTs.toDate(), end: toTs.toDate());
    } else {
      _inactiveRange = null;
    }

    bool dbActive = true;
    if (d.containsKey('active') && d['active'] == false) {
      dbActive = false;
    }

    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    final bool hasWindow = fromTs != null && toTs != null;
    final bool scheduledFuture = hasWindow && fromTs!.toDate().isAfter(today);
    final bool inWindowNow =
        hasWindow && !today.isBefore(fromTs!.toDate()) && !today.isAfter(toTs!.toDate());

    _disableFacility = (!dbActive) || scheduledFuture || inWindowNow;

    _pickedImageName = null;
  }

  // ---------- custom slots ----------
  Future<void> _onAddCustomSlot() async {
    int dur = 1;
    final int? p = int.tryParse(_durationCtrl.text.trim());
    if (p != null) dur = p;
    if (dur <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please set a valid booking duration')));
      _slotError = null;
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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Working hours not found in SystemInformation')));
      _slotError = null;
      _slotFieldKey.currentState?.validate();
      return;
    }
    final int sysStart = sys['start']!;
    final int sysEnd = sys['end']!;
    if (sMin < sysStart || eMin > sysEnd) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Slot must be within ${_showHHMM(sysStart)} – ${_showHHMM(sysEnd)}')),
      );
      _slotError = null;
      _slotFieldKey.currentState?.validate();
      return;
    }

    for (final m in _customSlots) {
      final int a = _safeParseInt(m['startMin'], 0);
      final int b = _safeParseInt(m['endMin'], 0);
      if (sMin < b && a < eMin) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Slot overlaps an existing one')));
        _slotError = null;
        _slotFieldKey.currentState?.validate();
        return;
      }
    }

    setState(() {
      _customSlots.add({'startMin': sMin, 'endMin': eMin});
      _customSlots.sort((x, y) {
        final int xs = _safeParseInt(x['startMin'], 0);
        final int ys = _safeParseInt(y['startMin'], 0);
        return xs.compareTo(ys);
      });
      _slotError = null;
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
  Future<bool> _facilityNameExists(String name, {String? ignoreId}) async {
    final QuerySnapshot<Map<String, dynamic>> qs = await FirebaseFirestore.instance
        .collection('Facilities')
        .where('name', isEqualTo: _clean(name))
        .where('deleted', isEqualTo: false)
        .limit(2)
        .get();

    for (final d in qs.docs) {
      if (ignoreId == null) return true;
      if (d.id != ignoreId) return true;
    }
    return false;
  }

  // ---------- saves ----------
  Future<void> _saveNew() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_pickedImageName == null || _pickedImageName!.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please choose an image filename')));
      return;
    }
    if (_catId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please select a category')));
      return;
    }
    if (_managerId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please select a manager')));
      return;
    }

    int dur = int.tryParse(_durationCtrl.text.trim()) ?? 0;
    if (dur <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Booking duration must be > 0')));
      return;
    }

    if (_customSlots.isEmpty) {
      setState(() => _slotError = 'Cannot be empty');
      _slotFieldKey.currentState?.validate();
      return;
    } else {
      setState(() => _slotError = null);
      _slotFieldKey.currentState?.validate();
    }

    final Map<String, int>? sys = await _getWorkingMinutes();
    if (sys == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Working hours not found in SystemInformation')));
      return;
    }
    final int step = dur * 60;
    int earliest = 999999;
    int latest = -1;
    for (final m in _customSlots) {
      final int s = _safeParseInt(m['startMin'], -1);
      final int e = _safeParseInt(m['endMin'], -1);
      if (s < 0 || e < 0) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Invalid slot data')));
        return;
      }
      if ((e - s) != step) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Every slot must equal the booking duration')));
        return;
      }
      final int sysStart = sys['start']!;
      final int sysEnd = sys['end']!;
      if (s < sysStart || e > sysEnd) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Slots must be within ${_showHHMM(sysStart)} – ${_showHHMM(sysEnd)}')),
        );
        return;
      }
      if (s < earliest) earliest = s;
      if (e > latest) latest = e;
    }

    if (_slots < 1) _slots = 1;
    if (_requiredCapacity < 1) _requiredCapacity = 1;
    if (_maxCapacity < 1) _maxCapacity = 1;
    if (_requiredCapacity > _maxCapacity) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Required capacity cannot be greater than max capacity')),
      );
      return;
    }

    final String name = _clean(_nameCtrl.text);
    if (await _facilityNameExists(name)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Facility "$name" already exists')));
      return;
    }

    try {
      final List<Map<String, dynamic>> slotsToSave = <Map<String, dynamic>>[];
      for (final m in _customSlots) {
        final int sMin = _safeParseInt(m['startMin'], 0);
        final int eMin = _safeParseInt(m['endMin'], 0);
        slotsToSave.add(<String, dynamic>{
          'start': _showHHMM(sMin),
          'end': _showHHMM(eMin),
          'startMin': sMin,
          'endMin': eMin,
        });
      }

      await FirebaseFirestore.instance.collection('Facilities').add(<String, dynamic>{
        'name': name,
        'imageName': _pickedImageName,
        'location': _locationCtrl.text.trim(),
        'categoryId': _catId,
        'categoryName': _catName, // keeping existing field if you still want it
        'details': _detailsCtrl.text.trim(),
        'availableSlots': _slots,
        'requiredCapacity': _requiredCapacity,
        'maxCapacity': _maxCapacity,
        'availableTime': <String, dynamic>{
          'start': _showHHMM(earliest),
          'end': _showHHMM(latest),
          'startMin': earliest,
          'endMin': latest,
        },
        'customTimeSlots': slotsToSave,
        'bookingDurationHours': dur,
        'managerId': _managerId,
        'managerName': _managerName, // keeping existing field if you still want it
        'requireApproval': _requireApproval,
        'enabled': true,
        'active': !_disableFacility,
        'inactiveReason': null,
        'inactiveFrom': null,
        'inactiveTo': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      widget.onFacilityUpdated(null, null);
      widget.onClose();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Facility added')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to add: $e')));
    }
  }

  Future<void> _saveEdit() async {
    if (widget.selectedFacilityId == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_catId == null || _managerId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please complete all fields')));
      return;
    }

    if (_customSlots.isEmpty) {
      setState(() => _slotError = 'Cannot be empty');
      _slotFieldKey.currentState?.validate();
      return;
    } else {
      setState(() => _slotError = null);
      _slotFieldKey.currentState?.validate();
    }

    int dur = int.tryParse(_durationCtrl.text.trim()) ?? 0;
    if (dur <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Booking duration must be > 0')));
      return;
    }

    final Map<String, int>? sys = await _getWorkingMinutes();
    if (sys == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Working hours not found in SystemInformation')));
      return;
    }
    final int step = dur * 60;
    int earliest = 999999;
    int latest = -1;
    for (final m in _customSlots) {
      final int s = _safeParseInt(m['startMin'], -1);
      final int e = _safeParseInt(m['endMin'], -1);
      if ((e - s) != step) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Every slot must be exactly equal to the booking duration')));
        return;
      }
      final int sysStart = sys['start']!;
      final int sysEnd = sys['end']!;
      if (s < sysStart || e > sysEnd) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Slots must be within ${_showHHMM(sysStart)} – ${_showHHMM(sysEnd)}')));
        return;
      }
      if (s < earliest) earliest = s;
      if (e > latest) latest = e;
    }

    final String name = _clean(_nameCtrl.text);
    if (await _facilityNameExists(name, ignoreId: widget.selectedFacilityId)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Facility "$name" already exists')));
      return;
    }

    String imageToSave = '';
    if (_pickedImageName != null) {
      imageToSave = _pickedImageName!;
    } else {
      if (widget.selectedFacilityData != null &&
          widget.selectedFacilityData!.containsKey('imageName')) {
        imageToSave = (widget.selectedFacilityData!['imageName'] ?? '').toString();
      } else {
        imageToSave = '';
      }
    }

    if (_slots < 1) _slots = 1;
    if (_requiredCapacity < 1) _requiredCapacity = 1;
    if (_maxCapacity < 1) _maxCapacity = 1;

    if (_requiredCapacity > _maxCapacity) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Required capacity cannot be greater than max capacity')),
      );
      return;
    }

    final List<Map<String, dynamic>> slotsToSave = <Map<String, dynamic>>[];
    for (final m in _customSlots) {
      final int sMin = _safeParseInt(m['startMin'], 0);
      final int eMin = _safeParseInt(m['endMin'], 0);
      slotsToSave.add(<String, dynamic>{
        'start': _showHHMM(sMin),
        'end': _showHHMM(eMin),
        'startMin': sMin,
        'endMin': eMin,
      });
    }

    final Map<String, dynamic> update = <String, dynamic>{
      'name': name,
      'imageName': imageToSave,
      'location': _locationCtrl.text.trim(),
      'categoryId': _catId,
      'categoryName': _catName, // optional legacy
      'details': _detailsCtrl.text.trim(),
      'availableSlots': _slots,
      'requiredCapacity': _requiredCapacity,
      'maxCapacity': _maxCapacity,
      'availableTime': <String, dynamic>{
        'start': _showHHMM(earliest),
        'end': _showHHMM(latest),
        'startMin': earliest,
        'endMin': latest,
      },
      'customTimeSlots': slotsToSave,
      'bookingDurationHours': int.tryParse(_durationCtrl.text.trim()) ?? 1,
      'managerId': _managerId,
      'managerName': _managerName, // optional legacy
      'requireApproval': _requireApproval,
    };

    if (_disableFacility) {
      final String reason = _inactiveReasonCtrl.text.trim();
      if (reason.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Reason required')));
        return;
      }
      if (_inactiveRange == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Please pick a date range')));
        return;
      }

      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);

      final DateTime startDay = DateTime(
        _inactiveRange!.start.year,
        _inactiveRange!.start.month,
        _inactiveRange!.start.day,
      );
      final DateTime endDay = DateTime(
        _inactiveRange!.end.year,
        _inactiveRange!.end.month,
        _inactiveRange!.end.day,
      );

      if (endDay.isBefore(startDay)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('End date cannot be before start date')));
        return;
      }




      final Timestamp? dbFromTs =
      (widget.selectedFacilityData?['inactiveFrom'] is Timestamp)
          ? widget.selectedFacilityData!['inactiveFrom'] as Timestamp
          : null;
      final Timestamp? dbToTs =
      (widget.selectedFacilityData?['inactiveTo'] is Timestamp)
          ? widget.selectedFacilityData!['inactiveTo'] as Timestamp
          : null;

      bool _sameDay(DateTime a, DateTime b) =>
          a.year == b.year && a.month == b.month && a.day == b.day;

      bool unchangedExistingRange = false;
      if (dbFromTs != null && dbToTs != null) {
        if (_sameDay(dbFromTs.toDate(), _inactiveRange!.start) &&
            _sameDay(dbToTs.toDate(), _inactiveRange!.end)) {
          unchangedExistingRange = true;
        }
      }

      if (startDay.isBefore(today) && !unchangedExistingRange) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Unavailable start date cannot be before today')));
        return;
      }

      final bool startsInFuture = startDay.isAfter(today);
      if (startsInFuture) {
        update['active'] = true;
      } else {
        update['active'] = false;
      }
      update['inactiveReason'] = reason;
      update['inactiveFrom'] = Timestamp.fromDate(startDay);
      update['inactiveTo'] = Timestamp.fromDate(_toEndOfDay(endDay));
    } else {
      update['active'] = true;
      update['inactiveReason'] = null;
      update['inactiveFrom'] = null;
      update['inactiveTo'] = null;
    }

    try {
      await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.selectedFacilityId)
          .update(update);

      if (_disableFacility && widget.selectedFacilityId != null && _inactiveRange != null) {
        final DateTime startDay = DateTime(
          _inactiveRange!.start.year, _inactiveRange!.start.month, _inactiveRange!.start.day,
        );
        final DateTime endDay = DateTime(
          _inactiveRange!.end.year, _inactiveRange!.end.month, _inactiveRange!.end.day,
        );
        await _notifyBookingsInDisabledRange(
          facilityId: widget.selectedFacilityId!,
          startDay: startDay,
          endDay: endDay,
        );
      }

      final Map<String, dynamic> newMap = <String, dynamic>{};
      final Map<String, dynamic> old =
      widget.selectedFacilityData == null ? <String, dynamic>{} : Map<String, dynamic>.from(widget.selectedFacilityData!);
      newMap.addAll(old);
      newMap.addAll(update);
      widget.onFacilityUpdated(widget.selectedFacilityId, newMap);

      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Facility updated')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to update: $e')));
    }
  }

  /// read bookingDate from a booking map in simple way
  /// supports Firestore Timestamp or "YYYY-MM-DD" string
  /// return DateTime? (null if cannot read)
  DateTime? _readBookingDate(Map<String, dynamic> m) {
    if (m.containsKey('bookingDate')) {
      final dynamic v = m['bookingDate'];

      // if Firestore Timestamp
      if (v is Timestamp) {
        return v.toDate();
      }

      // if "YYYY-MM-DD" string
      if (v is String) {
        final String s = v.trim();
        if (s.isNotEmpty) {
          try {
            final List<String> p = s.split('-');
            if (p.length == 3) {
              final int y = int.parse(p[0]);
              final int mo = int.parse(p[1]);
              final int d = int.parse(p[2]);
              return DateTime(y, mo, d);
            }
          } catch (_) {
            // ignore parsing error
          }
        }
      }
    }
    return null;
  }

  /// read an approval/status string in a very forgiving way
  /// we only allow "rejected" to pass; everything else blocks
  String _readApprovalLower(Map<String, dynamic> m) {
    String a = '';
    if (m.containsKey('approval') && m['approval'] != null) {
      a = m['approval'].toString();
    } else {
      if (m.containsKey('status') && m['status'] != null) {
        a = m['status'].toString();
      } else {
        a = '';
      }
    }
    return a.toLowerCase().trim();
  }

  /// check bookings for this facility within a date range (inclusive)
  /// return true if there is ANY booking that is NOT "rejected"
  /// return false if none found (safe to disable)
  Future<bool> _hasBlockingBookingsForDisable({
    required String facilityId,
    required DateTime startDay,
    required DateTime endDay,
  }) async {
    try {
      // get all bookings for this facility (simple, then filter by date)
      final QuerySnapshot<Map<String, dynamic>> qs = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('facilityId', isEqualTo: facilityId)
          .get();

      for (final doc in qs.docs) {
        final Map<String, dynamic> m = doc.data();

        // skip deleted if you use soft delete
        if (m.containsKey('deleted')) {
          if (m['deleted'] is bool) {
            if (m['deleted'] == true) {
              continue;
            }
          }
        }

        // read date
        final DateTime? bd = _readBookingDate(m);
        if (bd == null) {
          // no date -> skip
          continue;
        }

        // compare by day only
        final DateTime only = DateTime(bd.year, bd.month, bd.day);

        // outside the disable range -> skip
        if (only.isBefore(startDay)) {
          continue;
        } else {
          if (only.isAfter(endDay)) {
            continue;
          } else {
            // inside the disable range -> check approval
            final String approval = _readApprovalLower(m);
            final bool isRejected = approval == 'rejected';
            if (!isRejected) {
              // this blocks the disable
              return true;
            }
          }
        }
      }
    } catch (_) {
      // on read error we choose to be safe and block
      return true;
    }
    // no blocking bookings found
    return false;
  }


  Future<void> _softDelete() async {
    if (widget.selectedFacilityId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.selectedFacilityId)
          .update(<String, dynamic>{'deleted': true});

      widget.onFacilityUpdated(null, null);
      widget.onClose();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Facility deleted')));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

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
    return res ?? false;
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

  // NEW: read-only field that looks up a Category name by id
  Widget _roCategoryLive(String? categoryId) {
    return _ReadOnlyLookupField(
      label: 'Facility Category',
      future: () async {
        final id = categoryId?.trim() ?? '';
        if (id.isEmpty) return '—';
        final snap = await FirebaseFirestore.instance
            .collection('FacilitiesCategory')
            .doc(id)
            .get();
        final data = snap.data();
        final name = (data?['name'] as String?)?.trim() ?? '';
        return name.isEmpty ? '—' : name;
      }(),
    );
  }

  // NEW: read-only field that looks up a Manager/User name by id
  Widget _roManagerLive(String? managerId) {
    return _ReadOnlyLookupField(
      label: 'Assign Manager',
      future: () async {
        final id = managerId?.trim() ?? '';
        if (id.isEmpty) return '—';
        final snap = await FirebaseFirestore.instance
            .collection('UserInformation')
            .doc(id)
            .get();
        final data = snap.data();
        // prefer "name", then "username"
        final name = ((data?['name'] ?? data?['username']) as String?)?.trim() ?? '';
        return name.isEmpty ? '—' : name;
      }(),
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
    if (_view == 'view' && widget.selectedFacilityId == null) {
      return _emptyPlaceholder();
    }

    if (_view == 'add') {
      return _buildForm(isEdit: false);
    }
    if (_view == 'edit') {
      return _buildForm(isEdit: true);
    }

    // VIEW
    final Map<String, dynamic> d =
    widget.selectedFacilityData == null ? <String, dynamic>{} : Map<String, dynamic>.from(widget.selectedFacilityData!);

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

    String slots = '';
    if (d.containsKey('availableSlots') && d['availableSlots'] != null) {
      slots = d['availableSlots'].toString();
    }

    String reqCap = '';
    if (d.containsKey('requiredCapacity') && d['requiredCapacity'] != null) {
      reqCap = d['requiredCapacity'].toString();
    }
    String maxCap = '';
    if (d.containsKey('maxCapacity') && d['maxCapacity'] != null) {
      maxCap = d['maxCapacity'].toString();
    }

    String dur = '-';
    if (d.containsKey('bookingDurationHours') && d['bookingDurationHours'] != null) {
      dur = d['bookingDurationHours'].toString();
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

    // NEW: ids for live lookups
    final String? categoryId = (d['categoryId']?.toString());
    final String? managerId = (d['managerId']?.toString());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ro('Facility Name', name),
        _imagePreviewBox(img),
        // LIVE category / manager names (lookup by id)
        _roCategoryLive(categoryId),
        _ro('Facility Location', loc),
        _ro('Facility Details', det),
        _ro('Available Slots', slots),
        _ro('Required Capacity', reqCap),
        _ro('Max Capacity', maxCap),
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
            return labels.isEmpty ? '-' : labels.join(', ');
          }
          return '-';
        })()),
        _ro('Booking Duration', '$dur hour'),
        _roManagerLive(managerId),
        _ro('Require Approval', (d['requireApproval'] == true) ? 'Yes' : 'No'),
        _ro('Status', _statusLabel(dbActive)),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: widget.onClose,
              child: const Text('Close'),
            ),
            SizedBox(width: 8.w),
            ElevatedButton(
              onPressed: () => setState(() {
                _hydrateFromSelected();
                _view = 'edit';
              }),
              child: const Text('Edit'),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildForm({required bool isEdit}) {
    final List<Widget> disableExtras = <Widget>[];
    if (_disableFacility) {
      disableExtras.add(SizedBox(height: 6.h));
      disableExtras.add(
        TextFormField(
          controller: _inactiveReasonCtrl,
          validator: (v) {
            if (_disableFacility) {
              if (v == null || v.trim().isEmpty) return 'Reason required';
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

    String? previewName;
    if (_pickedImageName != null) {
      previewName = _pickedImageName;
    } else {
      if (isEdit && widget.selectedFacilityData != null) {
        previewName = (widget.selectedFacilityData!['imageName'] ?? '').toString();
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
              if (v == null || v.trim().isEmpty) return 'Required';
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
                bool isDel = false;
                if (m.containsKey('deleted') && m['deleted'] == true) {
                  isDel = true;
                }
                if (!isDel) docs.add(d);
              }

              String? value;
              bool found = docs.any((d) => d.id == _catId);
              value = found ? _catId : null;

              return SizedBox(
                width: 380.w,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: value,
                  items: docs.map((d) {
                    final Map<String, dynamic> m = d.data();
                    String nm = '';
                    if (m.containsKey('name') && m['name'] != null) nm = m['name'].toString();
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
              if (v == null || v.trim().isEmpty) return 'Required';
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
              if (v == null || v.trim().isEmpty) return 'Required';
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
                    int n = int.tryParse(v) ?? 1;
                    if (n < 1) n = 1;
                    _slots = n;
                  },
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Cannot be empty';
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

          // Required Capacity
          Text('Required Capacity', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          Row(
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _requiredCapacity = _requiredCapacity - 1;
                    if (_requiredCapacity < 1) _requiredCapacity = 1;
                  });
                },
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 60.w,
                child: TextFormField(
                  key: ValueKey<int>(_requiredCapacity),
                  initialValue: _requiredCapacity.toString(),
                  onChanged: (v) {
                    int n = int.tryParse(v) ?? 1;
                    if (n < 1) n = 1;
                    _requiredCapacity = n;
                  },
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Cannot be empty';
                    return null;
                  },
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _requiredCapacity = _requiredCapacity + 1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          SizedBox(height: 12.h),

          // Max Capacity
          Text('Max Capacity', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          Row(
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _maxCapacity = _maxCapacity - 1;
                    if (_maxCapacity < 1) _maxCapacity = 1;
                  });
                },
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 60.w,
                child: TextFormField(
                  key: ValueKey<int>(_maxCapacity),
                  initialValue: _maxCapacity.toString(),
                  onChanged: (v) {
                    int n = int.tryParse(v) ?? 1;
                    if (n < 1) n = 1;
                    _maxCapacity = n;
                  },
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Cannot be empty';
                    return null;
                  },
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _maxCapacity = _maxCapacity + 1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          SizedBox(height: 12.h),

          // Booking Duration
          Text('Booking Duration', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          Row(
            children: [
              IconButton(
                onPressed: () {
                  int val = int.tryParse(_durationCtrl.text.trim()) ?? 1;
                  if (val > 1) val = val - 1;
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
                    int val = int.tryParse(v ?? '') ?? 0;
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
                  int val = int.tryParse(_durationCtrl.text.trim()) ?? 1;
                  val = val + 1;
                  _durationCtrl.text = val.toString();
                  setState(() {});
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          SizedBox(height: 12.h),

          // custom booking slots
          Text('Custom Booking Time Slots',
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 8.h),

          FormField<bool>(
            key: _slotFieldKey,
            autovalidateMode: AutovalidateMode.always,
            validator: (_) => _slotError,
            builder: (field) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 1.0.sw,
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: _BoxPanel._fill,
                    borderRadius: BorderRadius.circular(12.r),
                    border:
                    Border.all(color: const Color(0xFF8620E2).withOpacity(.25), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 18.sp, color: const Color(0xFF5B1BC2)),
                          SizedBox(width: 6.w),
                          Text('Add custom slot(s)',
                              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          SizedBox(
                            height: 36.h,
                            child: OutlinedButton.icon(
                              onPressed: _onAddCustomSlot,
                              icon: const Icon(Icons.add),
                              label: const Text('Add time slot'),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                    color: const Color(0xFF5B1BC2).withOpacity(.7), width: 1.2),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10.r)),
                              ),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 10.h),

                      Text(
                        'Tip: Start time can be any minute, e.g. 07:30.',
                        style: TextStyle(
                          fontSize: 10.sp,
                          fontStyle: FontStyle.italic,
                          color: Colors.black.withOpacity(.7),
                        ),
                      ),

                      SizedBox(height: 10.h),

                      if (_customSlots.isEmpty)
                        Container(
                          width: 1.0.sw,
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          alignment: Alignment.center,
                          child: Text('No slots yet. Tap "Add time slot".',
                              style: TextStyle(fontSize: 12.sp, color: Colors.black)),
                        )
                      else
                        Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children: List.generate(_customSlots.length, (int i) {
                            final int s = _safeParseInt(_customSlots[i]['startMin'], 0);
                            final int e = _safeParseInt(_customSlots[i]['endMin'], 0);

                            return Container(
                              padding:
                              EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD9C9FF),
                                borderRadius: BorderRadius.circular(999.r),
                                border: Border.all(
                                    color: const Color(0xFF8620E2).withOpacity(.25), width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.access_time,
                                      size: 14.sp, color: Colors.black87),
                                  SizedBox(width: 6.w),
                                  Text(
                                    '${_showHHMM(s)} – ${_showHHMM(e)}',
                                    style: TextStyle(
                                        fontSize: 12.sp,
                                        color: Colors.black,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(width: 8.w),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _customSlots.removeAt(i);
                                        _slotError =
                                        _customSlots.isEmpty ? 'Cannot be empty' : null;
                                      });
                                      _slotFieldKey.currentState?.validate();
                                    },
                                    child: Padding(
                                      padding: EdgeInsets.all(4.w),
                                      child: Icon(Icons.close,
                                          size: 14.sp, color: Colors.black87),
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
                      if (_inactiveRange == null) {
                        _inactiveRange = DateTimeRange(start: today, end: today);
                      } else {
                        if (_inactiveRange!.end.isBefore(today)) {
                          _inactiveRange = DateTimeRange(start: today, end: today);
                        }
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
                TextButton(
                  onPressed: () => setState(() => _view = 'view'),
                  child: const Text('Cancel'),
                ),
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

/// Read-only lookup field with same visual style as `_ro(...)`.
class _ReadOnlyLookupField extends StatelessWidget {
  const _ReadOnlyLookupField({
    Key? key,
    required this.label,
    required this.future,
  }) : super(key: key);

  final String label;
  final Future<String> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: future,
      builder: (context, snap) {
        final String value = (snap.data ?? (snap.connectionState == ConnectionState.waiting ? 'Loading...' : '—'));
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
      },
    );
  }
}
