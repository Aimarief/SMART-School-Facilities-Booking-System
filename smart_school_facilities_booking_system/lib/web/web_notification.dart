// lib/web_notification.dart
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
  // ----- top bar format -----
  final bool _use24HourFormat = true;

  // ----- filter state: 'none' | 'unread' | 'read' -----
  String _filter = 'none';

  // ----- date filter -----
  bool _dateFilterOn = false;
  DateTime _selectedDay = DateTime.now(); // default today

  // ----- selection for right panel -----
  String? _selectedNotifId;
  Map<String, dynamic>? _selectedNotifData; // raw inbox doc (authoritative)
  Map<String, dynamic>? _selectedBooking;   // loaded from Bookings/{bookingId} (fallback)
  bool _loadingRight = false;

  // =========================
  // Small helpers
  // =========================

  String _currentUid() => FirebaseAuth.instance.currentUser?.uid ?? '';

  DateTime? _tsToDate(dynamic v) => (v is Timestamp) ? v.toDate() : null;

  String _nextFilter(String f) => f == 'none' ? 'unread' : (f == 'unread' ? 'read' : 'none');

  String _toYMD(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatLongDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

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

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _openDayPicker() async {
    final today = DateTime.now();
    final first = DateTime(today.year - 1, today.month, today.day);
    final last  = DateTime(today.year + 1, today.month, today.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: first,
      lastDate: last,
      builder: (ctx, child) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(child: child ?? const SizedBox()),
            SizedBox(height: 4.h),
            TextButton(
              onPressed: () {
                setState(() => _dateFilterOn = false);
                Navigator.of(ctx).pop();
              },
              child: const Text('Reset to All Days'),
            ),
            SizedBox(height: 8.h),
          ],
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDay = picked;
        _dateFilterOn = true;
      });
    }
  }

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

  /// Visibility: allow if recipientId == uid OR managerId == uid OR bookedBy/bookBy == uid OR createdBy == uid
  bool _canSee(Map<String, dynamic> m, String uid) {
    if (uid.isEmpty) return false;
    String recipient = (m['recipientId'] ?? '').toString().trim();
    String manager   = (m['managerId']   ?? '').toString().trim();
    String bookedBy  = (m['bookedBy']    ?? m['bookBy'] ?? '').toString().trim();
    String createdBy = (m['createdBy']   ?? m['creatorUid'] ?? m['creatorId'] ?? '').toString().trim();
    return recipient == uid || manager == uid || bookedBy == uid || createdBy == uid;
  }

  Future<void> _markAsRead(DocumentReference<Map<String, dynamic>> ref) async {
    try { await ref.update({'isRead': true, 'readAt': FieldValue.serverTimestamp()}); } catch (_) {}
  }

  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _groupByDate(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
      ) {
    final groups = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    final today = DateTime.now();
    final uid = _currentUid();

    for (final d in docs) {
      final m = d.data();
      if (!_canSee(m, uid)) continue;

      // 🔎 hide rejected approval_status
      final type = (m['type'] ?? '').toString().trim();
      if (type == 'approval_status') {
        final appr = ((m['approval'] ?? m['approvalStatus'] ?? m['status'] ?? '') as String)
            .toLowerCase();
        if (appr.contains('rej')) continue; // skip "rejected"
      }

      final isRead = (m['isRead'] == true);
      if (_filter == 'unread' && isRead) continue;
      if (_filter == 'read' && !isRead) continue;

      DateTime? ts = _tsToDate(m['createdAt']);
      if (ts == null) ts = _tsToDate(m['submittedAt']);  // <-- fallback for older docs
      if (ts == null) continue;

      final dayOk = !_dateFilterOn || _sameDay(ts, _selectedDay);
      if (!dayOk) continue;

      final key = _sameDay(ts, today) ? '__JUST__' : _toYMD(ts);
      groups.putIfAbsent(key, () => []);
      groups[key]!.add(d);
    }
    return groups;
  }


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

  // ======== EMAIL cache (for chip subtitle) ========
  final Map<String, String> _emailCache = <String, String>{};
  final Set<String> _emailLoading = <String>{};

  Future<void> _ensureEmailCached(String uid) async {
    if (uid.isEmpty || _emailCache.containsKey(uid) || _emailLoading.contains(uid)) return;
    _emailLoading.add(uid);
    try {
      final doc = await FirebaseFirestore.instance.collection('UserInformation').doc(uid).get();
      final m = doc.data();
      String email = '';
      if (m != null) {
        email = (m['email'] ?? m['userEmail'] ?? m['emailAddress'] ?? '').toString().trim();
      }
      _emailCache[uid] = email.isEmpty ? uid : email;
      if (mounted) setState(() {});
    } catch (_) {
      _emailCache[uid] = uid;
    } finally {
      _emailLoading.remove(uid);
    }
  }

  // ---------- Details helpers (parsing, formats) ----------
  static DateTime? _readBookingDate(Map<String, dynamic> m) {
    for (final k in ['bookingDate', 'date', 'bookDate', 'day']) {
      if (m.containsKey(k)) {
        final v = m[k];
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        if (v is String) {
          final d1 = _tryParseYMD(v); if (d1 != null) return d1;
          final d2 = _tryParseDMY(v); if (d2 != null) return d2;
        }
      }
    }
    return null;
  }

  static DateTime? _readTime(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k)) {
        final v = m[k];
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        if (v is String) {
          final t1 = _tryParseHMS(v); if (t1 != null) return t1;
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

  static DateTime? _readBookingDatePrefNotif(Map<String, dynamic> inbox, Map<String, dynamic>? booking) {
    final a = _readBookingDate(inbox);
    if (a != null) return a;
    if (booking != null) return _readBookingDate(booking);
    return null;
  }

  static DateTime? _readTimePrefNotif(
      Map<String, dynamic> inbox,
      Map<String, dynamic>? booking,
      List<String> keys,
      ) {
    final a = _readTime(inbox, keys);
    if (a != null) return a;
    if (booking != null) return _readTime(booking, keys);
    return null;
  }

  static String _fmtDDMonYYYY(DateTime d) {
    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    final day = d.day.toString().padLeft(2, '0');
    return '$day ${months[d.month - 1]} ${d.year}';
  }

  static String _fmt24WithAmPm(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    final ampm = (d.hour >= 12) ? 'pm' : 'am';
    return '$hh.$mm $ampm';
  }

  static DateTime? _tryParseYMD(String s) {
    try { final p = s.split('-'); if (p.length == 3) return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2])); } catch (_) {}
    return null;
  }

  static DateTime? _tryParseDMY(String s) {
    try { final p = s.split('/'); if (p.length == 3) return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])); } catch (_) {}
    return null;
  }

  static DateTime? _tryParseHMS(String s) {
    try { final p = s.split(':'); if (p.length == 3) { final now = DateTime.now(); return DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]), int.parse(p[2])); } } catch (_) {}
    return null;
  }

  static DateTime? _tryParseHM(String s) {
    try { final p = s.split(':'); if (p.length == 2) { final now = DateTime.now(); return DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1])); } } catch (_) {}
    return null;
  }

  // ---- Approval status (prefer Booking doc) ----
// ---- Approval status (from Booking doc only) ----
  String _computeApprovalFromInbox(Map<String, dynamic> inbox) {
    // Prefer the 'approval' field you now store
    String s = (inbox['approval'] ?? '').toString().trim();

    // Fallbacks, in case some old items used these keys
    if (s.isEmpty) s = (inbox['approvalStatus'] ?? '').toString().trim();
    if (s.isEmpty) s = (inbox['status'] ?? '').toString().trim(); // only if it’s one of accepted/pending/rejected

    if (s.isEmpty) return 'pending';

    final l = s.toLowerCase();
    if (l.contains('acc') || l.contains('approv')) return 'accepted';
    if (l.contains('rej') || l.contains('declin') || l.contains('deni')) return 'rejected';
    if (l.contains('pend') || l.contains('waiting')) return 'pending';

    // default if unknown text (avoid showing 'upcoming' etc.)
    return 'pending';
  }

  // ======== FACILITY name cache (for chip subtitle when inbox lacks facilityName) ========
  final Map<String, String> _facilityNameCache = <String, String>{};
  final Set<String> _facilityLoading = <String>{};

  Future<void> _ensureFacilityNameCached(String fid) async {
    if (fid.isEmpty || _facilityNameCache.containsKey(fid) || _facilityLoading.contains(fid)) return;
    _facilityLoading.add(fid);
    try {
      final doc = await FirebaseFirestore.instance.collection('Facilities').doc(fid).get();
      final m = doc.data();
      String name = '';
      if (m != null) {
        name = (m['name'] ?? m['facilityName'] ?? '').toString().trim();
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


  // =========================
  // BUILD
  // =========================

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
                      constraints: BoxConstraints(maxWidth: 460.w + 24.w + 1200.w),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // LEFT BOX
                          _Box(
                            width: 460.w,
                            height: 965.h,
                            title: 'Notification',
                            header: _LeftHeader(
                              onOpenSettings: () => Navigator.of(context).pushNamed('/webaccount'),
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
                          // RIGHT BOX
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

        final docs = snap.data!.docs;
        if (docs.isEmpty) return Center(child: Text('No notifications', style: TextStyle(fontSize: 14.sp)));

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

  /// Chip list (subtitle must show bookedBy/bookBy EMAIL)
  List<Widget> _buildChipList(List<QueryDocumentSnapshot<Map<String, dynamic>>> items) {
    final children = <Widget>[];

    for (final d in items) {
      final m = d.data();

      // ----- type / approval -----
      final String type = (m['type'] ?? '').toString().trim();
      final String typeLc = type.toLowerCase();
      final String approvalLc = (m['approval'] ?? m['approvalStatus'] ?? m['status'] ?? '')

          .toString()
          .toLowerCase();
      final String facilityId = _readFirstStr(m, ['facilityId','facilityID','facilityDocId','facility_id']);


      // ----- title -----
      String title;
      if (type == 'system_issue') {
        title = 'System Issue';
      } else if (type == 'approval_status') {
        title = 'Facility Approved';
      } else if (type == 'booking_created' &&
          (approvalLc.contains('pend') || approvalLc.contains('wait'))) {
        title = 'Facility pending request';
      } else if (type == 'booking_updated' &&
          (approvalLc.contains('pend') || approvalLc.contains('wait'))) {
        title = 'Approval pending request';
      } else if (typeLc == 'booking_deleted' || typeLc == 'deleted_booking') {     // <— add
        title = 'Delete Booking';
      } else {
        title = (m['type'] != null) ? _titleForType(m['type'].toString()) : 'Message';
      }



// ----- subtitle -----
      final String facilityName =
      _readFirstStr(m, ['facilityName', 'facility', 'facilityTitle']);
      final String bookedUid = _readFirstStr(m, ['bookedBy', 'bookBy']); // end-user id

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

      String subtitle;
      if (type == 'system_issue') {
        final reporterEmail = (m['email'] ?? '-').toString();
        subtitle = '$reporterEmail has reported an issue';
      } else if (type == 'approval_status') {
        subtitle = '${facilityName.isEmpty ? '-' : facilityName} is approved';
      } else if ((type == 'booking_created' || type == 'booking_updated') &&
          (approvalLc.contains('pend') || approvalLc.contains('wait'))) {
        final facLbl = _displayFacilityName(
          facilityId: facilityId,
          inboxFacilityName: facilityName,
        );
        subtitle = '$facLbl is currently waiting for approval';

      } else if (typeLc == 'booking_deleted' || typeLc == 'deleted_booking') {           // <-- add this block
        final facLbl = _displayFacilityName(
          facilityId: facilityId,
          inboxFacilityName: facilityName,
        );
        subtitle = 'The booked $facLbl have been deleted';

      } else {
        subtitle = 'The ${facilityName.isEmpty ? '-' : facilityName} is booked by $email';
      }



      // ----- read/time -----
      final bool isRead = (m['isRead'] == true);
      String timeLbl = '-';
      final created = _tsToDate(m['createdAt']) ?? _tsToDate(m['submittedAt']); // <-- fallback
      if (created != null) timeLbl = _formatTimeShort(created);

      // ----- chip -----
      children.add(
        _NotifChip(
          title: title,
          subtitle: subtitle,
          timeLabel: timeLbl,
          isRead: isRead,
          onTap: () async {
            setState(() { _selectedNotifId = d.id; _selectedNotifData = m; _loadingRight = true; });
            if (!isRead) await _markAsRead(d.reference);

            final bookingId = _readFirstStr(m, ['bookingId', 'booking_id', 'id', 'bookingID']);
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


  // ---------- RIGHT PANEL ----------
  Widget _buildRightPanel() {
    if (_loadingRight) return const Center(child: CircularProgressIndicator());
    if (_selectedNotifId == null || _selectedNotifData == null) {
      return Center(child: Text('Please select an option', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)));
    }

    final inbox = _selectedNotifData!;
    final booking = _selectedBooking;

    final type = (inbox['type'] ?? '').toString();
    final typeLc = type.toLowerCase();
    final bool isDeleted = typeLc == 'booking_deleted' || typeLc == 'deleted_booking';

    if (type == 'system_issue') {
      final reporterEmail = (inbox['email'] ?? '-').toString();
      final issueTitle = (inbox['title'] ?? inbox['issueTitle'] ?? '-').toString();
      final description = (inbox['message'] ?? inbox['description'] ?? '-').toString();
      final base64Img = (inbox['imageBase64'] ?? '').toString().trim();

      Uint8List? imgBytes;
      if (base64Img.isNotEmpty) {
        try {
          final clean = base64Img.contains(',') ? base64Img.split(',').last : base64Img;
          imgBytes = base64Decode(clean);
        } catch (_) {
          imgBytes = null;
        }
      }

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


    // IDs — prefer Inbox, fallback Booking
    final facilityId = _readFirstStrPrefNotif(inbox, booking, ['facilityId','facilityID','facilityDocId','facility_id']);
    final bookedUid  = _readFirstStrPrefNotif(inbox, booking, ['bookedBy','bookBy']); // end-user (userId)
    final createdUid = _readFirstStrPrefNotif(inbox, booking, ['createdBy','creatorUid','creatorId']); // actor
    final managerUid = _readFirstStrPrefNotif(inbox, booking, ['managerId','managerUID','managerUid']);

    // For deleted bookings: strictly read slot/date/time from INBOX
    final String seat = isDeleted
        ? _readFirstStr(inbox, ['seatIndex','slotNumber','seatNumber','slot','seat'])
        : _readFirstStrPrefNotif(inbox, booking, ['seatIndex','slotNumber','seatNumber','slot','seat']);

    final DateTime? bookDate = isDeleted
        ? _readBookingDate(inbox)
        : _readBookingDatePrefNotif(inbox, booking);

    final DateTime? tStart = isDeleted
        ? _readTime(inbox, ['start','startTime','timeStart'])
        : _readTimePrefNotif(inbox, booking, ['start','startTime','timeStart']);

    final DateTime? tEnd = isDeleted
        ? _readTime(inbox, ['end','endTime','timeEnd'])
        : _readTimePrefNotif(inbox, booking, ['end','endTime','timeEnd']);

    final String dateStr  = (bookDate != null) ? _fmtDDMonYYYY(bookDate) : '';
    final String timeFancy = (tStart != null && tEnd != null)
        ? '${_fmt24WithAmPm(tStart)} - ${_fmt24WithAmPm(tEnd)}'
        : (tStart != null) ? _fmt24WithAmPm(tStart) : '';


    // Use INBOX only. If absent, show "—"
    final reason = _readFirstStr(inbox, ['approvalReason','reason','bookingReason','purpose','notes']);

    final approval = _computeApprovalFromInbox(inbox);


    // NOTE: removed the old ConstrainedBox(maxWidth: 940.w) to let content stretch
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, // name at very top
        children: [
          // ===== Facility Name at the top =====
          _FacilityNameLive(
            facilityId: facilityId,
            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827)),
          ),
          SizedBox(height: 12.h),

          // ===== Row: Image (left) | Summary (right - stretches to end of panel) =====
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FacilityImageSimple(facilityId: facilityId),
              SizedBox(width: 16.w),
              // Everything on the right grows to the end
              Expanded(
                child: _summaryColumn(
                  children: [
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

          // ===== Reason of booking (full width) =====
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

          // ===== Booked by (full width, base64-only photo) =====
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

          // ===== Facility Manager (full width, asset path only) =====
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

          // ===== Approval (from BookingId) =====
          if (isDeleted)
            _summaryLine(icon: Icons.delete_outline, labelLower: 'status', value: 'The booking for this user have been deleted')
          else
            _summaryLine(icon: Icons.verified_outlined, labelLower: 'approval', value: approval),
        ],
      ),
    );
  }

  // ===== Vertical summary (slot/date/time) =====
  Widget _summaryColumn({required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, // stretch children horizontally
      children: [
        for (int i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) SizedBox(height: 8.h),
        ],
      ],
    );
  }

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

  /// Same UI as _summaryLine but value is **email** resolved from uid
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
                  final e = (data['email'] ?? data['userEmail'] ?? data['emailAddress'] ?? '') as String?;
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
  String _titleForType(String? t) {
    final s = t?.toString() ?? '';
    if (s == 'booking_created') return 'New booked facility';
    if (s == 'booking_updated') return 'Booking updated';
    if (s == 'approval_status') return 'Facility Approved'; // <- new
    return 'Message';
  }


}

// ==============================
// Reusable purple box layout
// ==============================
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

// ==============================
// Header (filter + settings + date)
// ==============================
class _LeftHeader extends StatelessWidget {
  const _LeftHeader({
    Key? key,
    required this.onOpenSettings,
    required this.onCycleFilter,
    required this.currentFilter,
    required this.onOpenCalendar,
    required this.dateFilterOn,
    required this.selectedDay,
    required this.formatDate,
  }) : super(key: key);

  final VoidCallback onOpenSettings;
  final VoidCallback onCycleFilter;
  final String currentFilter; // 'none' | 'unread' | 'read'
  final VoidCallback onOpenCalendar;
  final bool dateFilterOn;
  final DateTime selectedDay;
  final String Function(DateTime d) formatDate;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    String tip;
    if (currentFilter == 'unread') { icon = Icons.mark_email_unread; tip = 'Filter: Unread (tap to switch)'; }
    else if (currentFilter == 'read') { icon = Icons.mark_email_read; tip = 'Filter: Read (tap to switch)'; }
    else { icon = Icons.filter_list; tip = 'Filter: All (tap to switch)'; }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Spacer(),
            Tooltip(
              message: tip,
              child: SizedBox(
                width: 36.w,
                height: 36.h,
                child: OutlinedButton(
                  onPressed: onCycleFilter,
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                  child: Icon(icon, size: 18),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            SizedBox(
              width: 36.w,
              height: 36.h,
              child: OutlinedButton(
                onPressed: onOpenSettings,
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                child: const Icon(Icons.settings, size: 18),
              ),
            ),
          ],
        ),
        SizedBox(height: 8.h),
        Row(
          children: [
            Expanded(
              child: Text(dateFilterOn ? formatDate(selectedDay) : 'Just', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)),
            ),
            SizedBox(width: 8.w),
            SizedBox(
              width: 36.w,
              height: 36.h,
              child: OutlinedButton(
                onPressed: onOpenCalendar,
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                child: const Icon(Icons.calendar_today, size: 18),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ==============================
// Notification chip (no overflow)
// ==============================
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

/* ===========================
   Live-resolved facility name
   =========================== */
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

/* ===========================
   Facility image (simple, asset path only)
   =========================== */
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

  Widget _placeholder() => const Center(child: Icon(Icons.image, size: 44, color: Color(0xFF9CA3AF)));
}

/* ===========================
   Person card (User/Manager) — simplified photo logic
   =========================== */
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

        final String name  = _pickFirst(data?['name'], data?['userName'], data?['username']);
        final String email = _pickFirst(data?['email'], data?['userEmail'], data?['emailAddress']);
        final String phone = _pickFirst(data?['contact'], data?['phone'], data?['mobile']);
        final String role  = _pickFirst(data?['role']);

        Uint8List? bytes;
        String? assetPath;

        if (photoMode == _PhotoMode.base64) {
          final String b64 = _pickFirst(data?['profileImageBase64'], data?['imageBase64'], data?['profileImage64']);
          bytes = _tryDecodeBase64(b64);
        } else {
          // asset path only (manager)
          String? p = _pickFirst(data?['profileImagePath'], data?['profileImageName'], data?['imageName']);
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

  Widget _kv(String k, String v) {
    return Row(
      children: [
        Text('$k: ', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
        Expanded(child: Text(v.trim().isEmpty ? '—' : v.trim(), style: TextStyle(fontSize: 12.sp, color: const Color(0xFF111827)), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

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
