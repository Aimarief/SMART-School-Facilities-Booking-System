import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'web_top_bar.dart';
import 'package:smart_school_facilities_booking_system/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WebFacilities extends StatefulWidget {
  const WebFacilities({Key? key}) : super(key: key);

  @override
  State<WebFacilities> createState() => _WebFacilitiesState();
}

class _WebFacilitiesState extends State<WebFacilities> {
  final bool _use24HourFormat = true;


  final TextEditingController _facSearch = TextEditingController();

  String? _facId;
  Map<String, dynamic>? _facData;

  String _mode = 'view';
//---------------------------------------
// wswitch mode to add facility
//---------------------------------------
  void _openAddFacility() {
    setState(() {
      _mode = 'add';
      _facId = null;
      _facData = null;
    });
  }
//---------------------------------------
// switch mode to select facility view mode
//---------------------------------------
  void _selectFacility(String id, Map<String, dynamic> data) {
    setState(() {
      _facId = id;
      _facData = data;
      _mode = 'view';
    });
  }
//---------------------------------------
//  switch mode to view without date
//---------------------------------------
  void _closeRight() {
    setState(() {
      _facId = null;
      _facData = null;
      _mode = 'view';
    });
  }
//---------------------------------------
// switch mode after facility update and view that data
//---------------------------------------
  void _onFacilityUpdated(String? id, Map<String, dynamic>? updated) {
    setState(() {
      _facId = id;
      _facData = updated;
      _mode = 'view';
    });
  }

  @override
  void dispose() {
    _facSearch.dispose();
    super.dispose();
  }

//---------------------------------------
// Main build main design 1 that show left and right panel
//---------------------------------------

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
              constraints: BoxConstraints(minHeight: constraints.maxHeight), // stretch the box if zoom in, minimum height is fix, it can be taller but cannot be shorter
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 1684.w,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
//---------------------------------------
// display left list
//---------------------------------------
                          FacilityLeftList(
                            width: 460.w,
                            height: 965.h,
                            search: _facSearch,
                            onAddTap: _openAddFacility,
                            onSelect: _selectFacility,
                          ),
                          SizedBox(width: 24.w),
//---------------------------------------
// display right list
//---------------------------------------
                          FacilityRightPanel(
                            width: 1200.w,
                            height: 965.h,
                            selectedFacilityId: _facId,
                            selectedFacilityData: _facData,
                            initialView: _mode,
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
//---------------------------------------
// display the whole big box of the list
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
//---------------------------------------
// fill and out line colour
//---------------------------------------
  static const Color _fill = Color(0xFFEDDFFF);
  static const Color _outline = Color(0xFF8620E2);

  @override
  Widget build(BuildContext context) {
    final List<Widget> kids = <Widget>[
      //---------------------------------------
// display title
//---------------------------------------
      Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
      SizedBox(height: 8.h),
    ];
    if (header != null) {
      kids.add(header!);
      kids.add(SizedBox(height: 8.h));
    }
    //---------------------------------------
// display childe ( which is the
//---------------------------------------
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
//---------------------------------------
// search header
//---------------------------------------
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
 //---------------------------------------
// text field for search , on change will set state
//---------------------------------------
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
//---------------------------------------
// button when tap will switch to add facility mode
//---------------------------------------
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
//---------------------------------------
// display each facility at left list
//---------------------------------------

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
//---------------------------------------
// will change to view mode with facility data
//---------------------------------------
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
//---------------------------------------
// main build 2 left list
//---------------------------------------
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
    return FirebaseFirestore.instance
        .collection('Facilities')
        .orderBy('name').snapshots();
  }

  String _clean(String s) => s.trim();
//---------------------------------------
// main design 2 box panel
//---------------------------------------

  @override
  Widget build(BuildContext context) {
    //---------------------------------------
// call the box panel to show teh whole container size and desing
//---------------------------------------
    return _BoxPanel(
      width: widget.width,
      height: widget.height,
      title: 'Facility',
      header: _SearchHeader(
        controller: widget.search,
        onChanged: (_) => setState(() {}),
        onAddTap: widget.onAddTap,
      ),
      //---------------------------------------
// get the facility stream
//---------------------------------------
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
//---------------------------------------
// filter the facility base on teh seach controller
//---------------------------------------
          final String q = _clean(widget.search.text).toLowerCase();
          final List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

          for (final d in docs) {
            final Map<String, dynamic> m = d.data();
//---------------------------------------
// ingnore deleted facility
//---------------------------------------
            bool del = false;
            if (m.containsKey('deleted')) {
              if (m['deleted'] == true) {
                del = true;
              }
            }
//---------------------------------------
// if contain the name same as the controller
//---------------------------------------
            String name = '';
            if (m.containsKey('name')) {
                name = m['name'];
            }

            bool matches = true;
            if (q.isNotEmpty) {
              final String lower = name.toLowerCase();
              if (!lower.contains(q)) { // if lower which is the facility name contain key word in the search controller
                matches = false;
              }
            }
//---------------------------------------
// add into the filter list
//---------------------------------------
            if (!del) {
              if (matches) {
                filtered.add(d); //if match and no deleted , will add in the filtered list
              }
            }
          }
//---------------------------------------
// if filter list is empty
//---------------------------------------
          if (filtered.isEmpty) {
            return Center(child: Text('empty', style: TextStyle(fontSize: 14.sp)));
          }
//---------------------------------------
// use list widget to display each of the facility in the filter list
//---------------------------------------

          final List<Widget> children = <Widget>[];
          for (int i = 0; i < filtered.length; i++) {
            final doc = filtered[i];
            final Map<String, dynamic> data = doc.data();

            String name = '';
                name = data['name'].toString();
//---------------------------------------
// add into the card
//---------------------------------------
            children.add(
              _ListTileCard(
                label: name,
                onTap: () => widget.onSelect(doc.id, data),
              ),
            );
            if (i < filtered.length - 1) {
              children.add(SizedBox(height: 8.h));
            }
          }
//---------------------------------------
// then display
//---------------------------------------

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
// main build 3 right panel
//---------------------------------------

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
//---------------------------------------
// all teh controllers
//---------------------------------------
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>(); // use to check and validate all form
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _locationCtrl = TextEditingController();
  final TextEditingController _detailsCtrl = TextEditingController();
  final TextEditingController _durationCtrl = TextEditingController(text: '1');
  final TextEditingController _inactiveReasonCtrl = TextEditingController();
  final GlobalKey<FormFieldState> _slotFieldKey = GlobalKey<FormFieldState>(); //only for slot because its not text field, it have to use different way to validate

  int _slots = 1;
  int _requiredCapacity = 1;
  int _maxCapacity = 1;

  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  List<Map<String, int>> _customSlots = <Map<String, int>>[];
  bool _disableFacility = false;
  bool _isRangePickerOpen = false;
  DateTimeRange? _inactiveRange;

  String? _slotError;
  String? _pickedImageName;
  String? _catId;
  String _catName = '';
  String? _managerId;
  String _managerName = '';

//---------------------------------------
// view mode
//---------------------------------------
  String _view = 'view';

  static const String _assetDir = 'asset/image';
//---------------------------------------
// inti state do this first
//---------------------------------------

  @override
  void initState() {
    super.initState();
//---------------------------------------
// look what is the mode
//---------------------------------------
    _view = widget.initialView;
    //---------------------------------------
// get all the information of the facility
//---------------------------------------
    _hydrateFromSelected();
    //---------------------------------------
// iff is add mode set everything to default value
//---------------------------------------
    if (_view == 'add') {
      _resetAddDefaults();
    }
  }
  //---------------------------------------
//  didUpdateWidget always calls _hydrateFromSelected() and _resetAddDefaults() whenever the parent rebuilds, because init state only run once
//---------------------------------------

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

//---------------------------------------
// trim the string
//---------------------------------------

  String _clean(String s) => s.trim();

  //---------------------------------------
// format date to date format
//---------------------------------------
  String _fmtDate(DateTime d) {
    final String y = d.year.toString();
    final String mo = d.month.toString().padLeft(2, '0');
    final String da = d.day.toString().padLeft(2, '0');
    return '$y-$mo-$da';
  }

//---------------------------------------
// parse the time to int
//---------------------------------------
  int _safeParseInt(Object? v, int fallback) {
    if (v is int) return v;
    if (v == null) return fallback;
    final int? p = int.tryParse(v.toString());
    return p ?? fallback;
  }

//---------------------------------------
// convert minute back to hour and minute
//---------------------------------------
  String _showHHMM(int m) {
    final String h = (m ~/ 60).toString().padLeft(2, '0');
    final String mm = (m % 60).toString().padLeft(2, '0');
    return '$h:$mm';
  }

//---------------------------------------
// convert hh mm time to minute
//---------------------------------------
  int _parseToMinutes(String v) {
    final String s = v.trim();

    // 2) split into hour and minute
    final List<String> p = s.split(':');
    if (p.length != 2) return -1;

    // 3) parse numbers safely (no exceptions)
    final int? h = int.tryParse(p[0]);
    final int? m = int.tryParse(p[1]);
    if (h == null || m == null) return -1;

    // 4) validate ranges
    if (h < 0 || h > 23) return -1;
    if (m < 0 || m > 59) return -1;

    // 5) convert to minutes
    return h * 60 + m;
  }

//---------------------------------------
// get the working hour in System information
//---------------------------------------
  Future<Map<String, int>?> _getWorkingMinutes() async {
    try {
      final col = FirebaseFirestore.instance.collection('SystemInformation');

      DocumentSnapshot<Map<String, dynamic>> doc = await col
          .doc('Setting')
          .get();


      final data = doc.data();
      if (data == null) return null;
//---------------------------------------
// get the start adn end
//---------------------------------------
      final start = _parseToMinutes(data['start']);
      final end = _parseToMinutes(data['end']);
      if (start < 0 || end < 0) return null;

      return {'start': start, 'end': end};
    } catch (_) {
      return null;
    }
  }

//---------------------------------------
// notify user the booking need to be update
//---------------------------------------
  Future<void> _notifyBookingsInDisabledRange({
    required String facilityId,
    required DateTime startDay,
    required DateTime endDay,
  }) async {
    try {
      //---------------------------------------
// get the booking wheere it belong to teh facility id
//---------------------------------------
      final QuerySnapshot<Map<String, dynamic>> qs = await FirebaseFirestore
          .instance
          .collection('Bookings')
          .where('facilityId', isEqualTo: facilityId)
          .get();

      for (final doc in qs.docs) {
        final Map<String, dynamic> m = doc.data();

//---------------------------------------
// ignore ddeleted facility
//---------------------------------------
        if (m.containsKey('deleted')) {
          if (m['deleted'] is bool) {
            if (m['deleted'] == true) {
              continue;
            }
          }
        }
//---------------------------------------
// ignore ended status
//---------------------------------------
        String statusStr = '';
        if (m.containsKey('status') && m['status'] != null) {
          statusStr = m['status'].toString().toLowerCase().trim();
        }
        if (statusStr == 'ended') {
          continue;
        }

//---------------------------------------
// get the booking date
//---------------------------------------

        final DateTime? bd = _readBookingDate(m);
        if (bd == null) continue;

//---------------------------------------
// if its before start and after end day then reject
//---------------------------------------
        final DateTime only = DateTime(bd.year, bd.month, bd.day);
        if (only.isBefore(startDay)) continue;
        if (only.isAfter(endDay)) continue;

//---------------------------------------
// ingnore rejected approval
//---------------------------------------
        final String approval = _readApprovalLower(m);
        if (approval == 'rejected') continue;

//---------------------------------------
// get the user id
//---------------------------------------
        String userId = '';
        if (m.containsKey('userId') && m['userId'] != null) {
          userId = m['userId'].toString().trim();
        }
        if (userId.isEmpty) continue; // nothing to notify

//---------------------------------------
// get the seat index
//---------------------------------------
        int seatIndex = 0;
        if (m.containsKey('seatIndex') && m['seatIndex'] != null) {
          final int? si = int.tryParse(m['seatIndex'].toString());
          if (si != null) seatIndex = si;
        }

//---------------------------------------
// get start time and end time
//---------------------------------------
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
//---------------------------------------
// send to user inbox
//---------------------------------------
        await NotificationService.sendRequestUpdateMails(
          bookingId: doc.id,
          userId: userId,
          seatIndex: seatIndex,
          start: startStr,
          end: endStr,
          facilityId: facilityId,
          bookingDate: _fmtDate(only),
        );
      }
    } catch (_) {
    }
  }

//---------------------------------------
// set end day at the last second of the day
//---------------------------------------
  DateTime _toEndOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

//---------------------------------------
// get asset image
//---------------------------------------

  String _assetPath(String? name) {
    if (name == null || name.isEmpty) return '';
    return '$_assetDir/$name';
  }
//---------------------------------------
// will place image, if no image write no image
//---------------------------------------
  Widget _assetImageOrLabel(String? name) {
    final String path = _assetPath(name);
    if (path.isEmpty) {
      return const Center(child: Text('No image'));
    }
    return Image.asset(
      path,
      fit: BoxFit.cover,
      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
        if (name == null || name.isEmpty) {
          return const Center(child: Text('No image'));
        } else {
          return Center(child: Text(name));
        }
      },
    );
  }

//---------------------------------------
// filepicker alows to open file and pick image
//---------------------------------------
  Future<void> _pickImage() async {
    final FilePickerResult? res =
    await FilePicker.platform.pickFiles(type: FileType.image, withData: false);
    if (res == null || res.files.isEmpty) return;

    setState(() {
      _pickedImageName = res.files.first.name;
    });
  }

//---------------------------------------
// allows user to pick inactive range
//---------------------------------------
  Future<void> _pickInactiveRange() async {
    if (_isRangePickerOpen) return;
    _isRangePickerOpen = true;

    try {
      final DateTime now = DateTime.now();
      final DateTime first = DateTime(now.year, now.month, now.day);
//---------------------------------------
// limit to 2 years
//---------------------------------------
      final DateTime last = DateTime(now.year + 2, 12, 31); // 2 year

      DateTimeRange init;
      //check if previously choose is before first then today willl be come first
      if (_inactiveRange != null) {
        DateTime s = _inactiveRange!.start.isBefore(first)
            ? first
            : _inactiveRange!.start;
        DateTime e = _inactiveRange!.end.isAfter(last) ? last : _inactiveRange!
            .end;
//---------------------------------------
// validation check if end is not before start , end = to start
//---------------------------------------
        if (e.isBefore(s))
          e = s;
        init = DateTimeRange(start: s, end: e);
      } else {
        init = DateTimeRange(start: first, end: first);
      }
//---------------------------------------
// show teh date range picker
//---------------------------------------
      final DateTimeRange? picked = await showDateRangePicker(
        context: context,
        firstDate: first, // first day that can be pick
        lastDate: last, // last day that can be pick
        initialDateRange: init, // time range rule
      );
//---------------------------------------
// set state when inactive range is picked
//---------------------------------------
      if (picked != null) {
        setState(() => _inactiveRange = picked);
      }
    } finally {
      _isRangePickerOpen = false;
    }
  }

//---------------------------------------
// If no facility is pick then show this
//---------------------------------------
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

//---------------------------------------
// when add is press, set all to default or empty
//---------------------------------------
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
//---------------------------------------
// get all the facility information
//---------------------------------------

  void _hydrateFromSelected() {
    final Map<String, dynamic>? d = widget.selectedFacilityData;
    if (d == null || _view == 'add') return;

    //---------------------------------------
// set facility name
//---------------------------------------

    String nm = '';
    if (d.containsKey('name')) {
      nm = d['name'];
    }
    _nameCtrl.text = nm;

    //---------------------------------------
// set facility location
//---------------------------------------

    String loc = '';
    if (d.containsKey('location') && d['location'] != null) {
      loc = d['location'].toString();
    }
    _locationCtrl.text = loc;

    //---------------------------------------
// set category id
//---------------------------------------
    if (d.containsKey('categoryId') && d['categoryId'] != null) {
      _catId = d['categoryId'].toString();
    } else {
      _catId = null;
    }
//---------------------------------------
// set category name
//---------------------------------------
    _catName = '';
    if (d.containsKey('categoryName') && d['categoryName'] != null) {
      _catName = d['categoryName'].toString();
    }
//---------------------------------------
// set facility details
//---------------------------------------
    String det = '';
    if (d.containsKey('details') && d['details'] != null) {
      det = d['details'].toString();
    }
    _detailsCtrl.text = det;

    //---------------------------------------
// set the booking duration
//---------------------------------------

    int dur = 1;
    if (d.containsKey('bookingDurationHours') &&
        d['bookingDurationHours'] != null) {
      dur = d['bookingDurationHours'] as int;
    }
    _durationCtrl.text = dur.toString();
//---------------------------------------
// set the slots
//---------------------------------------
    _slots = 1;
    if (d.containsKey('availableSlots') && d['availableSlots'] != null) {
      _slots = d['availableSlots'];
    }
    if (_slots < 1) _slots = 1;
//---------------------------------------
// set required capacity
//---------------------------------------
    _requiredCapacity = 1;
    if (d.containsKey('requiredCapacity') && d['requiredCapacity'] != null) {
      _requiredCapacity = d['requiredCapacity'];
    }
    if (_requiredCapacity < 1) _requiredCapacity = 1;

    _maxCapacity = 1;
    if (d.containsKey('maxCapacity') && d['maxCapacity'] != null) {
      _maxCapacity = d['maxCapacity'];
    }
    if (_maxCapacity < 1) _maxCapacity = 1;
//---------------------------------------
// set available time , start and end time
//---------------------------------------

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

//---------------------------------------
// this part will convert time to string
//---------------------------------------
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

//---------------------------------------
// this part will add the time slot into customslot list
//---------------------------------------
    _customSlots = <Map<String, int>>[];
    if (d.containsKey('customTimeSlots') && d['customTimeSlots'] is List) {
      final List raw = d['customTimeSlots'] as List;
      for (final s in raw) {
        if (s is Map) {
          final int? sMin = int.tryParse('${s['startMin']}');
          final int? eMin = int.tryParse('${s['endMin']}');
          if (sMin != null && eMin != null && eMin > sMin) {
//------------------------------------- --
//add each of custom time slot into the list
//---------------------------------------
            _customSlots.add(<String, int>{'startMin': sMin, 'endMin': eMin});
          }
        }
      }
//---------------------------------------
// sort the time ealiest first
//---------------------------------------
      _customSlots.sort((a, b) {
        final int aStart = _safeParseInt(a['startMin'], 0);
        final int bStart = _safeParseInt(b['startMin'], 0);
        return aStart.compareTo(bStart);
      });
    }
//---------------------------------------
// set manager id
//---------------------------------------
    if (d.containsKey('managerId')) {
      _managerId = d['managerId']?.toString();
    } else {
      _managerId = null;
    }
//---------------------------------------
// set manager name
//---------------------------------------

    String managerName = '';
    if (d.containsKey('managerName') && d['managerName'] != null) {
      managerName = d['managerName'].toString();
    }
    _managerName = managerName;

//---------------------------------------
// check if the time stamp exist as null or timestamp, they may be null
//---------------------------------------
    final Timestamp? fromTs =
    (d['inactiveFrom'] is Timestamp) ? d['inactiveFrom'] as Timestamp : null;
    final Timestamp? toTs =
    (d['inactiveTo'] is Timestamp) ? d['inactiveTo'] as Timestamp : null;

    _inactiveReasonCtrl.text = (d['inactiveReason'] ?? '').toString();
    if (fromTs != null && toTs != null) {
      _inactiveRange =
          DateTimeRange(start: fromTs.toDate(), end: toTs.toDate());
    } else {
      _inactiveRange = null;
    }
//---------------------------------------
// check is active or not
//---------------------------------------

    bool dbActive = true;
    if (d.containsKey('active') && d['active'] == false) {
      dbActive = false;
    }
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
//---------------------------------------
// if have inactive range
//---------------------------------------
    final bool hasWindow = fromTs != null && toTs != null;
//---------------------------------------
// check if inactive start time after today
//---------------------------------------
    final bool scheduledFuture = hasWindow && fromTs.toDate().isAfter(today);
//---------------------------------------
// check if today is in the schedule (check if today is after start and today is before end )
//---------------------------------------
    final bool inWindowNow =
        hasWindow && !today.isBefore(fromTs.toDate()) && !today.isAfter(toTs.toDate());
//---------------------------------------
// true if it wither not active or have future schedule or in the range of inactive day
//---------------------------------------
    _disableFacility = (!dbActive) || scheduledFuture || inWindowNow;

    _pickedImageName = null;

    final String? id = widget.selectedFacilityId;
    if (id != null) {
      //this part will check the unaivailable facility, if pass already, then it will be turned to active (like housekeeping method)
      _autoClearExpiredInactive(id, d);
    }
  }

//---------------------------------------
// while adding the time slot
//---------------------------------------
  Future<void> _onAddCustomSlot() async {
    int dur = 1;
    final int? p = int.tryParse(_durationCtrl.text.trim());
    if (p != null)
      dur = p;
    if (dur <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
          const SnackBar(content: Text('Please set a valid booking duration')));
      _slotError = null;
      _slotFieldKey.currentState?.validate();
      return;
    }
//---------------------------------------
// show time picker
//---------------------------------------
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: 'Pick slot START time',
    );
    if (picked == null) return;

//---------------------------------------
// convert the picked time to minute
//---------------------------------------
    final int sMin = picked.hour * 60 + picked.minute;
    final int eMin = sMin + (dur * 60);

    //---------------------------------------
// get working minutes
//---------------------------------------

    final Map<String, int>? sys = await _getWorkingMinutes();
    if (sys == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Working hours not found in SystemInformation')));
      _slotError = null;
      _slotFieldKey.currentState?.validate();
      return;
    }
    //---------------------------------------
// if the picked time is out of system working hour
//---------------------------------------
    final int sysStart = sys['start']!;
    final int sysEnd = sys['end']!;
    if (sMin < sysStart || eMin > sysEnd) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            'Slot must be within ${_showHHMM(sysStart)} – ${_showHHMM(sysEnd)}')),
      );
      _slotError = null;
      _slotFieldKey.currentState?.validate();
      return;
    }
//---------------------------------------
// check if the new time slot is within the already exist time slot if yes show slots overlap
//---------------------------------------
    for (final m in _customSlots) {
      final int a = _safeParseInt(m['startMin'], 0);
      final int b = _safeParseInt(m['endMin'], 0);
      if (sMin < b && a < eMin) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
            const SnackBar(content: Text('Slot overlaps an existing one')));
        _slotError = null;
        _slotFieldKey.currentState?.validate();
        return;
      }
    }
//---------------------------------------
//or else add to custom slots and sort them by start minute
//---------------------------------------
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

//---------------------------------------
// call category stream
//---------------------------------------

  Stream<QuerySnapshot<Map<String, dynamic>>> _catsStream() {
    return FirebaseFirestore.instance
        .collection('FacilitiesCategory')
        .orderBy('name')
        .snapshots();
  }

//---------------------------------------
// call manager stream
//---------------------------------------

  Stream<QuerySnapshot<Map<String, dynamic>>> _managersStream() {
    return FirebaseFirestore.instance
        .collection('UserInformation')
        .where('role', isEqualTo: 'Manager')
        .where('deleted', isEqualTo: false) // only active managers
        .snapshots();
  }


//---------------------------------------
// check if name is exist, ingnore it self
//---------------------------------------

  Future<bool> _facilityNameExists(String name, {String? ignoreId}) async {
    final QuerySnapshot<Map<String, dynamic>> qs = await FirebaseFirestore
        .instance
        .collection('Facilities')
        .where('name', isEqualTo: _clean(name))
        .where('deleted', isEqualTo: false)
        .limit(2)
        .get();
//---------------------------------------
// if i have item and wither ingnore id is null or its not equal to ingnore id then , thsi name already exist
//---------------------------------------

    for (final d in qs.docs) {
      if (ignoreId == null) return true;
      if (d.id != ignoreId) return true;
    }
    return false;
  }

//---------------------------------------
// when new facility is going to be save
//---------------------------------------
  Future<void> _saveNew() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
//---------------------------------------
// validation
//---------------------------------------
    if (_pickedImageName == null || _pickedImageName!.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
          const SnackBar(content: Text('Please choose an image filename')));
      return;
    }
    if (_catId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
          const SnackBar(content: Text('Please select a category')));
      return;
    }
    if (_managerId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
          const SnackBar(content: Text('Please select a manager')));
      return;
    }

    int dur = int.tryParse(_durationCtrl.text.trim()) ?? 0;
    if (dur <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
          const SnackBar(content: Text('Booking duration must be > 0')));
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

//---------------------------------------
// get the working time from database in SystemInformation
//---------------------------------------
    final Map<String, int>? sys = await _getWorkingMinutes();
    if (sys == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Working hours not found in SystemInformation')));
      return;
    }
    //---------------------------------------
// check if the time slot is over the duration
//---------------------------------------
    final int durationPerSlot = dur * 60;
    int earliest = 999999;
    int latest = -1;
    for (final m in _customSlots) {
      final int s = _safeParseInt(m['startMin'], -1);
      final int e = _safeParseInt(m['endMin'], -1);

      final int sysStart = sys['start']!;
      final int sysEnd = sys['end']!;
      if (s < sysStart || e > sysEnd) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              'Slots must be within ${_showHHMM(sysStart)} – ${_showHHMM(
                  sysEnd)}')),
        );
        return;
      }

      if ((e - s) != durationPerSlot) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
                'Each slot must exactly match booking duration of $dur hour(s)')));
        return;
      }
//---------------------------------------
// get ealiest and lastes time range to dsiplay availablble time
//---------------------------------------

      if (s < earliest)
        earliest = s;
      if (e > latest)
        latest = e;
    }

//---------------------------------------
// when required capacity more than max
//---------------------------------------

    if (_requiredCapacity > _maxCapacity) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
            'Required capacity cannot be greater than max capacity')),
      );
      return;
    }
//---------------------------------------
// check if there is existing facility name
//---------------------------------------

    final String name = _clean(_nameCtrl.text);
    if (await _facilityNameExists(name)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
          SnackBar(content: Text('Facility "$name" already exists')));
      return;
    }
//---------------------------------------
// store the custom time slot
//---------------------------------------

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
//---------------------------------------
// add into new facilities database
//---------------------------------------
      await FirebaseFirestore.instance.collection('Facilities').add(
          <String, dynamic>{
            'name': name,
            'imageName': _pickedImageName,
            'location': _locationCtrl.text.trim(),
            'categoryId': _catId,
            'deleted': false,
            'categoryName': _catName,
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
            'managerName': _managerName,
            'requireApproval': true,
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
//---------------------------------------
// housekeeping to check if reach time then set inactive to null and active to true
//---------------------------------------

  Future<void> _autoClearExpiredInactive(String docId, Map<String, dynamic> d) async {
    try {
      final toRaw = d['inactiveTo'];
      if (toRaw is! Timestamp) return;
//---------------------------------------
// get today date and teh inactive to end date
//---------------------------------------
      final DateTime now = DateTime.now();
      final DateTime end = toRaw.toDate();

//---------------------------------------
// if it is before today then update them to null and active = true
//---------------------------------------
      if (end.isBefore(now)) {
        await FirebaseFirestore.instance
            .collection('Facilities')
            .doc(docId)
            .update({
          'active': true,
          'inactiveFrom': null,
          'inactiveTo': null,
          'inactiveReason': null,
        });
      }
    } catch (_) {
    }
  }
//---------------------------------------
// for saving edit
//---------------------------------------

  Future<void> _saveEdit() async {
    if (widget.selectedFacilityId == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
//---------------------------------------
// validation
//---------------------------------------
    if (_catId == null || _managerId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
          const SnackBar(content: Text('Please complete all fields')));
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
          .showSnackBar(
          const SnackBar(content: Text('Booking duration must be > 0')));
      return;
    }
//---------------------------------------
// get the working minute from database
//---------------------------------------
    final Map<String, int>? sys = await _getWorkingMinutes();
    if (sys == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Working hours not found in SystemInformation')));
      return;
    }
    final int durationPerSlot = dur * 60;
    int earliest = 999999;
    int latest = -1;
    for (final m in _customSlots) {
      //convert into int
      final int s = _safeParseInt(m['startMin'], -1);
      final int e = _safeParseInt(m['endMin'], -1);
      final int sysStart = sys['start']!;
      final int sysEnd = sys['end']!;
      //---------------------------------------
// make sure slot is within the system time
//---------------------------------------
      if (s < sysStart || e > sysEnd) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Slots must be within ${_showHHMM(sysStart)} – ${_showHHMM(
                    sysEnd)}')));
        return;
      }

      if ((e - s) != durationPerSlot) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(
                'Each slot must exactly match booking duration of $dur hour(s)')));
        return;
      }
      //---------------------------------------
// get earliest and the latest
//---------------------------------------
      if (s < earliest) earliest = s;
      if (e > latest) latest = e;
    }

    //---------------------------------------
// check facility name exist
//---------------------------------------
    final String name = _clean(_nameCtrl.text);
    if (await _facilityNameExists(name, ignoreId: widget.selectedFacilityId)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
          SnackBar(content: Text('Facility "$name" already exists')));
      return;
    }

    String imageToSave = '';
    if (_pickedImageName != null) {
      imageToSave = _pickedImageName!;
    } else {
      if (widget.selectedFacilityData != null &&
          widget.selectedFacilityData!.containsKey('imageName')) {
        imageToSave =
            (widget.selectedFacilityData!['imageName'] ?? '').toString();
      } else {
        imageToSave = '';
      }
    }
//---------------------------------------
// check required capacity make sure less thatn max capacity
//---------------------------------------
    if (_requiredCapacity > _maxCapacity) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
            'Required capacity cannot be greater than max capacity')),
      );
      return;
    }
//---------------------------------------
// slot that will be save in databse
//---------------------------------------
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
//---------------------------------------
// info that will be update in database
//---------------------------------------

    final Map<String, dynamic> update = <String, dynamic>{
      'name': name,
      'imageName': imageToSave,
      'location': _locationCtrl.text.trim(),
      'categoryId': _catId,
      'categoryName': _catName,
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
      'managerName': _managerName,
      'requireApproval': true,

    };

//---------------------------------------
// if the facility have disble range
//---------------------------------------

    if (_disableFacility) {
//---------------------------------------
// validation
//---------------------------------------

      final String reason = _inactiveReasonCtrl.text.trim();
      if (reason.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Reason required')));
        return;
      }
      if (_inactiveRange == null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
            const SnackBar(content: Text('Please pick a date range')));
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
//---------------------------------------
// make sure end date cannot before the start date
//---------------------------------------

      if (endDay.isBefore(startDay)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(
            content: Text('End date cannot be before start date')));
        return;
      }

//---------------------------------------
// get the inactive range
//---------------------------------------

      final dynamic inactiveF = widget.selectedFacilityData?['inactiveFrom'];
      final dynamic inactiveT   = widget.selectedFacilityData?['inactiveTo'];

      final Timestamp? dbFromTs = inactiveF is Timestamp ? inactiveF : null;
      final Timestamp? dbToTs   = inactiveT is Timestamp ? inactiveT : null;


//---------------------------------------
// is same day?
//---------------------------------------
      bool _sameDay(DateTime a, DateTime b) =>
          a.year == b.year && a.month == b.month && a.day == b.day;

      //---------------------------------------
// check if its the same in databse (this check is important and may heppend when already set yesteday and to day still not end yet,
// if u dint set below fucntion , u cant confirm the edit)
//---------------------------------------
      bool unchangedExistingRange = false;
      if (dbFromTs != null && dbToTs != null) {
        if (_sameDay(dbFromTs.toDate(), _inactiveRange!.start) && _sameDay(dbToTs.toDate(), _inactiveRange!.end)) {
          unchangedExistingRange = true;
        }
      }
//---------------------------------------
// make sure start cannot be before today
//---------------------------------------

      if (startDay.isBefore(today) && !unchangedExistingRange) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Unavailable start date cannot be before today')));
        return;
      }
//---------------------------------------
// update database
//---------------------------------------

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

      //---------------------------------------
// get the inactive range if they exist to send email for update
//---------------------------------------

      if (_disableFacility && widget.selectedFacilityId != null && _inactiveRange != null) {
        final DateTime startDay = DateTime(
          _inactiveRange!.start.year, _inactiveRange!.start.month, _inactiveRange!.start.day,
        );
        final DateTime endDay = DateTime(
          _inactiveRange!.end.year, _inactiveRange!.end.month, _inactiveRange!.end.day,
        );
        //---------------------------------------
// this part will send teh email if tehre is facility within the day
//---------------------------------------
        await _notifyBookingsInDisabledRange(
          facilityId: widget.selectedFacilityId!,
          startDay: startDay,
          endDay: endDay,
        );
      }

//---------------------------------------
// It creates a new map by copying the old facility data and then overlaying the updated fields,
// and finally calls the parent callback with the facility ID and this merged result.
//---------------------------------------
      final Map<String, dynamic> newMap = <String, dynamic>{};
      final Map<String, dynamic> old = widget.selectedFacilityData == null ? <String, dynamic>{} :
      Map<String, dynamic>.from(widget.selectedFacilityData!);
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

//---------------------------------------
// read the booking date from firestore
//---------------------------------------
  DateTime? _readBookingDate(Map<String, dynamic> m) {
    if (m.containsKey('bookingDate')) {
      final dynamic v = m['bookingDate'];

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
          }
        }
      }
    }
    return null;
  }

//---------------------------------------
// get approval and status
//---------------------------------------

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

//---------------------------------------
// whend delete facility do soft delete
//---------------------------------------

  Future<void> _softDelete() async {
    if (widget.selectedFacilityId == null) return;
    try {
//---------------------------------------
// update database deleted = true
//---------------------------------------
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
//---------------------------------------
// delete pop up
//---------------------------------------

  Future<bool> _confirmDelete() async {
    final bool? res = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // don't allow tap-outside to close
      builder: (_) =>
          AlertDialog(
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.zero),
            title: Text(
              'Delete facility?',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
            ),
            content: Text(
              'Are you sure you want to delete this facility?',
              style: TextStyle(fontSize: 14.sp),
            ),
            //---------------------------------------
// cancel return false
//---------------------------------------
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
              ),
//---------------------------------------
// confirm return true
//---------------------------------------
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF0707), // red confirm
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero),
                ),
                child: Text('Confirm', style: TextStyle(
                    fontSize: 14.sp, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
    );
    return res ?? false;
  }

//---------------------------------------
// show ro which is in view mode field
//---------------------------------------
  Widget _ro(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
        SizedBox(height: 6.h),
        TextFormField(
          key: ValueKey<String>('$label|$value'),
          initialValue: value,
          enabled: false,
          decoration: const InputDecoration(
              isDense: true, border: OutlineInputBorder()),
        ),
        SizedBox(height: 12.h),
      ],
    );
  }

//---------------------------------------
// read catogory id and name
//---------------------------------------
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

//---------------------------------------
// read manager id and name
//---------------------------------------
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
        // then find "username"
        final name = ((data?['username']) as String?)?.trim() ?? '';
        return name.isEmpty ? '—' : name;
      }(),
    );
  }
//---------------------------------------
// preview the image, means show the image
//---------------------------------------
  Widget _imagePreviewBox(String? name) {
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
          child: _assetImageOrLabel(name),
        ),
        SizedBox(height: 12.h),
      ],
    );
  }

  String _statusLabel(bool dbActive) => dbActive ? 'Active' : 'Disabled';

//---------------------------------------
// Main build in right pannel
//---------------------------------------
  @override
  Widget build(BuildContext context) {
    //---------------------------------------
// box panel design the whole out countainer
//---------------------------------------
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
    //---------------------------------------
// if view mode but no facility id display
//---------------------------------------
    if (_view == 'view' && widget.selectedFacilityId == null) {
      return _emptyPlaceholder();
    }
//---------------------------------------
// if in add mode then display
//---------------------------------------

    if (_view == 'add') {
      return _buildForm(isEdit: false);
    }

//---------------------------------------
// if in edit mode then display
//---------------------------------------
    if (_view == 'edit') {
      return _buildForm(isEdit: true);
    }
//---------------------------------------
// if none of it meet , means its view mode with facility data
//---------------------------------------

    final Map<String, dynamic> d =
    widget.selectedFacilityData == null ? <String, dynamic>{} : Map<String, dynamic>
        .from(widget.selectedFacilityData!);

    //---------------------------------------
// set all of the information from database to string to prepare for display
//---------------------------------------
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
    if (d.containsKey('bookingDurationHours') &&
        d['bookingDurationHours'] != null) {
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


    final String? categoryId = (d['categoryId']?.toString());
    final String? managerId = (d['managerId']?.toString());

    //---------------------------------------
// main design for view mode
//---------------------------------------
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ro('Facility Name', name),
        _imagePreviewBox(img),
        _roCategoryLive(categoryId),
        _ro('Facility Location', loc),
        _ro('Facility Details', det),
        _ro('Available Slots', slots),
        _ro('Required Capacity', reqCap),
        _ro('Max Capacity', maxCap),
        _ro('Available Time', '$startText – $endText'),
        //---------------------------------------
// display custom time slot
//---------------------------------------
        _ro('Custom Slots', (() {
          if (d.containsKey('customTimeSlots') && d['customTimeSlots'] is List) {
            final List raw = d['customTimeSlots'] as List;
            final List<String> labels = <String>[];
            for (final s in raw) {
              if (s is Map) {
                String st = '';
                String en = '';
                if (s.containsKey('start') && s['start'] != null)
                  st = s['start'].toString();
                if (s.containsKey('end') && s['end'] != null)
                  en = s['end'].toString();
                if (st.isNotEmpty && en.isNotEmpty)
                  labels.add('$st–$en');
              }
            }
            return labels.isEmpty ? '-' : labels.join(', ');
          }
          return '-';
        })()),

        _ro('Booking Duration', '$dur hour'),
        _roManagerLive(managerId),
        _ro('Status', _statusLabel(dbActive)),
        Row(
//---------------------------------------
// close button
//---------------------------------------

        mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: widget.onClose,
              child: const Text('Close'),
            ),
            SizedBox(width: 8.w),
//---------------------------------------
// edit button change view mode to edit
//---------------------------------------
            ElevatedButton(
              onPressed: () =>
                  setState(() {
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
//---------------------------------------
// main design for Edit and Add new facility form
//---------------------------------------
  Widget _buildForm({required bool isEdit}) {

    final List<Widget> disableExtras = <Widget>[];
    //---------------------------------------
// if it is disable facility, will have extra widget
//---------------------------------------
    if (_disableFacility) {
      disableExtras.addAll([
//---------------------------------------
// inactive reason
//---------------------------------------
        Text('Reason', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
        SizedBox(height: 6.h),
        TextFormField(
          controller: _inactiveReasonCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            hintText: 'Why is this facility unavailable?',
          ),
        ),
        SizedBox(height: 12.h),

//---------------------------------------
// date that allows to pick inactive range
//---------------------------------------
        Text('Date', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
        SizedBox(height: 6.h),
        SizedBox(
          width: 1.0.sw,
          child: OutlinedButton.icon(
//---------------------------------------
// on press will open calender
//---------------------------------------
          onPressed: _pickInactiveRange,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _inactiveRange == null
                    ? 'From — to —'
                    : 'From ${_fmtDate(_inactiveRange!.start)} to ${_fmtDate(_inactiveRange!.end)}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14.sp, color: Colors.black87),
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
              side: const BorderSide(color: Colors.black54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.r)),
              minimumSize: Size.fromHeight(46.h),
              alignment: Alignment.centerLeft,
            ),
          ),
        ),
      ]);
    }

//---------------------------------------
// dget the image name
//---------------------------------------
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

//---------------------------------------
// The form design for edit and add
//---------------------------------------
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
//---------------------------------------
// display facility name
//---------------------------------------
          Text('Facility Name',
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          TextFormField(
            controller: _nameCtrl,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              return null;
            },
            decoration:
            const InputDecoration(isDense: true, border: OutlineInputBorder()),
          ),
          SizedBox(height: 12.h),
//---------------------------------------
// display image
//---------------------------------------

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
            child: _assetImageOrLabel(previewName),
          ),
          SizedBox(height: 6.h),
//---------------------------------------
//  allows to pick image
//---------------------------------------
          OutlinedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.upload_file, size: 16),
            label: const Text('Upload Image'),
          ),
          SizedBox(height: 12.h),

//---------------------------------------
// category drop down
//---------------------------------------
          Text('Facility Category',
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
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
//---------------------------------------
// check if category is deleted
//---------------------------------------
              final List<QueryDocumentSnapshot<Map<String, dynamic>>> raw =
                  snap.data!.docs;
              final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
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
//---------------------------------------
//list down the drop down category for pick category
//---------------------------------------
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
                  decoration: const InputDecoration(
                      isDense: true, border: OutlineInputBorder()),
                  hint: const Text('Option'),
                ),
              );
            },
          ),
          SizedBox(height: 12.h),
//---------------------------------------
// display display location
//---------------------------------------
          Text('Facility Location',
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          TextFormField(
            controller: _locationCtrl,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              return null;
            },
            decoration:
            const InputDecoration(isDense: true, border: OutlineInputBorder()),
          ),
          SizedBox(height: 12.h),

//---------------------------------------
// display facility details
//---------------------------------------
          Text('Facility Details',
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          TextFormField(
            controller: _detailsCtrl,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              return null;
            },
            maxLines: 3,
            decoration:
            const InputDecoration(isDense: true, border: OutlineInputBorder()),
          ),
          SizedBox(height: 12.h),

//---------------------------------------
// display available slots
//---------------------------------------
          Text('Available Slots',
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          Row(
            children: [
              IconButton(
//---------------------------------------
// decrement button, cannot less than 1
//---------------------------------------

              onPressed: () {
                  setState(() {
                    _slots = _slots - 1;
                    if (_slots < 1) _slots = 1;
                  });
                },
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
 //---------------------------------------
// when press the column ca input
//---------------------------------------
              width: 60.w,
                child: TextFormField(
                  key: ValueKey<int>(_slots),
                  initialValue: _slots.toString(),
                  onChanged: (v) {
                    int n = int.tryParse(v) ?? 1;
                    if (n < 1) n = 1;
                    _slots = n;
                  },
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    return null;
                  },
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                      isDense: true, border: OutlineInputBorder()),
                ),
              ),
//---------------------------------------
// increment button
//---------------------------------------

              IconButton(
                onPressed: () => setState(() => _slots = _slots + 1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          SizedBox(height: 12.h),

//---------------------------------------
// required capacity
//---------------------------------------
          Text('Required Capacity',
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          Row(
            children: [
              IconButton(
//---------------------------------------
// decrement button cannot less than 1
//---------------------------------------

              onPressed: () {
                  setState(() {
                    _requiredCapacity = _requiredCapacity - 1;
                    if (_requiredCapacity < 1) _requiredCapacity = 1;
                  });
                },
                icon: const Icon(Icons.remove),
              ),
//---------------------------------------
// can manual input
//---------------------------------------
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
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Cannot be empty';
                    return null;
                  },
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                      isDense: true, border: OutlineInputBorder()),
                ),
              ),
//---------------------------------------
// increment button
//---------------------------------------
              IconButton(
                onPressed: () =>
                    setState(() => _requiredCapacity = _requiredCapacity + 1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          SizedBox(height: 12.h),
//---------------------------------------
// max capacity
//---------------------------------------
          Text('Max Capacity',
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          Row(
 //---------------------------------------
// decrement button cannot less than 1
//---------------------------------------
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
//---------------------------------------
// can manually input
//---------------------------------------
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
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Cannot be empty';
                    return null;
                  },
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                      isDense: true, border: OutlineInputBorder()),
                ),
              ),
//---------------------------------------
// buttono increament by 1
//---------------------------------------
            IconButton(
                onPressed: () => setState(() => _maxCapacity = _maxCapacity + 1),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          SizedBox(height: 12.h),

//---------------------------------------
// booking duration
//---------------------------------------
          Text('Booking Duration',
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
          SizedBox(height: 6.h),
          Row(
            children: [
//---------------------------------------
// button decrement by 1
//---------------------------------------
              IconButton(
                onPressed: () {
                  int val = int.tryParse(_durationCtrl.text.trim()) ?? 1;
                  if (val > 1) val = val - 1;
                  _durationCtrl.text = val.toString();
                  setState(() {});
                },
                icon: const Icon(Icons.remove),
              ),
//---------------------------------------
// can manually input
//---------------------------------------
              SizedBox(
                width: 100.w,
                child: TextFormField(
                  controller: _durationCtrl,
                  textAlign: TextAlign.center,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly
                  ],
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    int val = int.tryParse(v ?? '') ?? 0;
                    if (val <= 0) return 'Required';
                    return null;
                  },
                  decoration: const InputDecoration(
                      isDense: true, border: OutlineInputBorder()),
                ),
              ),
              SizedBox(width: 8.w),
              const Text('hour'),
//---------------------------------------
// increment button by 1
//---------------------------------------
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

//---------------------------------------
// custom booking slot
//---------------------------------------
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
//---------------------------------------
// get teh same colour as boxpanel fill
//---------------------------------------
                  color: _BoxPanel._fill,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                        color: const Color(0xFF8620E2).withOpacity(.25), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.schedule,
                              size: 18.sp, color: const Color(0xFF5B1BC2)),
                          SizedBox(width: 6.w),
                          Text('Add custom slot(s)',
                              style: TextStyle(
                                  fontSize: 12.sp, fontWeight: FontWeight.w600)),
                          const Spacer(),
//---------------------------------------
// add tiem slot button
//---------------------------------------

                          SizedBox(
                            height: 36.h,
                            child: OutlinedButton.icon(
//---------------------------------------
// open on add custom slot
//---------------------------------------
                            onPressed: _onAddCustomSlot,
                              icon: const Icon(Icons.add),
                              label: const Text('Add time slot'),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                    color:
                                    const Color(0xFF5B1BC2).withOpacity(.7),
                                    width: 1.2),
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
//---------------------------------------
// show custom time
//---------------------------------------
                      if (_customSlots.isEmpty)
                        Container(
                          width: 1.0.sw,
                          padding: EdgeInsets.symmetric(vertical: 12.h),
                          alignment: Alignment.center,
                          child: Text('No slots yet. Tap "Add time slot".',
                              style:
                              TextStyle(fontSize: 12.sp, color: Colors.black)),
                        )
                      else
                        Wrap(
                          spacing: 8.w,
                          runSpacing: 8.h,
                          children:
//---------------------------------------
// show each of the custom slot using wrap
//---------------------------------------
                          List.generate(_customSlots.length, (int i) {
                            final int s =
                            _safeParseInt(_customSlots[i]['startMin'], 0);
                            final int e =
                            _safeParseInt(_customSlots[i]['endMin'], 0);
//---------------------------------------
// the design for each cell
//---------------------------------------
                            return Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 12.w, vertical: 8.h),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD9C9FF),
                                borderRadius: BorderRadius.circular(999.r),
                                border: Border.all(
                                    color: const Color(0xFF8620E2)
                                        .withOpacity(.25),
                                    width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.access_time,
                                      size: 14.sp, color: Colors.black87),
                                  SizedBox(width: 6.w),

//---------------------------------------
// from when to when, convert the minute back to hour
//---------------------------------------

                                  Text(
                                    '${_showHHMM(s)} – ${_showHHMM(e)}',
                                    style: TextStyle(
                                        fontSize: 12.sp,
                                        color: Colors.black,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  SizedBox(width: 8.w),
//---------------------------------------
// remove time slot button
//---------------------------------------
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _customSlots.removeAt(i);
                                        _slotError = _customSlots.isEmpty
                                            ? 'Required'
                                            : null;
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
//---------------------------------------
// if have error text from validator, display it below them
//---------------------------------------
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

//---------------------------------------
// display manager drop down
//---------------------------------------

          Text('Assign Manager',
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
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
//---------------------------------------
// get the not deleted one
//---------------------------------------

              final docs = snap.data!.docs.where((d) {
                final m = d.data();
                return m['deleted'] != true;
              }).toList();

//---------------------------------------
// make a drop down
//---------------------------------------
              final List<DropdownMenuItem<String>> items =
              <DropdownMenuItem<String>>[];
              for (final d in docs) {
                final m = d.data();
                String nm = 'Manager';
                if (m['username'] != null) {
                  nm = m['username'].toString();
                }
                items.add(
//---------------------------------------
// show drop down
//---------------------------------------
                DropdownMenuItem<String>(
                    value: d.id,
                    child: Text(nm, overflow: TextOverflow.ellipsis),
                    onTap: () => _managerName = nm,
                  ),
                );
              }
              //---------------------------------------
// on the drop down button display manager
//---------------------------------------
              final bool found = items.any((it) => it.value == _managerId);
              final String? value = found ? _managerId : null;

              return DropdownButtonFormField<String>(
                value: value,
                items: items,
                onChanged: (v) => setState(() => _managerId = v),
                validator: (v) {
                  if (v == null) return 'Required';
                  return null;
                },
                decoration: const InputDecoration(
                    isDense: true, border: OutlineInputBorder()),
                hint: const Text('Option'),
              );
            },
          ),

          SizedBox(height: 12.h),

//---------------------------------------
// if it is in edit mode add one more disable facility temporary as switch button
//---------------------------------------

          if (isEdit) ...[
            Row(
              children: [
                const Text('Disable facility temporarily'),
                const SizedBox(width: 8),
                Switch(
                  value: _disableFacility,
                  onChanged: (v) => setState(() {
                    _disableFacility = v;
//---------------------------------------
// when open set default start and end today for inactive range
//---------------------------------------
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
//---------------------------------------
// then show this which already display above
//---------------------------------------
            ...disableExtras, // will be empty when not disabled
          ],

          SizedBox(height: 16.h),

//---------------------------------------
// during edit mode
//---------------------------------------
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isEdit) ...[
 //---------------------------------------
// delete button
//---------------------------------------
                TextButton(
                  onPressed: () async {
                    final bool ok = await _confirmDelete();
                    if (ok) await _softDelete();
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Delete'),
                ),
//---------------------------------------
// cancel button
//---------------------------------------

                SizedBox(width: 8.w),
                TextButton(
                  onPressed: () => setState(() => _view = 'view'),
                  child: const Text('Cancel'),
                ),
                SizedBox(width: 8.w),
//---------------------------------------
// confirm button
//---------------------------------------
                ElevatedButton(
                    onPressed: _saveEdit, child: const Text('Confirm')),
              ] else ...[
//---------------------------------------
// if in add mode , display cancel and add button
//---------------------------------------
                TextButton(
                    onPressed: widget.onClose, child: const Text('Cancel')),
                SizedBox(width: 8.w),
                ElevatedButton(
                    onPressed: _saveNew, child: const Text('Add')),
              ],
            ],
          ),
        ],
      ),
    );
  }

}

//---------------------------------------
// get the category or manager name from database proccess
//---------------------------------------

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
        //---------------------------------------
// display name
//---------------------------------------
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
