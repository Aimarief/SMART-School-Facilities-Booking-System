// lib/android_notification_details.dart
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
  // this page shows a single notification (Inbox doc) in detail
  final String inboxId;       // absolute path: "UserInformation/<uid>/Inbox/<docId>"
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
  int _currentIndex = 3; // bottom bar: Notifications tab

  // ---------------- navigation (basic) ----------------
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

  // --------------------- helpers (format / parse) ---------------------
  // format full date like: Mon, 1 Jan 2025
  String _formatFullDate(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);

  // format time like 9.30 am (with non-breaking space)
  String _formatTime12(DateTime d) => DateFormat('h.mm a').format(d).toLowerCase().replaceAll(' ', '\u00A0');

  // read only the date part (drop time) from several possible types
  DateTime? _readDateOnly(dynamic v) {
    if (v is Timestamp) { final d = v.toDate(); return DateTime(d.year, d.month, d.day); }
    if (v is DateTime)   { return DateTime(v.year, v.month, v.day); }
    if (v is String && v.trim().isNotEmpty) {
      try { final p = DateTime.tryParse(v); if (p != null) return DateTime(p.year, p.month, p.day); } catch (_) {}
      try { final p = DateFormat('yyyy-MM-dd').parseStrict(v); return DateTime(p.year, p.month, p.day); } catch (_) {}
    }
    return null;
  }

  // parse "HH:mm" or loose formats like "930" -> [h,m]
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
    final d = t.replaceAll(RegExp(r'[^0-9]'), '');
    int h = -1, m = -1;
    if (d.length == 4) { h = int.tryParse(d.substring(0, 2)) ?? -1; m = int.tryParse(d.substring(2, 4)) ?? -1; }
    else if (d.length == 3) { h = int.tryParse(d.substring(0, 1)) ?? -1; m = int.tryParse(d.substring(1, 3)) ?? -1; }
    else if (d.length == 2) { h = int.tryParse(d) ?? -1; m = 0; }
    if (h >= 0 && h <= 23 && m >= 0 && m <= 59) return [h, m];
    return null;
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

  // read approval-style word from inbox (kept for other types)
  String _approvalFromInbox(Map<String, dynamic> m) {
    final raw = (m['approval'] ?? m['approvalStatus'] ?? m['status'] ?? '').toString().toLowerCase();
    if (raw.contains('acc') || raw.contains('approv')) return 'accepted';
    if (raw.contains('rej') || raw.contains('declin') || raw.contains('deni')) return 'rejected';
    if (raw.contains('pend') || raw.contains('wait')) return 'pending';
    return 'pending';
  }

  // small colored boxes (kept for other types)
  Color _approvalBg(String a) {
    switch (a) { case 'accepted': return Colors.green.shade200; case 'rejected': return Colors.red.shade200; default: return Colors.amber.shade200; }
  }
  Color _approvalBorder(String a) {
    switch (a) { case 'accepted': return Colors.green; case 'rejected': return Colors.red; default: return Colors.amber; }
  }

  // try to pick a bookingId from inbox fields, if widget.bookingId is null
  String _pickBookingId(Map<String, dynamic> inbox) {
    final cands = ['bookingId', 'booking_id', 'bookingID'];
    for (final k in cands) {
      final v = inbox[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  // --------------------- UI ---------------------
  @override
  Widget build(BuildContext context) {
    final double barHeight = 0.07.sh; // scale bottom bar height by screen height

    // stream for facility (image/name)
    final facilityStream = FirebaseFirestore.instance
        .collection('Facilities')
        .doc(widget.facilityId)
        .snapshots();

    // stream for the inbox doc itself
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

      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: facilityStream,
        builder: (context, facSnap) {
          // read facility name + image from Facilities/{facilityId}
          String facilityName = '';
          String facilityImagePath = '';
          if (facSnap.hasData && facSnap.data!.exists) {
            final fac = facSnap.data!.data()!;
            facilityName = (fac['name']?.toString() ?? '').trim();
            final imgName = (fac['imageName']?.toString().trim() ?? '');
            if (imgName.isNotEmpty) facilityImagePath = 'asset/image/$imgName';
          }

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

              // read inbox map
              final inbox = inboxSnap.data!.data()!;

              // read type so we can branch
              final String inboxType = (inbox['type'] ?? '').toString().trim().toLowerCase();

              // keep old approval flow for other types
              final approval = _approvalFromInbox(inbox);
              final approvalReason = (inbox['approvalReason'] ?? '').toString().trim();

              // bookingId for other types (we still show booking summary by querying)
              final effectiveBookingId = (widget.bookingId != null && widget.bookingId!.trim().isNotEmpty)
                  ? widget.bookingId!.trim()
                  : _pickBookingId(inbox);

              // image height scales with width and clamps nicely for small phones
              final double imgH = (1.0.sw * 0.75).clamp(240.h, 420.h);
              // Prefer the inline fields saved inside this Inbox doc
              final bool hasInlineDetails =
                  ((inbox['bookingDate'] ?? '').toString().trim().isNotEmpty) ||
                      ((inbox['start'] ?? '').toString().trim().isNotEmpty) ||
                      ((inbox['end'] ?? '').toString().trim().isNotEmpty) ||
                      (inbox['seatIndex'] != null);


              // ---------- PAGE ----------
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // -------- facility image --------
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

                    // -------- text area (name + details) --------
                    SizedBox(
                      width: 0.90.sw,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // facility name title
                          Text(
                            facilityName,
                            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                          SizedBox(height: 10.h),

                          // =========================
                          // BOOKING SUMMARY SECTION
                          // =========================
                          // NEW: for request_update we read date/start/end/seat directly from Inbox
                          if (hasInlineDetails || inboxType == 'request_update' || inboxType == 'booking_deleted') ...[
                            // ---- build date line from inbox ----
                                () {
                              final String bookingDateStr = (inbox['bookingDate'] ?? '').toString().trim();
                              final DateTime? bookingDate = _readDateOnly(bookingDateStr);
                              final String label = bookingDate == null
                                  ? (bookingDateStr.isEmpty ? '' : 'Booking Date: $bookingDateStr')
                                  : 'Booking Date: ${_formatFullDate(bookingDate)}';
                              return label.isEmpty
                                  ? const SizedBox()
                                  : Padding(
                                padding: EdgeInsets.only(bottom: 12.h),
                                child: Text(label,
                                    style: TextStyle(fontSize: 14.sp, color: Colors.black87, fontWeight: FontWeight.w600)),
                              );
                            }(),

                            // ---- time + seat card ----
                                () {
                              // start
                              String startStr = '--.--';
                              final String rawStart = (inbox['start'] ?? '').toString().trim();
                              final hmS = _parseHM(rawStart);
                              if (hmS != null) {
                                final DateTime base = _readDateOnly(inbox['bookingDate']) ?? DateTime.now();
                                startStr = _formatTime12(DateTime(base.year, base.month, base.day, hmS[0], hmS[1]));
                              } else if (rawStart.isNotEmpty) {
                                startStr = rawStart;
                              }
                              // end
                              String endStr = '--.--';
                              final String rawEnd = (inbox['end'] ?? '').toString().trim();
                              final hmE = _parseHM(rawEnd);
                              if (hmE != null) {
                                final DateTime base = _readDateOnly(inbox['bookingDate']) ?? DateTime.now();
                                endStr = _formatTime12(DateTime(base.year, base.month, base.day, hmE[0], hmE[1]));
                              } else if (rawEnd.isNotEmpty) {
                                endStr = rawEnd;
                              }
                              // seat
                              String seatText = '-';
                              final dynamic si = inbox['seatIndex'];
                              if (si != null) seatText = si.toString();

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
                                          Align(
                                            alignment: Alignment.topLeft,
                                            child: Text(
                                              startStr,
                                              maxLines: 1,
                                              overflow: TextOverflow.clip,
                                              style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: Colors.black87),
                                            ),
                                          ),
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text('      |', style: TextStyle(fontSize: 16.sp, color: Colors.black45)),
                                          ),
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
                                    Container(width: 2.w, height: 50.h, margin: EdgeInsets.symmetric(horizontal: 12.w), color: const Color(0xFF7E57C2)),
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
                          // OLD flow: other types (booking_created / updated / approval_status)
                          else if (effectiveBookingId.isNotEmpty) ...[
                            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              stream: FirebaseFirestore.instance.collection('Bookings').doc(effectiveBookingId).snapshots(),
                              builder: (context, bookSnap) {
                                String dateLine = '';
                                String startStr = '--.--';
                                String endStr   = '--.--';
                                String seatText = '-';

                                if (bookSnap.hasData && bookSnap.data!.exists) {
                                  final bk = bookSnap.data!.data()!;
                                  final bookingDateField = (bk['bookingDate'] ?? bk['booking_date'] ?? bk['date']);
                                  final bookingDate = _readDateOnly(bookingDateField);
                                  if (bookingDate != null) { dateLine = 'Booking Date: ${_formatFullDate(bookingDate)}'; }

                                  final startDT = _composeFromDate(bookingDateField, bk['start'] ?? bk['startTime']);
                                  final endDT   = _composeFromDate(bookingDateField, bk['end']   ?? bk['endTime']);
                                  if (startDT != null) startStr = _formatTime12(startDT);
                                  if (endDT   != null) endStr   = _formatTime12(endDT);

                                  if (bk['seatIndex'] != null) {
                                    seatText = bk['seatIndex'].toString();
                                  } else if (bk['slotIndex'] != null) {
                                    seatText = bk['slotIndex'].toString();
                                  }
                                }

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (dateLine.isNotEmpty)
                                      Text(dateLine, style: TextStyle(fontSize: 14.sp, color: Colors.black87, fontWeight: FontWeight.w600)),
                                    if (dateLine.isNotEmpty) SizedBox(height: 12.h),
                                    Container(
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
                                                Align(
                                                  alignment: Alignment.topLeft,
                                                  child: Text(startStr, maxLines: 1, overflow: TextOverflow.clip,
                                                      style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: Colors.black87)),
                                                ),
                                                Align(
                                                  alignment: Alignment.centerLeft,
                                                  child: Text('      |', style: TextStyle(fontSize: 16.sp, color: Colors.black45)),
                                                ),
                                                Align(
                                                  alignment: Alignment.bottomLeft,
                                                  child: Text(endStr, maxLines: 1, overflow: TextOverflow.clip,
                                                      style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: Colors.black54)),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(width: 2.w, height: 50.h, margin: EdgeInsets.symmetric(horizontal: 12.w), color: const Color(0xFF7E57C2)),
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
                                    ),
                                  ],
                                );
                              },
                            )
                          ]
                          else ...[
                              // fallback if we cannot find booking id at all
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

                          // =========================
// DETAILS / APPROVAL BLOCK
// =========================
                          if (inboxType == 'request_update' || inboxType == 'booking_deleted') ...[
                            // NEW: For both request_update and booking_deleted we show a simple "Details" box
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
                                // keep your original request_update wording (with bookingDate)
                                    ? 'The facility your for current booking date ${(inbox['bookingDate'] ?? '').toString()} are disable and require you to change or create a new booking if nessacery.'
                                // NEW wording for booking_deleted
                                    : 'Your booking for this facility have beed deleted',
                                style: TextStyle(fontSize: 14.sp),
                              ),
                            ),
                          ] else ...[
                            // keep your previous "Approval Details" + "Approval" boxes for other types
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

      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}
