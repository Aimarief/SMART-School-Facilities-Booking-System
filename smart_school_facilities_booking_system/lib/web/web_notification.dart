import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'web_top_bar.dart';

class WebNotification extends StatefulWidget {
  const WebNotification({Key? key}) : super(key: key);

  @override
  State<WebNotification> createState() => _WebNotificationState();
}

class _WebNotificationState extends State<WebNotification> {

  final bool _use24HourFormat = true;

  String _filter = 'none';

  bool _dateFilterOn = false;
  DateTime _selectedDay = DateTime.now(); // default today

  String? _selectedNotifId;
  Map<String, dynamic>? _selectedNotifData; // raw inbox doc (authoritative)
  Map<String, dynamic>? _selectedBooking;   // loaded from Bookings/{bookingId} (fallback)
  bool _loadingRight = false;

  String _currentUid() => FirebaseAuth.instance.currentUser?.uid ?? '';

  DateTime? _tsToDate(dynamic v) => (v is Timestamp) ? v.toDate() : null;
//---------------------------------------
// filter if filter is none next is unread, if f is unread next is read
//---------------------------------------
  String _nextFilter(String f) => f == 'none' ? 'unread' : (f == 'unread' ? 'read' : 'none');

  String _toYMD(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

//---------------------------------------
// format the day
//---------------------------------------
  String _formatLongDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

//---------------------------------------
// format time to am or pm
//---------------------------------------
  String _formatTimeShort(DateTime d) {
    int hh = d.hour;
    final mm = d.minute;
    String ap = 'am';
    int disp = hh;
    if (hh == 0) { disp = 12; ap = 'am'; }
    else if (hh == 12) { disp = 12; ap = 'pm'; }
    else if (hh > 12) { disp = hh - 12; ap = 'pm'; }
    final mmStr = mm.toString().padLeft(2, '0');
    return '$disp:$mmStr $ap';
  }

//---------------------------------------
// check same day
//---------------------------------------

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  //---------------------------------------
// open date picker
//---------------------------------------
  Future<void> _openDayPicker() async {
    final today = DateTime.now();
    final first = DateTime(today.year - 1, today.month, today.day);
    final last  = DateTime(today.year + 1, today.month, today.day);

    //---------------------------------------
// format date pick first date show and last date show and selected day
//---------------------------------------

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: first,
      lastDate: last,
      helpText: 'Select a day',
      cancelText: 'Reset to All Days',
      confirmText: 'Apply',
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx),
          child: child ?? const SizedBox(),
        );
      },
    );

// After the dialog:
    if (picked == null) {
      // User tapped “Reset to All Days” (Cancel) → treat as reset
      setState(() => _dateFilterOn = false);
    } else {
      setState(() {
        _dateFilterOn = true;
        _selectedDay = picked;
      });
    }
  }
//---------------------------------------
// get the inbox for user id and sort by date
//---------------------------------------

  Stream<QuerySnapshot<Map<String, dynamic>>> _inboxStream() {
    final uid = _currentUid();
    if (uid.isEmpty) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('UserInformation')
        .doc(uid)
        .collection('Inbox')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

//---------------------------------------
// check wether the database shown user id if have then user can see the message
//---------------------------------------
  bool _canSee(Map<String, dynamic> m, String uid) {
    if (uid.isEmpty) return false;
    String recipient = (m['recipientId'] ).toString().trim();
    String manager   = (m['managerId']).toString().trim();
    String bookedBy  = (m['bookedBy']).toString().trim();
    String createdBy = (m['createdBy']).toString().trim();
    return recipient == uid || manager == uid || bookedBy == uid || createdBy == uid;
  }
//---------------------------------------
// mark as read
//---------------------------------------
  Future<void> _markAsRead(DocumentReference<Map<String, dynamic>> ref) async {
    try { await ref.update({'isRead': true, 'readAt': FieldValue.serverTimestamp()}); } catch (_) {}
  }

//---------------------------------------
// sort it base on date and readed status
//---------------------------------------

  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _groupByDate(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,) {
    final groups = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    final today = DateTime.now();
    final uid = _currentUid();

    for (final d in docs) {
      final m = d.data();
 //---------------------------------------
// check id the user can see
//---------------------------------------
      if (!_canSee(m, uid)) continue;
//---------------------------------------
// admin or manager dun need to look for rejected approval
//---------------------------------------
      final type = (m['type'] ?? '').toString().trim();
      if (type == 'approval_status') {
        final appr = ((m['approval'] ) as String).toLowerCase();
        if (appr.contains('rej')) continue; // skip "rejected"
      }
//---------------------------------------
// check if it is read or not
//---------------------------------------
      final isRead = (m['isRead'] == true);
      if (_filter == 'unread' && isRead) continue;
      if (_filter == 'read' && !isRead) continue;
//---------------------------------------
// convert to date format
//---------------------------------------
      DateTime? ts = _tsToDate(m['createdAt']);
      if (ts == null) continue;
//---------------------------------------
// if no date filter or date filter same as created day then ok
//---------------------------------------
      final dayOk = !_dateFilterOn || _sameDay(ts, _selectedDay);
      if (!dayOk) continue;

//---------------------------------------
//  if same dat put just if no put the date
//---------------------------------------
      final key = _sameDay(ts, today) ? '__JUST__' : _toYMD(ts);
      groups.putIfAbsent(key, () => []);
      groups[key]!.add(d);
    }
    return groups;
  }
//---------------------------------------
// sort the date
//---------------------------------------
  List<String> _sortedGroupKeys(Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> g) {
    final keys = g.keys.toList();
    final just = <String>[];
    final dates = <String>[];
    for (final k in keys) { if (k == '__JUST__') just.add(k); else dates.add(k); }
    dates.sort((a, b) => a == b ? 0 : (a.compareTo(b) > 0 ? -1 : 1)); // desc
    return <String>[...just, ...dates];
  }

  Widget _groupHeader(String key) {
    if (key == '__JUST__') return const SizedBox.shrink();
    DateTime? d;
    try { final p = key.split('-'); if (p.length == 3) d = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2])); } catch (_) {}
    return Text(d == null ? key : _formatLongDate(d), style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700));
  }

  final Map<String, String> _emailCache = <String, String>{};
  final Set<String> _emailLoading = <String>{};

  //---------------------------------------
// get email from user id
//---------------------------------------

  Future<void> _ensureEmailCached(String uid) async {
    if (uid.isEmpty || _emailCache.containsKey(uid) || _emailLoading.contains(uid)) return;
    _emailLoading.add(uid);
    try {
      final doc = await FirebaseFirestore.instance.collection('UserInformation').doc(uid).get();
      final m = doc.data();
      String email = '';
      if (m != null) {
        email = (m['email']).toString().trim();
      }
      _emailCache[uid] = email.isEmpty ? uid : email;
      if (mounted) setState(() {});
    } catch (_) {
      _emailCache[uid] = uid;
    } finally {
      _emailLoading.remove(uid);
    }
  }

//---------------------------------------
// read the booking date
//---------------------------------------

  static DateTime? _readBookingDate(Map<String, dynamic> m) {
    for (final k in ['bookingDate']) {
      if (m.containsKey(k)) {
        final v = m[k];
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        if (v is String) {
          final d1 = _tryParseYMD(v); if (d1 != null) return d1;

        }
      }
    }
    return null;
  }

  //---------------------------------------
// parse time
//---------------------------------------

  static DateTime? _readTime(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k)) {
        final v = m[k];
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        if (v is String) {
          final t2 = _tryParseHM(v);  if (t2 != null) return t2;
        }
      }
    }
    return null;
  }

  static String _readFirstStr(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k)) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
        if (v != null) return v.toString();
      }
    }
    return '';
  }

  static String _readFirstStrPrefNotif(
      Map<String, dynamic> inbox,
      Map<String, dynamic>? booking,
      List<String> keys,
      ) {
    final a = _readFirstStr(inbox, keys);
    if (a.isNotEmpty) return a;
    if (booking != null) return _readFirstStr(booking, keys);
    return '';
  }
//---------------------------------------
// format the day year month
//---------------------------------------

  static String _fmtDDMonYYYY(DateTime d) {
    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    final day = d.day.toString().padLeft(2, '0');
    return '$day ${months[d.month - 1]} ${d.year}';
  }
//---------------------------------------
// formate time to pm am
//---------------------------------------

  static String _fmt24WithAmPm(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    final ampm = (d.hour >= 12) ? 'pm' : 'am';
    return '$hh.$mm $ampm';
  }
//---------------------------------------
// split the date y m d
//---------------------------------------

  static DateTime? _tryParseYMD(String s) {
    try { final p = s.split('-'); if (p.length == 3) return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2])); } catch (_) {}
    return null;
  }

//---------------------------------------
// split the time hh mm
//---------------------------------------

  static DateTime? _tryParseHM(String s) {
    try { final p = s.split(':'); if (p.length == 2) { final now = DateTime.now(); return DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1])); } } catch (_) {}
    return null;
  }

//---------------------------------------
// read the approval from inbox
//---------------------------------------
  String _computeApprovalFromInbox(Map<String, dynamic> inbox) {
    String s = (inbox['approval'] ?? '').toString().trim();
    if (s.isEmpty) return 'pending';

    final l = s.toLowerCase();
    if (l.contains('accepted')) return 'accepted';
    if (l.contains('reject') ) return 'rejected';
    if (l.contains('pending'))  return 'pending';

//---------------------------------------
// default
//---------------------------------------
    return 'pending';
  }

  final Map<String, String> _facilityNameCache = <String, String>{};
  final Set<String> _facilityLoading = <String>{};

  //---------------------------------------
// get the current facility name
//---------------------------------------

  Future<void> _ensureFacilityNameCached(String fid) async {
    if (fid.isEmpty || _facilityNameCache.containsKey(fid) || _facilityLoading.contains(fid)) return;
    _facilityLoading.add(fid);
    try {
      final doc = await FirebaseFirestore.instance.collection('Facilities').doc(fid).get();
      final m = doc.data();
      String name = '';
      if (m != null) {
        name = (m['name'] ).toString().trim();
      }
      if (name.isEmpty) name = 'Facility';
      _facilityNameCache[fid] = name;
      if (mounted) setState(() {});
    } catch (_) {
      _facilityNameCache[fid] = 'Facility';
    } finally {
      _facilityLoading.remove(fid);
    }
  }

  //---------------------------------------
// get the facility name
//---------------------------------------
  String _displayFacilityName({
    required String facilityId,
    required String inboxFacilityName,
  }) {
    if (inboxFacilityName.trim().isNotEmpty) return inboxFacilityName.trim();
    if (facilityId.isEmpty) return 'Facility';
    final cached = _facilityNameCache[facilityId];
    if (cached != null && cached.isNotEmpty) return cached;
    _ensureFacilityNameCached(facilityId); // async fill
    return 'Facility';
  }

//---------------------------------------
// main build
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
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 1684.w),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
//---------------------------------------
// left box
//---------------------------------------
                          _Box(
                            width: 460.w,
                            height: 965.h,
                            title: 'Notification',
                            header: _LeftHeader(
                              onCycleFilter: () => setState(() => _filter = _nextFilter(_filter)),
                              currentFilter: _filter,
                              onOpenCalendar: _openDayPicker,
                              dateFilterOn: _dateFilterOn,
                              selectedDay: _selectedDay,
                              formatDate: _formatLongDate,
                            ),
                            child: _buildLeftBody(),
                          ),
                          SizedBox(width: 24.w),
//---------------------------------------
// right box
//---------------------------------------
                          _Box(
                            width: 1200.w,
                            height: 965.h,
                            title: 'Details',
                            child: Padding(
                              padding: EdgeInsets.only(right: 8.w, bottom: 8.h),
                              child: _buildRightPanel(),
                            ),
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
//---------------------------------------
// left list design
//---------------------------------------
  Widget _buildLeftBody() {
    final uid = _currentUid();
    if (uid.isEmpty) {
      return Center(child: Text('Please sign in', style: TextStyle(fontSize: 14.sp)));
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _inboxStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snap.hasError) return Center(child: Text('Failed to load', style: TextStyle(fontSize: 14.sp)));
        if (!snap.hasData) return Center(child: Text('Empty', style: TextStyle(fontSize: 14.sp)));
//---------------------------------------
// if no data show no notification
//---------------------------------------
        final docs = snap.data!.docs;
        if (docs.isEmpty) return Center(child: Text('No notifications', style: TextStyle(fontSize: 14.sp)));
// group by date first
        final groups = _groupByDate(docs);
        if (groups.isEmpty) return Center(child: Text('No notifications', style: TextStyle(fontSize: 14.sp)));

        final keys = _sortedGroupKeys(groups);
        return ListView.builder(
          itemCount: keys.length,
          itemBuilder: (context, idx) {
            final k = keys[idx];
            final items = groups[k] ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            return Padding(
              padding: EdgeInsets.only(bottom: 16.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
//---------------------------------------
// then display
//---------------------------------------
                children: [
                  _groupHeader(k),
                  SizedBox(height: 8.h),
                  ..._buildChipList(items),
                ],
              ),
            );
          },
        );
      },
    );
  }

//---------------------------------------
// show each item at left
//---------------------------------------
  List<Widget> _buildChipList(List<QueryDocumentSnapshot<Map<String, dynamic>>> items) {
    final children = <Widget>[];

    for (final d in items) {
      final m = d.data();

//---------------------------------------
// look at the type of mail
//---------------------------------------
      final String type = (m['type'] ?? '').toString().trim();
      final String typeLc = type.toLowerCase();
      final String approvalLc = (m['approval'] ).toString().toLowerCase();
      final String facilityId = _readFirstStr(m, ['facilityId']);
      final bool isPending =
          approvalLc.contains('pend') || approvalLc.contains('wait');
      final bool isAmendment = ((m['amendmentId'] ?? '').toString().trim().isNotEmpty);
//---------------------------------------
// set mail title base on type
//---------------------------------------

      String title;
      if (type == 'system_issue') {
        title = 'System Issue';
      } else if (type == 'approval_status') {
        title = 'Facility Approved';

      } else if (type == 'booking_created' && isPending) {
        title = 'Facility pending request' + (isAmendment ? ' (Amendment)' : '');
      } else if (type == 'booking_updated' && isPending) {
        title = 'Approval pending request';
      } else if (typeLc == 'booking_deleted') {
        title = 'Delete Booking';
      } else {
        title = (m['type'] != null) ? _titleForType(m['type'].toString()) : 'Message';
      }

      final String facilityName =
      _readFirstStr(m, ['facilityName']);
      final String bookedUid = _readFirstStr(m, ['bookedBy','bookBy']);


      String email = '-';
      if (bookedUid.isNotEmpty) {
        final cached = _emailCache[bookedUid];
        if (cached != null && cached.isNotEmpty) {
          email = cached;
        } else {
          _ensureEmailCached(bookedUid);
          email = '…';
        }
      }
//---------------------------------------
// subtitle for the title
//---------------------------------------

      String subtitle;

      if (type == 'system_issue') {
        final reporterEmail = (m['email'] ?? '-').toString();
        subtitle = '$reporterEmail has reported an issue';

      } else if (type == 'approval_status') {

        subtitle = '${facilityName.isEmpty ? '-' : facilityName} is approved';
      } else if ((type == 'booking_created' || type == 'booking_updated') &&
          (approvalLc.contains('pend') )) {
//---------------------------------------
// get facility name and id
//---------------------------------------
        final facLbl = _displayFacilityName(
          facilityId: facilityId,
          inboxFacilityName: facilityName,
        );
        subtitle = '$facLbl is currently waiting for approval';
      } else if (typeLc == 'booking_deleted') {
        final facLbl = _displayFacilityName(
          facilityId: facilityId,
          inboxFacilityName: facilityName,
        );
        subtitle = 'The booked $facLbl have been deleted';

      } else {
        subtitle = 'The ${facilityName.isEmpty ? '-' : facilityName} is booked by $email';
      }

//---------------------------------------
// check if is read or not
//---------------------------------------

      final bool isRead = (m['isRead'] == true);
      String timeLbl = '-';
      final created = _tsToDate(m['createdAt']) ;
      if (created != null) timeLbl = _formatTimeShort(created);

      children.add(
        _NotifChip(
          title: title,
          subtitle: subtitle,
          timeLabel: timeLbl,
          isRead: isRead,
          onTap: () async {
            setState(() { _selectedNotifId = d.id; _selectedNotifData = m; _loadingRight = true; });
            if (!isRead) await _markAsRead(d.reference);

            String bookingId = _readFirstStr(m, ['bookingId']);
            Map<String, dynamic>? booking;
            if (bookingId.isNotEmpty) {
              try {
                final snap = await FirebaseFirestore.instance.collection('Bookings').doc(bookingId).get();
                booking = snap.data();
                if (booking != null) booking['__id'] = snap.id;
              } catch (_) {}
            }
            setState(() { _selectedBooking = booking; _loadingRight = false; });
          },
        ),
      );
      children.add(SizedBox(height: 8.h));
    }

    return children;
  }

//---------------------------------------
// right panel design
//---------------------------------------

  Widget _buildRightPanel() {
    if (_loadingRight) return const Center(child: CircularProgressIndicator());
    if (_selectedNotifId == null || _selectedNotifData == null) {
//---------------------------------------
// when nothing is chosen yet
//---------------------------------------
      return Center(child: Text('Please select an option', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)));
    }

    final inbox = _selectedNotifData!;
    final booking = _selectedBooking;

    final type = (inbox['type'] ?? '').toString();
    final typeLc = type.toLowerCase();
    final bool isDeleted = typeLc == 'booking_deleted';
//---------------------------------------
// for issue mail
//---------------------------------------
    if (type == 'system_issue') {
      final reporterEmail = (inbox['email']).toString();
      final issueTitle = (inbox['title'] ).toString();
      final description = (inbox['message'] ).toString();
      final base64Img = (inbox['imageBase64'] ?? '').toString().trim();

//---------------------------------------
// decode the image for system isuue type
//---------------------------------------
      Uint8List? imgBytes;
      if (base64Img.isNotEmpty) {
        try {
          final clean = base64Img.contains(',') ? base64Img.split(',').last : base64Img;
          imgBytes = base64Decode(clean);
        } catch (_) {
          imgBytes = null;
        }
      }
//---------------------------------------
// design for system issue
//---------------------------------------
      return Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('System Issue', style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700)),
            SizedBox(height: 12.h),

            Text('Email:', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
            SizedBox(height: 4.h),
            Text(reporterEmail, style: TextStyle(fontSize: 13.sp)),
            SizedBox(height: 12.h),

            Text('Title:', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
            SizedBox(height: 4.h),
            Text(issueTitle, style: TextStyle(fontSize: 13.sp)),
            SizedBox(height: 12.h),

            Text('Description:', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
            SizedBox(height: 4.h),
            Text(description, style: TextStyle(fontSize: 13.sp)),
            SizedBox(height: 12.h),

            if (imgBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12.r),
                child: Container(
                  width: 200.w.clamp(150.0, 240.0),
                  height: 200.w.clamp(150.0, 240.0),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    color: const Color(0xFFF9FAFB),
                  ),
                  child: Image.memory(imgBytes, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                ),
              ),
          ],
        ),
      );
    }
//---------------------------------------
// for other mail type
//---------------------------------------
    final facilityId = _readFirstStrPrefNotif(inbox, booking, ['facilityId']);
    final bookedUid  = _readFirstStrPrefNotif(inbox, booking, ['bookedBy','userId']); // userId
    final createdUid = _readFirstStrPrefNotif(inbox, booking, ['createdBy']); // actor
    final managerUid = _readFirstStrPrefNotif(inbox, booking, ['managerId']);

    final String seat = _readFirstStr(inbox, ['seatIndex']);
    final DateTime? bookDate = _readBookingDate(inbox);
    final DateTime? tStart = _readTime(inbox, ['start']);
    final DateTime? tEnd   = _readTime(inbox, ['end']);

    final String dateStr  = (bookDate != null) ? _fmtDDMonYYYY(bookDate) : '';
    final String timeFancy = (tStart != null && tEnd != null)
        ? '${_fmt24WithAmPm(tStart)} - ${_fmt24WithAmPm(tEnd)}'
        : (tStart != null) ? _fmt24WithAmPm(tStart) : '';

    final reason = _readFirstStr(inbox, ['approvalReason']);
    final approval = _computeApprovalFromInbox(inbox);

    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
//---------------------------------------
// facility name
//---------------------------------------
          _FacilityNameLive(
            facilityId: facilityId,
            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827)),
          ),
          SizedBox(height: 12.h),

//---------------------------------------
// show image
//---------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FacilityImageSimple(facilityId: facilityId),
              SizedBox(width: 16.w),
//---------------------------------------
// show each of the item beside image
//---------------------------------------
              Expanded(
                child: _summaryColumn(// each of the spacing
                  children: [// each of the box
                    _summaryLine(icon: Icons.event_seat, labelLower: 'slot', value: seat),
                    _summaryLine(icon: Icons.calendar_today_outlined, labelLower: 'date', value: dateStr),
                    _summaryLine(icon: Icons.schedule, labelLower: 'time', value: timeFancy),
                    _summaryLineLiveEmail(icon: Icons.person_outline, labelLower: 'booked by', uid: bookedUid),
                    _summaryLineLiveEmail(icon: Icons.person_outline_outlined, labelLower: 'created by', uid: createdUid),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: 16.h),
//---------------------------------------
// approval details
//---------------------------------------
          Text('Approval Details', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
          SizedBox(height: 6.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Text(reason.isEmpty ? '—' : reason, style: TextStyle(fontSize: 13.sp, color: const Color(0xFF111827))),
          ),

          SizedBox(height: 16.h),

//---------------------------------------
// booked by which use
//---------------------------------------
          Text('Booked by', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
          SizedBox(height: 8.h),
          SizedBox(
            width: double.infinity,
            child: _PersonCard.fromUid(
              uid: bookedUid,
              fillColor: const Color(0xFFF9F4FF),
              showStatusFromRole: true,
              photoMode: _PhotoMode.base64, // user: base64-only
            ),
          ),
          SizedBox(height: 14.h),
//---------------------------------------
// which facility manager it
//---------------------------------------
          Text('Facility Manager', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
          SizedBox(height: 8.h),
          SizedBox(
            width: double.infinity,
            child: _PersonCard.fromUid(
              uid: managerUid,
              fillColor: const Color(0xFFF9F4FF),
              showStatusFromRole: false,
              photoMode: _PhotoMode.asset, // manager: asset path only
            ),
          ),
          SizedBox(height: 14.h),
//---------------------------------------
// if it is deleted status then show deleted icon
//---------------------------------------
          if (isDeleted)
            _summaryLine(icon: Icons.delete_outline, labelLower: 'status', value: 'The booking for this user have been deleted')
          else
            _summaryLine(icon: Icons.verified_outlined, labelLower: 'approval', value: approval),
        ],
      ),
    );
  }

//---------------------------------------
// show each column beside the image
//---------------------------------------

  Widget _summaryColumn({required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, // stretch children horizontally
      children: [
        for (int i = 0; i < children.length; i++) ...[
          children[i],
//---------------------------------------
// have a small ehight space every column
//---------------------------------------
          if (i != children.length - 1) SizedBox(height: 8.h),
        ],
      ],
    );
  }
//---------------------------------------
// each of the column beside image design
//---------------------------------------
  Widget _summaryLine({
    required IconData icon,
    required String labelLower,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFF),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6B7280)),
          SizedBox(width: 10.w),
          Text('${labelLower.toLowerCase()}: ', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
          Expanded(
            child: Text(value.isEmpty ? '—' : value, style: TextStyle(fontSize: 12.sp, color: const Color(0xFF111827)), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

//---------------------------------------
// for email column design
//---------------------------------------
  Widget _summaryLineLiveEmail({
    required IconData icon,
    required String labelLower,
    required String uid,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFBFF),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF6B7280)),
          SizedBox(width: 10.w),
          Text('${labelLower.toLowerCase()}: ', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
          Expanded(
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: (uid.isEmpty)
                  ? const Stream.empty()
                  : FirebaseFirestore.instance.collection('UserInformation').doc(uid).snapshots(),
              builder: (context, snap) {
                String value = '—';
                final data = snap.data?.data();
                if (data != null) {
                  final e = (data['email'] ) as String?;
                  value = (e != null && e.trim().isNotEmpty) ? e.trim() : (uid.isNotEmpty ? uid : '—');
                }
                return Text(value, style: TextStyle(fontSize: 12.sp, color: const Color(0xFF111827)), overflow: TextOverflow.ellipsis);
              },
            ),
          ),
        ],
      ),
    );
  }
  //---------------------------------------
// for approve or new booked by admin
//---------------------------------------
  String _titleForType(String? t) {
    final s = t?.toString() ?? '';
    if (s == 'booking_created') return 'New booked facility';
    if (s == 'booking_updated') return 'Booking updated';
    if (s == 'approval_status') return 'Facility Approved';
    return 'Message';
  }


}

//---------------------------------------
// the box that design right and left panel
//---------------------------------------

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

  static const Color _fill = Color(0xFFEDDFFF); // lilac panel
  static const Color _outline = Color(0xFF8620E2); // purple border

  @override
  Widget build(BuildContext context) {
    final List<Widget> stack = <Widget>[];
    if (header != null) { stack.add(header!); stack.add(SizedBox(height: 8.h)); }

    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _outline, width: 1.w),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 8.h),
          ...stack,
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6.r),
              child: Scrollbar(thumbVisibility: true, child: child),
            ),
          ),
        ],
      ),
    );
  }
}

//---------------------------------------
// left box header
//---------------------------------------

class _LeftHeader extends StatelessWidget {
  const _LeftHeader({
    Key? key,
    required this.onCycleFilter,
    required this.currentFilter,
    required this.onOpenCalendar,
    required this.dateFilterOn,
    required this.selectedDay,
    required this.formatDate,
  }) : super(key: key);

  final VoidCallback onCycleFilter;
  final String currentFilter;
  final VoidCallback onOpenCalendar;
  final bool dateFilterOn;
  final DateTime selectedDay;
  final String Function(DateTime d) formatDate;

  @override
  Widget build(BuildContext context) {

    IconData icon;
    String tip;
    if (currentFilter == 'unread') {
      icon = Icons.mark_email_unread;
      tip  = 'Filter: Unread (tap to switch)';
    } else if (currentFilter == 'read') {
      icon = Icons.mark_email_read;
      tip  = 'Filter: Read (tap to switch)';
    } else {
      icon = Icons.filter_list;
      tip  = 'Filter: All (tap to switch)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                dateFilterOn ? formatDate(selectedDay) : 'Just',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(width: 8.w),
            SizedBox(
              width: 36.w,
              height: 36.h,
              child: Tooltip(
                message: tip,
                child: OutlinedButton(
                  onPressed: onCycleFilter,
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                  child: Icon(icon, size: 18.sp),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            SizedBox(
              width: 36.w,
              height: 36.h,
              child: OutlinedButton(
                onPressed: onOpenCalendar,
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                child: Icon(Icons.calendar_today, size: 18.sp),
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
      ],
    );
  }
}

//---------------------------------------
// each notification at the left side design
//---------------------------------------
class _NotifChip extends StatelessWidget {
  const _NotifChip({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.timeLabel,
    required this.isRead,
    required this.onTap,
  }) : super(key: key);

  final String title;
  final String subtitle;
  final String timeLabel;
  final bool isRead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const Color unreadBg = Color(0xFFE6D6FF);
    const Color readBg = Color(0xFFF5ECFF);
    final Color bg = isRead ? readBg : unreadBg;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8.r),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8.r),
        child: Container(
          width: double.infinity,
          height: 96.h,
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700)),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.sp)),
              Text(timeLabel, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.sp, color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}

//---------------------------------------
// get the facility name live
//---------------------------------------
class _FacilityNameLive extends StatelessWidget {
  final String facilityId;
  final TextStyle style;
  final TextOverflow overflow;

  const _FacilityNameLive({
    Key? key,
    required this.facilityId,
    required this.style,
    this.overflow = TextOverflow.ellipsis,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (facilityId.isEmpty) return Text('', style: style, overflow: overflow);
    final ref = FirebaseFirestore.instance.collection('Facilities').doc(facilityId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final name = (data?['name'] ?? data?['facilityName']) as String?;
        final display = (name != null && name.trim().isNotEmpty) ? name.trim() : '';
        return Text(display, style: style, overflow: overflow);
      },
    );
  }
}

//---------------------------------------
// show facility image
//---------------------------------------

class _FacilityImageSimple extends StatelessWidget {
  const _FacilityImageSimple({Key? key, required this.facilityId}) : super(key: key);

  final String facilityId;

  @override
  Widget build(BuildContext context) {
    final double size = 200.w.clamp(150.0, 240.0);
    if (facilityId.isEmpty) return _box(size, _placeholder());

    final ref = FirebaseFirestore.instance.collection('Facilities').doc(facilityId);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        String? path = (data?['imagePath'] as String?)?.trim();
        path ??= (data?['imageName'] as String?)?.trim();
        if (path != null && path.isNotEmpty && !path.startsWith('asset/')) {
          path = 'asset/image/$path';
        }
        final child = (path != null && path.isNotEmpty)
            ? Image.asset(path, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())
            : _placeholder();
        return _box(size, child);
      },
    );
  }
//---------------------------------------
// return image box
//---------------------------------------
  Widget _box(double size, Widget child) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E7EB)),
          color: const Color(0xFFF9FAFB),
        ),
        child: child,
      ),
    );
  }
//---------------------------------------
// show this image if there is no image
//---------------------------------------
  Widget _placeholder() => const Center(child: Icon(Icons.image, size: 44, color: Color(0xFF9CA3AF)));
}

//---------------------------------------
// check where the photofrom and display person profile
//---------------------------------------

enum _PhotoMode { base64, asset }

class _PersonCard extends StatelessWidget {
  const _PersonCard({
    Key? key,
    required this.name,
    required this.email,
    required this.contact,
    required this.fillColor,
    this.status,
    this.title,
    this.photoBytes,
    this.assetPath,
  }) : super(key: key);

  static Widget fromUid({
    required String uid,
    required Color fillColor,
    required bool showStatusFromRole,
    _PhotoMode photoMode = _PhotoMode.base64, // default to base64 for users
    String? title,
  }) {
    if (uid.isEmpty) {
      return _PersonCard(
        title: title,
        name: '',
        email: '',
        contact: '',
        status: showStatusFromRole ? '' : null,
        fillColor: fillColor,
      );
    }
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('UserInformation').doc(uid).get(),
      builder: (context, snap) {
        final data = snap.data?.data();

        final String name  = _pickFirst(data?['username']);
        final String email = _pickFirst(data?['email']);
        final String phone = _pickFirst(data?['contact']);
        final String role  = _pickFirst(data?['role']);

        Uint8List? bytes;
        String? assetPath;
//---------------------------------------
// if image in base 64 mode decode
//---------------------------------------

        if (photoMode == _PhotoMode.base64) {
          final String b64 = _pickFirst(data?['profileImageBase64']);
          bytes = _tryDecodeBase64(b64);
        } else {
//---------------------------------------
// if its not , then get from asset
//---------------------------------------
          String? p = _pickFirst(data?['profileImageName']);
          if (p != null && p.isNotEmpty && !p.startsWith('asset/')) {
            p = 'asset/image/$p';
          }
          assetPath = p;
        }

        return _PersonCard(
          title: title,
          name: name,
          email: email,
          contact: phone,
          status: showStatusFromRole ? role : null,
          fillColor: fillColor,
          photoBytes: bytes,
          assetPath: assetPath,
        );
      },
    );
  }

  final String? title;
  final String name;
  final String email;
  final String contact;
  final String? status;
  final Color fillColor;

  final Uint8List? photoBytes; // base64 only
  final String? assetPath;     // asset only
//---------------------------------------
// check wether it is asset image or byte image
//---------------------------------------
  bool get _hasBytes => photoBytes != null && photoBytes!.isNotEmpty;
  bool get _hasAsset => assetPath != null && assetPath!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final double size = 96.w.clamp(84.0, 120.0);
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
//---------------------------------------
// display image
//---------------------------------------

          ClipRRect(
            borderRadius: BorderRadius.circular(12.r),
            child: Container(
              width: size,
              height: size,
              color: const Color(0xFFF3F4F6),
              child: _buildPhoto(),
            ),
          ),
          SizedBox(width: 12.w),
//---------------------------------------
// display name, email and status
//---------------------------------------
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title!, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: const Color(0xFF6B7280))),
                  SizedBox(height: 4.h),
                ],
                _kv('Name', name),
                SizedBox(height: 4.h),
                _kv('Email', email),
                SizedBox(height: 4.h),
                _kv('Contact', contact),
                if (status != null) ...[
                  SizedBox(height: 4.h),
                  _kv('Status', status!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoto() {
    if (_hasBytes) {
      return Image.memory(photoBytes!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _avatarFallback(name));
    }
    if (_hasAsset) {
      return Image.asset(assetPath!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _avatarFallback(name));
    }
    return _avatarFallback(name);
  }
//---------------------------------------
// decode the image
//---------------------------------------
  static Uint8List? _tryDecodeBase64(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try { final s = raw.contains(',') ? raw.substring(raw.indexOf(',') + 1) : raw; return base64Decode(s); } catch (_) { return null; }
  }

  static String _pickFirst(dynamic a, [dynamic b, dynamic c]) {
    for (final v in [a, b, c]) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }
//---------------------------------------
// key : v
//---------------------------------------

  Widget _kv(String k, String v) {
    return Row(
      children: [
        Text('$k: ', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
        Expanded(child: Text(v.trim().isEmpty ? '—' : v.trim(), style: TextStyle(fontSize: 12.sp, color: const Color(0xFF111827)), overflow: TextOverflow.ellipsis)),
      ],
    );
  }
//---------------------------------------
// when there is no image
//---------------------------------------

  Widget _avatarFallback(String name) {
    final initials = _initials(name);
    return Center(child: Text(initials, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF))));
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
