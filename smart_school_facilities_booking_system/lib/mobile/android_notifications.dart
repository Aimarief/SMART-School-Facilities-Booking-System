import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'android_notification_details.dart';

import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_list_of_facilities.dart';
import 'android_account.dart';

import 'android_notification_setting.dart';


class AndroidNotifications extends StatefulWidget {
  @override
  State<AndroidNotifications> createState() => _AndroidNotificationsState();
}

class _AndroidNotificationsState extends State<AndroidNotifications> {
  //---------------------------------------
// current index page
//---------------------------------------
  int _currentIndex = 3;

  String _filter = 'none'; // 'none' | 'unread' | 'read'
  bool _dateFilterOn = false;
  DateTime _selectedDay = DateTime.now();


  final Map<String, String> _emailCache = <String, String>{};
  final Set<String> _emailLoading = <String>{};
  final Map<String, String> _facilityNameCache = <String, String>{};
  final Set<String> _facilityLoading = <String>{};

//---------------------------------------
// bottom navigate page
//---------------------------------------
  void _onTabSelected(int i) {
    if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAgenda()));
    } else if (i == 1) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } else if (i == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
    } else if (i == 3) {
      setState(() => _currentIndex = 3);
    } else if (i == 4) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
    }
  }

//---------------------------------------
// get current user id
//---------------------------------------
  String _currentUid() => FirebaseAuth.instance.currentUser?.uid ?? '';

  //---------------------------------------
// get all inbox and decending = true , from earliest to latest
//---------------------------------------
  Stream<QuerySnapshot<Map<String, dynamic>>> _inboxStream() {
    final uid = _currentUid();
    if (uid.isEmpty) {
      return Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    return FirebaseFirestore.instance
        .collection('UserInformation')
        .doc(uid)
        .collection('Inbox')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  //---------------------------------------
// when press filter button it will change
//---------------------------------------
  String _nextFilter(String f) => f == 'none' ? 'unread' : (f == 'unread' ? 'read' : 'none');

  //---------------------------------------
// check if same day
//---------------------------------------
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  //---------------------------------------
// change to date format
//---------------------------------------
  DateTime? _tsToDate(dynamic v) => (v is Timestamp) ? v.toDate() : null;

  //---------------------------------------
// change to ymd format
//---------------------------------------
  String _toYMD(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  //---------------------------------------
// change to day month year format
//---------------------------------------
  String _formatLongDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  //---------------------------------------
// change to having am and pm format
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
// open calender
//---------------------------------------
  Future<void> _openDayPicker() async {
    final today = DateTime.now();
    final first = DateTime(today.year - 1, today.month, today.day);
    final last  = DateTime(today.year + 1, today.month, today.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: first,
      lastDate: last,
      builder: (ctx, child) => child ?? const SizedBox(),
    );
//---------------------------------------
// set state when date is pick
//---------------------------------------
    if (picked != null) {
      setState(() {
        _selectedDay = picked;
        _dateFilterOn = true;
      });
    }
  }
//---------------------------------------
// mark the notifiation as read after open
//---------------------------------------
  Future<void> _markAsRead(DocumentReference<Map<String, dynamic>> ref) async {
    try {
      await ref.update({'isRead': true, 'readAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

//---------------------------------------
// check to make sure the mail is for this user role
//---------------------------------------
  bool _canSee(Map<String, dynamic> m, String uid) {
    if (uid.isEmpty) return false;
    String recipient = (m['recipientId'] ).toString().trim();
    String manager   = (m['managerId'] ).toString().trim();
    String bookedBy  = (m['bookedBy'] ).toString().trim();
    String createdBy = (m['createdBy']  ).toString().trim();
    return recipient == uid || manager == uid || bookedBy == uid || createdBy == uid;
  }

  //---------------------------------------
// save the facility in cached
//---------------------------------------
  Future<void> _ensureFacilityNameCached(String facilityId) async {
    if (facilityId.isEmpty || _facilityNameCache.containsKey(facilityId) || _facilityLoading.contains(facilityId)) return;
    _facilityLoading.add(facilityId);
    try {
      final doc = await FirebaseFirestore.instance.collection('Facilities').doc(facilityId).get();
      final m = doc.data();
      String name = '';
      if (m != null) {
        name = (m['name']).toString().trim();
      }
      _facilityNameCache[facilityId] = name.isEmpty ? facilityId : name;
      if (mounted) setState(() {});
    } catch (_) {
      _facilityNameCache[facilityId] = facilityId;
    } finally {
      _facilityLoading.remove(facilityId);
    }
  }

//---------------------------------------
// save the facility name for mail in cache
//---------------------------------------
  String _facilityNameForMail(Map<String, dynamic> m) {
    final inline = _readFirstStr(m, ['facilityName']);
    if (inline.isNotEmpty) return inline;

    final fid = _readFirstStr(m, ['facilityId']);
    if (fid.isEmpty) return '-';

    final cached = _facilityNameCache[fid];
    if (cached != null && cached.isNotEmpty) return cached;

    _ensureFacilityNameCached(fid);
    return '…';
  }

//---------------------------------------
// filter the mail by read or not read and date then add to list
//---------------------------------------
  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> _groupByDate(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> groups = {};
    final uid = _currentUid();

    for (final d in docs) {
      final m = d.data();
      if (!_canSee(m, uid)) continue;

      final isRead = (m['isRead'] == true);
      if (_filter == 'unread' && isRead) continue;
      if (_filter == 'read' && !isRead) continue;

      final ts = _tsToDate(m['createdAt']);
      if (ts == null) continue;
      if (_dateFilterOn && !_sameDay(ts, _selectedDay)) continue;
//---------------------------------------
// save key (date) and value data
//---------------------------------------

      final key = _toYMD(ts);
      groups.putIfAbsent(key, () => []);
      groups[key]!.add(d);
    }
    return groups;
  }
//---------------------------------------
// sort by date
//---------------------------------------
  List<String> _sortedGroupKeys(Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> g) {
    final keys = g.keys.toList();
    keys.sort((a, b) => a == b ? 0 : (a.compareTo(b) > 0 ? -1 : 1)); // desc by date string
    return keys;
  }

  //---------------------------------------
// fromat date at the header
//---------------------------------------
  Widget _groupHeader(String ymd) {
    DateTime? d;
    try {
      final p = ymd.split('-');
      if (p.length == 3) d = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    } catch (_) {}
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Text(
        d == null ? ymd : _formatLongDate(d),
        style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
      ),
    );
  }

  //---------------------------------------
// chache the email
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

  String _readFirstStr(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      if (m.containsKey(k)) {
        final v = m[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
        if (v != null) return v.toString();
      }
    }
    return '';
  }

//---------------------------------------
// check if the email is amendment mail
//---------------------------------------
  bool _isAmendment(Map<String, dynamic> m) {
    final v = m['isAmendment'] ;
    if (v is bool && v)
      return true;

    final amendId = (m['amendmentId'] ?? '').toString().trim();
    if (amendId.isNotEmpty) return true;

    final mode = ( m['requestType'] ).toString().toLowerCase();
    return mode.contains('amend');
  }


//---------------------------------------
// decide the title for mail
//---------------------------------------
  String _titleForMail(Map<String, dynamic> m) {
    final type = m['type']?.toString() ?? '';

    //---------------------------------------
// if mail type is approval
//---------------------------------------
    if (type == 'approval_status') {
      final rawAppr = (m['approval'] ).toString().toLowerCase();
      final isAccepted = rawAppr.contains('accepted') ;
      final isRejected = rawAppr.contains('rejected');
      final label = isRejected ? 'Rejected' : (isAccepted ? 'Approved' : 'Updated');
      return 'Facility $label';
    }
//---------------------------------------
// if mail type is booking created check if is pending or amendment
//---------------------------------------
    if (type == 'booking_created') {
      final ap = (m['approval'] ?? '').toString().toLowerCase();
      if (ap == 'pending') {
        return _isAmendment(m)
            ? 'Facility pending request (Amendment)'
            : 'Facility pending request';
      }
      return 'Booked Successfully';
    }
//---------------------------------------
// if booking is updated
//---------------------------------------
    if (type == 'booking_updated') {
      // leave “update” titles exactly as you have them
      final ap = (m['approval'] ?? '').toString().toLowerCase();
      if (ap == 'pending') return 'Facility pending request';
      return 'Booking updated';
    }
//---------------------------------------
// for request update facility
//---------------------------------------
    if (type == 'request_update') return 'Action needed';
    //---------------------------------------
// for booking deleted facility
//---------------------------------------
    if (type == 'booking_deleted') return 'Delete Booking';
    return 'Message';
  }
//---------------------------------------
// main build
//---------------------------------------
  @override
  Widget build(BuildContext context) {
    final double barHeight = MediaQuery.of(context).size.height * 0.07;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: Text("Notifications",
              style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(40.r),
              bottomRight: Radius.circular(40.r),
            ),
          ),
        ),
      ),

      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Column(
          children: [
//---------------------------------------
// filter button
//---------------------------------------
            Row(
              children: [
                Tooltip(
                  message: _filter == 'unread'
                      ? 'Filter: Unread (tap to switch)'
                      : _filter == 'read'
                      ? 'Filter: Read (tap to switch)'
                      : 'Filter: All (tap to switch)',
                  child: SizedBox(
                    width: 40.w,
                    height: 40.h,
                    child: OutlinedButton(
                      onPressed: () => setState(() => _filter = _nextFilter(_filter)),
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                      child: Icon(
                        _filter == 'unread'
                            ? Icons.mark_email_unread
                            : _filter == 'read'
                            ? Icons.mark_email_read
                            : Icons.filter_list,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
//---------------------------------------
// navigate to notification settting page
//---------------------------------------
                SizedBox(
                  width: 40.w,
                  height: 40.h,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NotificationSetting()),
                      );
                    },
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Icon(Icons.settings, size: 20),
                  ),
                ),
                const Spacer(),
//---------------------------------------
// display date and date picker
//---------------------------------------
                Text(
                  _dateFilterOn ? _formatLongDate(_selectedDay) : 'All',
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700),
                ),
                SizedBox(width: 8.w),
                SizedBox(
                  width: 40.w,
                  height: 40.h,
                  child: OutlinedButton(
                    onPressed: _openDayPicker,
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    child: const Icon(Icons.calendar_today, size: 20),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.h),
//---------------------------------------
// build the notification list
//---------------------------------------

            Expanded(
              child: _buildList(),
            ),
          ],
        ),
      ),

      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }

  //---------------------------------------
// build the list
//---------------------------------------

  Widget _buildList() {
    final uid = _currentUid();
    if (uid.isEmpty) {
      return Center(child: Text('Please sign in', style: TextStyle(fontSize: 14.sp)));
    }
    //---------------------------------------
// get the inbox of that user from database
//---------------------------------------

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _inboxStream(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Failed to load', style: TextStyle(fontSize: 14.sp)));
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return Center(child: Text('No notifications', style: TextStyle(fontSize: 14.sp)));
        }
//---------------------------------------
// make the filter of inbox by filetr and date
//---------------------------------------

        final groups = _groupByDate(snap.data!.docs);
        if (groups.isEmpty) {
          return Center(child: Text('No notifications', style: TextStyle(fontSize: 14.sp)));
        }
//---------------------------------------
// sort it by date
//---------------------------------------
        final keys = _sortedGroupKeys(groups);
        return ListView.builder(
          itemCount: keys.length,
          itemBuilder: (context, idx) {
            final k = keys[idx];
            final items = groups[k] ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];

            return Padding(
              padding: EdgeInsets.only(bottom: 14.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
//---------------------------------------
// display formated date at top of each date
//---------------------------------------
                  _groupHeader(k),
                  SizedBox(height: 6.h),
//---------------------------------------
// build each notifiacation
//---------------------------------------
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
// build each notification
//---------------------------------------

  List<Widget> _buildChipList(List<QueryDocumentSnapshot<Map<String, dynamic>>> items) {
    final children = <Widget>[];
    for (final d in items) {
      final m = d.data();

//---------------------------------------
// get the title
//---------------------------------------
      String title = _titleForMail(m);

      final String type = m['type']?.toString() ?? '';
      final String facilityName = _readFirstStr(m, ['facilityName']);
//---------------------------------------
// decide the subtitle
//---------------------------------------

      String subtitle;
//---------------------------------------
// for approval type
//---------------------------------------
      if (type == 'approval_status') {
        final rawAppr = (m['approval'] ).toString().toLowerCase();
        final isAccepted = rawAppr.contains('accept');
        final isRejected = rawAppr.contains('reject');
        final verdict = isRejected ? 'rejected' : (isAccepted ? 'accepted' : 'updated');

        subtitle = 'The ${facilityName.isEmpty ? '-' : facilityName} is $verdict';
//---------------------------------------
// for booking created type
//---------------------------------------
      } else if (type == 'booking_created') {
        final ap = (m['approval'] ?? '').toString().toLowerCase();
        if (ap == 'pending') {
          final facLbl = facilityName.isEmpty ? 'Facility' : facilityName;
          subtitle = '$facLbl is currently waiting for approval';
        } else {
          final String bookedUid = _readFirstStr(m, ['bookedBy']);
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
// if its not pending then show
//---------------------------------------
          subtitle = 'The ${facilityName.isEmpty ? '-' : facilityName} is booked by $email';
        }

//---------------------------------------
// if it is booking updated
//---------------------------------------
      } else if (type == 'booking_updated') {
        final ap = (m['approval'] ?? '').toString().toLowerCase();
        if (ap == 'pending') {
          final facLbl = facilityName.isEmpty ? 'Facility' : facilityName;
          subtitle = '$facLbl is currently waiting for approval';
        } else {
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
// if it is not pending
//---------------------------------------
          subtitle = 'The ${facilityName.isEmpty ? '-' : facilityName} is booked by $email';
        }
//---------------------------------------
// if it is calling user to update facility time
//---------------------------------------
      } else if (type == 'request_update') {
        subtitle = 'Your booking facility have been disable. Please update.';

//---------------------------------------
// if the booking is deleted
//---------------------------------------
      } else if (type == 'booking_deleted') {
        final String facName = _facilityNameForMail(m);
        subtitle = 'Your booked ${facName.isEmpty ? '-' : facName} have been deleted';

      } else {
        // default behavior (unchanged)
        final String bookedUid = _readFirstStr(m, ['bookedBy']);
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
        subtitle = 'The ${facilityName.isEmpty ? '-' : facilityName} is booked by $email';
      }

//---------------------------------------
// check if the mail is readed
//---------------------------------------
      final bool isRead = (m['isRead'] == true);
      String timeLbl = '-';
//---------------------------------------
// format the date
//---------------------------------------

      final created = _tsToDate(m['createdAt']);
      if (created != null) {
        final dateLbl = _formatLongDate(created);
        final timeOnly = _formatTimeShort(created);
        timeLbl = '$dateLbl, $timeOnly';
      }

      children.add(
        _NotifChip(
          title: title,
          subtitle: subtitle,
          timeLabel: timeLbl,
          isRead: isRead,
          onTap: () async {
            if (!isRead) await _markAsRead(d.reference);
            final String facilityId = (m['facilityId'] ).toString();
            final String bookingId = (m['bookingId'] ).toString();
            final String inboxDocPath = d.reference.path; // "UserInformation/<uid>/Inbox/<docId>"
            // so it can stream it directly
//---------------------------------------
// when tap navigate to detail page
//---------------------------------------
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AndroidNotificationDetails(
                  inboxId: inboxDocPath,
                  facilityId: facilityId,
                  bookingId: bookingId,
                ),
              ),
            );
          },

        ),
      );
      children.add(SizedBox(height: 8.h));
    }
    return children;
  }
}

//---------------------------------------
// the whole notification design
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
    //---------------------------------------
// set read and not read colour back ground
//---------------------------------------
    const Color unreadBg = Color(0xFFE6D6FF);
    const Color readBg   = Color(0xFFF5ECFF);
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
//---------------------------------------
// display title
//---------------------------------------
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700),
              ),
//---------------------------------------
// display subtitle
//---------------------------------------
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.sp),
              ),
//---------------------------------------
// display time label
//---------------------------------------
              Text(
                timeLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.sp, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
