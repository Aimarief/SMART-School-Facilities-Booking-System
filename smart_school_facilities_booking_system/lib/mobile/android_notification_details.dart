import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_list_of_facilities.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_view_booking.dart';

class AndroidNotificationDetails extends StatefulWidget {
  final String inboxId;       // "UserInformation/<uid>/Inbox/<docId>"
  final String facilityId;    // we use this to read facility image & name
  final String? bookingId;    // optional: prefilled booking doc id

  const AndroidNotificationDetails({
    Key? key,
    required this.inboxId,
    required this.facilityId,
    this.bookingId,
  }) : super(key: key);

  @override
  State<AndroidNotificationDetails> createState() => _AndroidNotificationDetailsState();
}

class _AndroidNotificationDetailsState extends State<AndroidNotificationDetails> {
  //---------------------------------------
// current page
//---------------------------------------

  int _currentIndex = 3;

//---------------------------------------
// navigation page
//---------------------------------------
  void _onTabSelected(int i) {
    // change tab — we keep pattern simple and same across app
    if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAgenda()));
    } else if (i == 1) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } else if (i == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
    } else if (i == 3) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
    } else if (i == 4) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
    }
  }

//---------------------------------------
// format date to full like Mon day month year
//---------------------------------------
  String _formatFullDate(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);

//---------------------------------------
//format time am pm
//---------------------------------------

  String _formatTime12(DateTime d) => DateFormat('h.mm a').format(d).toLowerCase().replaceAll(' ', '\u00A0');

//---------------------------------------
// return date
//---------------------------------------
  DateTime? _readDateOnly(dynamic v) {
    if (v is Timestamp) { final d = v.toDate(); return DateTime(d.year, d.month, d.day); }
    if (v is DateTime)   { return DateTime(v.year, v.month, v.day); }
    if (v is String && v.trim().isNotEmpty) {
      try { final p = DateTime.tryParse(v); if (p != null) return DateTime(p.year, p.month, p.day); } catch (_) {}
      try { final p = DateFormat('yyyy-MM-dd').parseStrict(v); return DateTime(p.year, p.month, p.day); } catch (_) {}
    }
    return null;
  }

//---------------------------------------
// parse time
//---------------------------------------

  List<int>? _parseHM(String s) {
    if (s.isEmpty) return null;
    String t = s.trim().replaceAll(' ', '').replaceAll('.', ':').replaceAll('-', ':');
    if (t.contains(':')) {
      final ps = t.split(':');
      final h = int.tryParse(ps[0]) ?? -1;
      final m = (ps.length > 1 ? int.tryParse(ps[1]) ?? -1 : 0);
      if (h >= 0 && h <= 23 && m >= 0 && m <= 59) return [h, m];
      return null;
    }
  }

  // compose a DateTime from (date-only field) + (time field that could be "HH:mm"/Timestamp)
  DateTime? _composeFromDate(dynamic dateField, dynamic timeField) {
    final ts = (timeField is Timestamp) ? timeField.toDate() : (timeField is DateTime ? timeField : null);
    if (ts != null) return ts;
    final hm = _parseHM(timeField?.toString() ?? '');
    if (hm == null) return null;
    final base = _readDateOnly(dateField) ?? DateTime.now();
    return DateTime(base.year, base.month, base.day, hm[0], hm[1]);
  }

//---------------------------------------
// read approval
//---------------------------------------
  String _approvalFromInbox(Map<String, dynamic> m) {
    final raw = (m['approval'] ?? m['approvalStatus'] ?? m['status'] ?? '').toString().toLowerCase();
    if (raw.contains('accepted')) return 'accepted';
    if (raw.contains('rejected')) return 'rejected';
    if (raw.contains('pending') ) return 'pending';
    return 'pending';
  }

//---------------------------------------
// for approval back ground colour
//---------------------------------------

  Color _approvalBg(String a) {
    switch (a) { case 'accepted': return Colors.green.shade200;
      case 'rejected': return Colors.red.shade200;
      default: return Colors.amber.shade200; }
  }
  //---------------------------------------
// for approval background border
//---------------------------------------
  Color _approvalBorder(String a) {
    switch (a) { case 'accepted': return Colors.green;
      case 'rejected': return Colors.red;
      default: return Colors.amber; }
  }

//---------------------------------------
// get the booking id
//---------------------------------------

  String _pickBookingId(Map<String, dynamic> inbox) {
    final bookid = ['bookingId'];
    for (final k in bookid) {
      final v = inbox[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

//---------------------------------------
// main build
//---------------------------------------
  @override
  Widget build(BuildContext context) {
    final double barHeight = 0.07.sh;

//---------------------------------------
// get the facility info from Facilities
//---------------------------------------

    final facilityStream = FirebaseFirestore.instance
        .collection('Facilities')
        .doc(widget.facilityId)
        .snapshots();

//---------------------------------------
// get inbox information from inbox database
//---------------------------------------

    final inboxStream = FirebaseFirestore.instance
        .doc(widget.inboxId)
        .snapshots();

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white, size: 22.sp),
            onPressed: () {
              // go back / close
              if (Navigator.canPop(context)) Navigator.pop(context);
            },
            tooltip: 'Back',
          ),
          title: Text(
            'Notification Details',
            style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.close, color: Colors.white, size: 22.sp),
              onPressed: () {
                // close page
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
              tooltip: 'Close',
            ),
          ],
        ),
      ),
//---------------------------------------
// get the facility name and image thorough facility id
//---------------------------------------
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: facilityStream,
        builder: (context, facSnap) {
          String facilityName = '';
          String facilityImagePath = '';
          if (facSnap.hasData && facSnap.data!.exists) {
            final fac = facSnap.data!.data()!;
            facilityName = (fac['name']?.toString() ?? '').trim();
            final imgName = (fac['imageName']?.toString().trim() ?? '');
            if (imgName.isNotEmpty) facilityImagePath = 'asset/image/$imgName';
          }

//---------------------------------------
// went into inbox database
//---------------------------------------

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: inboxStream,
            builder: (context, inboxSnap) {
              // handle loading / not found
              if (inboxSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!inboxSnap.hasData || !inboxSnap.data!.exists) {
                return Center(child: Text('Notification not found', style: TextStyle(fontSize: 14.sp)));
              }

              final inbox = inboxSnap.data!.data()!;

//---------------------------------------
// get the type of inbox
//---------------------------------------

              final String inboxType = (inbox['type'] ?? '').toString().trim().toLowerCase();

//---------------------------------------
// get the approval from inbox and get the approval reason
//---------------------------------------
              final approval = _approvalFromInbox(inbox);
              final approvalReason = (inbox['approvalReason'] ?? '').toString().trim();

//---------------------------------------
// also get the booking id
//---------------------------------------
              final effectiveBookingId = (widget.bookingId != null && widget.bookingId!.trim().isNotEmpty)
                  ? widget.bookingId!.trim()
                  : _pickBookingId(inbox);

//---------------------------------------
// image height
//---------------------------------------
              final double imgH = (1.0.sw * 0.75).clamp(240.h, 420.h);

//---------------------------------------
// have all important details
//---------------------------------------
              final bool hasInlineDetails =
                  ((inbox['bookingDate'] ?? '').toString().trim().isNotEmpty) ||
                      ((inbox['start'] ?? '').toString().trim().isNotEmpty) ||
                      ((inbox['end'] ?? '').toString().trim().isNotEmpty) ||
                      (inbox['seatIndex'] != null);

//---------------------------------------
// the content design
//---------------------------------------
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
//---------------------------------------
// facility image
//---------------------------------------
                    Container(
                      width: double.infinity,
                      height: imgH,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16.r),
                        color: Colors.grey.shade300,
                      ),
                      child: facilityImagePath.isEmpty
                          ? Center(child: Icon(Icons.image_not_supported, size: 40.sp, color: Colors.white))
                          : Image.asset(facilityImagePath, fit: BoxFit.cover),
                    ),

                    SizedBox(height: 16.h),

//---------------------------------------
// facility name
//---------------------------------------
                    SizedBox(
                      width: 0.90.sw,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            facilityName,
                            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                          SizedBox(height: 10.h),

//---------------------------------------
// booking summary section, if it have the important details then it will display
//---------------------------------------
                          if (hasInlineDetails || inboxType == 'request_update' || inboxType == 'booking_deleted') ...[ () {
                              final String bookingDateStr = (inbox['bookingDate'] ?? '').toString().trim();
                              final DateTime? bookingDate = _readDateOnly(bookingDateStr);

                              final String label = bookingDate == null
                                  ? (bookingDateStr.isEmpty ? '' : 'Booking Date: $bookingDateStr')
                                  : 'Booking Date: ${_formatFullDate(bookingDate)}';
//---------------------------------------
// display full day date
//---------------------------------------
                              return label.isEmpty
                                  ? const SizedBox()
                                  : Padding(
                                padding: EdgeInsets.only(bottom: 12.h),
                                child: Text(label,
                                    style: TextStyle(fontSize: 14.sp, color: Colors.black87, fontWeight: FontWeight.w600)),
                              );
                            }(),

//---------------------------------------
// get the start time
//---------------------------------------
                                () {
                              String startStr = '--.--';
                              final String rawStart = (inbox['start'] ?? '').toString().trim();
                              final hmS = _parseHM(rawStart);
                              if (hmS != null) {
                                final DateTime base = _readDateOnly(inbox['bookingDate']) ?? DateTime.now();
                                startStr = _formatTime12(DateTime(base.year, base.month, base.day, hmS[0], hmS[1]));
                              } else if (rawStart.isNotEmpty) {
                                startStr = rawStart;
                              }
 //---------------------------------------
// get the end time
//---------------------------------------
                                  String endStr = '--.--';
                              final String rawEnd = (inbox['end'] ?? '').toString().trim();
                              final hmE = _parseHM(rawEnd);
                              if (hmE != null) {
                                final DateTime base = _readDateOnly(inbox['bookingDate']) ?? DateTime.now();
                                endStr = _formatTime12(DateTime(base.year, base.month, base.day, hmE[0], hmE[1]));
                              } else if (rawEnd.isNotEmpty) {
                                endStr = rawEnd;
                              }
//---------------------------------------
// read seat
//---------------------------------------
                              String seatText = '-';
                              final dynamic si = inbox['seatIndex'];
                              if (si != null) seatText = si.toString();

//---------------------------------------
// return the purple time details container
//---------------------------------------
                                  return Container(
                                width: double.infinity,
                                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE9D7FF),
                                  borderRadius: BorderRadius.circular(14.r),
                                  boxShadow: [BoxShadow(color: const Color(0x22000000), blurRadius: 8.r, offset: Offset(0, 3.h))],
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 78.w,
                                      height: 68.h,
                                      child: Stack(
                                        children: [
//---------------------------------------
// show start time
//---------------------------------------
                                          Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              startStr,
                                              maxLines: 1,
                                              overflow: TextOverflow.clip,
                                              style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: Colors.black87),
                                            ),
                                          ),
//---------------------------------------
// something like devider
//---------------------------------------
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text('      |', style: TextStyle(fontSize: 16.sp, color: Colors.black45)),
                                          ),
 //---------------------------------------
// show end time
//---------------------------------------
                                          Align(
                                            alignment: Alignment.bottomLeft,
                                            child: Text(
                                              endStr,
                                              maxLines: 1,
                                              overflow: TextOverflow.clip,
                                              style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: Colors.black54),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
//---------------------------------------
// another devider that devide time and slot
//---------------------------------------
                                    Container(width: 2.w, height: 50.h, margin: EdgeInsets.symmetric(horizontal: 12.w), color: const Color(0xFF7E57C2)),
 //---------------------------------------
// display seat
//---------------------------------------

                                    Expanded(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.event_seat, size: 18.w, color: Colors.black54),
                                          Text('Slot : ', style: TextStyle(fontSize: 13.sp, color: Colors.black87, fontWeight: FontWeight.w600)),
                                          SizedBox(width: 6.w),
                                          Text(seatText, style: TextStyle(fontSize: 13.sp, color: Colors.black87, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }(),
                          ]
                          else ...[
//---------------------------------------
// fall back if no booking referemce for notification ( nearly impossible) since i alrady have soft delete for those id
//---------------------------------------

                              Container(
                                width: double.infinity,
                                padding: EdgeInsets.all(12.w),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3CD),
                                  borderRadius: BorderRadius.circular(12.r),
                                  border: Border.all(color: const Color(0xFFFFEEA3)),
                                ),
                                child: Text(
                                  'No booking reference found for this notification.',
                                  style: TextStyle(fontSize: 13.sp),
                                ),
                              ),
                            ],

                          SizedBox(height: 18.h),

//---------------------------------------
// for request update and booking deleted details
//---------------------------------------
                          if (inboxType == 'request_update' || inboxType == 'booking_deleted') ...[
                            Text('Details', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                            SizedBox(height: 6.h),
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(12.w),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: Text(
                                inboxType == 'request_update'
 //---------------------------------------
// request update text
//---------------------------------------
                                    ? 'The facility your for current booking date ${(inbox['bookingDate'] ?? '').toString()} '
                                    'are disable and require you to change or create a new booking if nessacery.'
//---------------------------------------
// deleted text
//---------------------------------------
                                    : 'Your booking for this facility have beed deleted',
                                style: TextStyle(fontSize: 14.sp),
                              ),
                            ),
                          ] else ...[
//---------------------------------------
// if its normal booking show approval details
//---------------------------------------
                            Text('Approval Details', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                            SizedBox(height: 6.h),
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.all(12.w),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12.r),
                              ),
                              child: Text(approvalReason.isEmpty ? '-' : approvalReason, style: TextStyle(fontSize: 14.sp)),
                            ),
                            SizedBox(height: 18.h),
//---------------------------------------
// approval box
//---------------------------------------
                            Text('Approval', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                            SizedBox(height: 6.h),
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 18.h),
                              decoration: BoxDecoration(
                                color: _approvalBg(approval),
                                borderRadius: BorderRadius.circular(12.r),
                                border: Border.all(color: _approvalBorder(approval), width: 1.w),
                              ),
                              child: Center(
                                child: Text(
                                  approval[0].toUpperCase() + approval.substring(1),
                                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: Colors.black87),
                                ),
                              ),
                            ),
                          ]

                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
//---------------------------------------
// bottom menu for navigation
//---------------------------------------
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}
