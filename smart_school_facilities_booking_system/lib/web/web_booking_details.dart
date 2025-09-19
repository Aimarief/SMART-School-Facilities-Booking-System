// web_booking_details.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'web_edit_booking.dart';
import 'package:smart_school_facilities_booking_system/notification_service.dart';
import 'package:smart_school_facilities_booking_system/booking_service.dart';

class WebBookingDetails extends StatelessWidget {
  const WebBookingDetails({
    Key? key,
    required this.booking,
    this.use24HourFormat = false,
  }) : super(key: key);

  final Map<String, dynamic> booking;
  final bool use24HourFormat;


  // Ask for a short reason. If `requiredInput` is true, empty is not allowed.
  Future<String?> _askReasonDialog(
      BuildContext context, {
        required String title,
      }) async {
    final ctrl = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 220),
            child: SizedBox(
              width: 440,
              child: TextFormField(
                controller: ctrl,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 3,          // fixed min height
                maxLines: 6,          // becomes scrollable when longer
                // wraps to next line when hitting the right edge
                decoration: const InputDecoration(
                  hintText: 'Write a short details',
                  // keep hint top-left
                  contentPadding: EdgeInsets.fromLTRB(12, 10, 12, 10),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final raw = ctrl.text.trim();
                final val = raw.isEmpty ? '-' : raw; // empty -> "-"
                Navigator.of(ctx).pop(val);
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }


// Save the reason to Bookings/{bookingId}.statusReason
  Future<void> _saveStatusReason(String bookingId, String? reason) async {
    final r = (reason ?? '').trim();
    if (r.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('Bookings') // <-- change if your collection name differs
        .doc(bookingId)
        .update({'statusReason': r});
  }

  Future<void> _hardDeleteAmendments(String bookingId) async {
    final doc = FirebaseFirestore.instance.collection('Bookings').doc(bookingId);

    Future<void> wipe(String sub) async {
      final col = doc.collection(sub);
      final qs  = await col.get();
      if (qs.docs.isEmpty) return;

      WriteBatch batch = FirebaseFirestore.instance.batch();
      int i = 0;
      for (final d in qs.docs) {
        batch.delete(d.reference);
        i++;
        if (i % 450 == 0) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
        }
      }
      await batch.commit();
    }

    // support both 'amendments' and 'Amendments'
    await wipe('amendments');
    await wipe('Amendments');
  }


  @override
  Widget build(BuildContext context) {
    // IDs only (names are resolved live from other collections)
    final String facilityId = _readFirstStr(booking, ['facilityId','facilityID','facilityDocId','facility_id']);
    final String bookedByUid = _readFirstStr(booking, ['uid','userId','bookedByUid','bookedById','bookedBy']);
    final String managerUid  = _readFirstStr(booking, ['managerId','managerUID','managerUid']);

    // Other booking fields (still read from booking)
    final String seat = _readFirstStr(booking, ['seatIndex','slotNumber','seatNumber','slot','seat']);
    final DateTime? bookDate = _readBookingDate(booking);
    final DateTime? tStart = _readTime(booking, ['start','startTime','timeStart']);
    final DateTime? tEnd   = _readTime(booking, ['end','endTime','timeEnd']);
    final String dateStr   = bookDate != null ? _fmtDDMonYYYY(bookDate) : '';
    final String timeFancy = (tStart != null && tEnd != null)
        ? '${_fmt24WithAmPm(tStart)} - ${_fmt24WithAmPm(tEnd)}'
        : (tStart != null) ? _fmt24WithAmPm(tStart) : '';

    final bool completedAmendment = booking['completeAmendment'] == true;

    // Approval + status (for UI logic)
    final String approvalLc = _readFirstStr(booking, ['approval','approve','approvalStatus']).trim().toLowerCase();
    final String statusLc   = _readFirstStr(booking, ['status','bookingStatus','state']).trim().toLowerCase();
    // --- amendment flags / preview (if any) ---
    final bool hasAmend = booking['hasPendingAmendment'] == true;
    final Map<String, dynamic>? amend = (hasAmend && booking['amendmentPreview'] is Map)
        ? Map<String, dynamic>.from(booking['amendmentPreview'])
        : null;

    final String amendSeat  = (amend?['seatIndex'] ?? '').toString();
    final String amendDate  = (amend?['bookingDate'] ?? '').toString();
    final String amendStart = (amend?['start'] ?? '').toString();
    final String amendEnd   = (amend?['end'] ?? '').toString();
    final String amendTime  = amendStart.isNotEmpty

        ? (amendEnd.isNotEmpty ? '$amendStart - $amendEnd' : amendStart)
        : '';

    // --- ACTION VISIBILITY ---
// Cancel button: only for accepted/approved + upcoming + NO pending amendment
    bool showDelete = statusLc == 'upcoming'
        && (approvalLc == 'accepted' || approvalLc == 'approved')
        && !hasAmend;

// Edit button: only for accepted/approved + upcoming + NO pending amendment + NOT completed before
    bool showEdit = statusLc == 'upcoming'
        && (approvalLc == 'accepted' || approvalLc == 'approved')
        && !hasAmend
        && !completedAmendment;

// When viewing an amendment, show its (new) reason/approvalReason — not the old one.
    final String reason = (hasAmend && amend != null)
        ? _readFirstStr(amend!, ['approvalReason','reason','amendReason','notes'])
        : _readFirstStr(booking, ['approvalReason','reason','bookingReason','purpose','notes']);

    final bool showApproveReject = hasAmend || !(approvalLc == 'accepted' || approvalLc == 'approved' || approvalLc == 'rejected');



    // Booking id (id-only booking logic kept intact)
    final String bookingId = _readFirstStr(booking, ['bookingId','booking_id','id','docId','bookingID','__id']);



    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 940.w),
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ===== Top header row: image (left) | summary (right) =====
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _FacilityImageSmart(facilityId: facilityId),
                SizedBox(width: 16.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Facility name (LIVE)
                      _FacilityNameLive(
                        facilityId: facilityId,
                        style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827)),
                      ),
                      SizedBox(height: 12.h),

                      // Vertical summary list: slot, date, time
                      _summaryColumn(
                        children: [
                          _summaryLine(icon: Icons.event_seat, labelLower: 'slot', value: seat),
                          _summaryLine(icon: Icons.calendar_today_outlined, labelLower: 'date', value: dateStr),
                          _summaryLine(icon: Icons.schedule, labelLower: 'time', value: timeFancy),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),

            if (hasAmend && amend != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Amendment request',
                    style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: const Color(0xFF6B7280))),
              ),
              SizedBox(height: 6.h),
              _summaryColumn(
                children: [
                  if (amendSeat.isNotEmpty) _summaryLine(icon: Icons.event_seat, labelLower: 'new slot', value: amendSeat),
                  if (amendDate.isNotEmpty) _summaryLine(icon: Icons.calendar_today_outlined, labelLower: 'new date', value: amendDate),
                  if (amendTime.isNotEmpty) _summaryLine(icon: Icons.schedule, labelLower: 'new time', value: amendTime),
                ],
              ),
              SizedBox(height: 16.h),
            ],

            SizedBox(height: 16.h),

            // ===== Reason of booking =====
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Reason of booking', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
            ),
            SizedBox(height: 6.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              // keep fallback ONLY here
              child: Text(reason.isEmpty ? '—' : reason, style: TextStyle(fontSize: 13.sp, color: const Color(0xFF111827))),
            ),

            SizedBox(height: 16.h),

            // ===== Booked by (LIVE from UserInformation/{uid}) =====
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Booked by', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
            ),
            SizedBox(height: 8.h),
            _PersonCard.fromUid(
              uid: bookedByUid,
              fillColor: const Color(0xFFE2CCFF),
              showStatusFromRole: true,
              photoMode: _PhotoMode.base64,
            ),

            SizedBox(height: 14.h),

            // ===== Facility Manager (LIVE from UserInformation/{uid}) =====
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Facility Manager', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
            ),
            SizedBox(height: 8.h),
            _PersonCard.fromUid(
              uid: managerUid,
              fillColor: const Color(0xFFE2CCFF),
              showStatusFromRole: false,
              photoMode: _PhotoMode.asset,
            ),

            SizedBox(height: 18.h),
            const Divider(height: 1),
            SizedBox(height: 12.h),

            // ===== Bottom actions (UNCHANGED BOOKING LOGIC) =====
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (showApproveReject)
                  Wrap(
                    spacing: 8.w,
                    runSpacing: 8.h,
                    children: [
                      _pillButton(
                        label: 'Approve',
                        icon: Icons.check,
                        background: const Color(0xFF10B981),
                        foreground: Colors.white,
                        onPressed: () => hasAmend
                            ? _onApproveAmendment(context, bookingId: bookingId)
                            : _onApprove(context, bookingId: bookingId),
                      ),
                      _pillButton(
                        label: 'Reject',
                        icon: Icons.close,
                        background: const Color(0xFFEF4444),
                        foreground: Colors.white,
                        onPressed: () => hasAmend
                            ? _onRejectAmendment(context, bookingId: bookingId)
                            : _onReject(context, bookingId: bookingId),
                      ),
                    ],
                  )
                else
                  (approvalLc == 'rejected' ? _approvalRejectedBadge() : _statusBadge(statusLc)),

                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  alignment: WrapAlignment.end,
                  children: [
                    if (showEdit)
                      _outlineButton(
                        label: 'Edit',
                        icon: Icons.edit_outlined,
                        border: const Color(0xFF3B82F6),
                        foreground: const Color(0xFF1D4ED8),
                        onPressed: () async {
                          // ----- prepare strings we need to pass to the edit popup -----
                          String ymd = '';
                          if (bookDate != null) {
                            final String y = bookDate.year.toString().padLeft(4, '0');
                            final String m = bookDate.month.toString().padLeft(2, '0');
                            final String d = bookDate.day.toString().padLeft(2, '0');
                            ymd = y + '-' + m + '-' + d;
                          }

                          String startStr = '';
                          String endStr = '';
                          if (tStart != null) {
                            startStr = _fmt24WithAmPm(tStart);
                          }
                          if (tEnd != null) {
                            endStr = _fmt24WithAmPm(tEnd);
                          }

                          // ----- 1) close the DETAILS popup -----
                          Navigator.of(context).pop();

                          String owner = '-';                                // default so it never crashes
                          if (booking['userId'] != null &&
                              booking['userId'].toString().trim().isNotEmpty) {
                            owner = booking['userId'].toString().trim();     // most common key
                          } else if (booking['uid'] != null &&
                              booking['uid'].toString().trim().isNotEmpty) {
                            owner = booking['uid'].toString().trim();        // alternate key
                          } else if (booking['ownerId'] != null &&
                              booking['ownerId'].toString().trim().isNotEmpty) {
                            owner = booking['ownerId'].toString().trim();    // another possible key
                          } else if (bookedByUid.trim().isNotEmpty) {
                            owner = bookedByUid.trim();                      // fallback to actor who created
                          }

                          // ----- 2) open the EDIT popup (this looks like the popup "changes" to Edit) -----
                          await openWebEditBookingDialog(
                            context: context,
                            booking: booking,                // raw map so we can reopen details later
                            bookingId: bookingId,
                            facilityId: facilityId,
                            bookedByUid: bookedByUid,
                            managerUid: managerUid,
                            userUid: owner,
                            dateYMD: ymd,
                            timeStart: startStr,
                            timeEnd: endStr,
                            seatIndex: seat,
                            approval: approvalLc,
                            status: statusLc,
                            use24HourFormat: use24HourFormat,
                          );
                        },


                      ),
                    if (showDelete)
                      _pillButton(
                        label: 'Cancel',
                        icon: Icons.delete_outline,
                        background: const Color(0xFFFFE4E6),
                        foreground: const Color(0xFFB91C1C),
                        onPressed: () async {
                          final ok = await _confirmDeleteBooking(context);
                          if (ok) {
                            await _onDeleteAccepted(context, bookingId: bookingId);
                          }
                        },

                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- ACTION HANDLERS (id-only) ----------
  Future<void> _onApprove(BuildContext context, {required String bookingId}) async {
    if (bookingId.isEmpty) {
      _toast(context, 'Missing booking id to approve.');
      return;
    }

    final reason = await _askReasonDialog(context, title: 'Approve booking');
    if (reason == null) return;

    final ok = await _busy(context, () async {
      // 1) update booking + store reason
      await BookingService.approveBookingByIdTx(bookingId: bookingId);
      await _saveStatusReason(bookingId, reason);

      // 2) send approval mail (type: approval_status)
      final String facilityId = _readFirstStr(booking, ['facilityId','facilityID','facilityDocId','facility_id']);
      final String userId     = _readFirstStr(booking, ['uid','userId','bookedByUid','bookedById','bookedBy']);
      final String managerId  = _readFirstStr(booking, ['managerId','managerUID','managerUid']);
      final String actor      = FirebaseAuth.instance.currentUser?.uid ?? '-';
      final String seatRawA = _readFirstStr(booking, ['seatIndex','slotNumber','seatNumber','slot','seat']);
      final int seatIndexA  = int.tryParse(seatRawA) ?? -1;

      String startA = _readFirstStr(booking, ['start','startTime','timeStart']);
      String endA   = _readFirstStr(booking, ['end','endTime','timeEnd']);
      final DateTime? tStartA = _readTime(booking, ['start','startTime','timeStart']);
      final DateTime? tEndA   = _readTime(booking, ['end','endTime','timeEnd']);
      if (startA.isEmpty && tStartA != null) startA = _fmtHHmm(tStartA);
      if (endA.isEmpty   && tEndA   != null) endA   = _fmtHHmm(tEndA);

      String bookingDateA = _readFirstStr(booking, ['bookingDate','date','bookDate','day']);
      final DateTime? bookDateA = _readBookingDate(booking);
      if (bookingDateA.trim().isEmpty && bookDateA != null) bookingDateA = _toYMD(bookDateA);

      await NotificationService.sendBookingApprovalMails(
        bookingId: bookingId,
        userId: userId,
        bookedBy: actor,
        facilityId: facilityId,
        managerId: managerId,
        approval: 'accepted',
        approvalReason: reason,
        // NEW ↓↓↓
        seatIndex: seatIndexA,
        bookingDate: bookingDateA,
        start: startA,
        end: endA,
      );

    });

    if (!ok) return;
    _toast(context, 'Booking approved.');
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _onReject(BuildContext context, {required String bookingId}) async {
    if (bookingId.isEmpty) {
      _toast(context, 'Missing booking id to reject.');
      return;
    }

    final reason = await _askReasonDialog(context, title: 'Reject booking');
    if (reason == null) return;

    final ok = await _busy(context, () async {
      // 1) update booking + store reason
      await BookingService.rejectBookingByIdSimple(bookingId: bookingId);
      await _saveStatusReason(bookingId, reason);

      // 2) send approval mail (type: approval_status)
      final String facilityId = _readFirstStr(booking, ['facilityId','facilityID','facilityDocId','facility_id']);
      final String userId     = _readFirstStr(booking, ['uid','userId','bookedByUid','bookedById','bookedBy']);
      final String managerId  = _readFirstStr(booking, ['managerId','managerUID','managerUid']);
      final String actor      = FirebaseAuth.instance.currentUser?.uid ?? '-';
      final String seatRawR = _readFirstStr(booking, ['seatIndex','slotNumber','seatNumber','slot','seat']);
      final int seatIndexR  = int.tryParse(seatRawR) ?? -1;

      String startR = _readFirstStr(booking, ['start','startTime','timeStart']);
      String endR   = _readFirstStr(booking, ['end','endTime','timeEnd']);
      final DateTime? tStartR = _readTime(booking, ['start','startTime','timeStart']);
      final DateTime? tEndR   = _readTime(booking, ['end','endTime','timeEnd']);
      if (startR.isEmpty && tStartR != null) startR = _fmtHHmm(tStartR);
      if (endR.isEmpty   && tEndR   != null) endR   = _fmtHHmm(tEndR);

      String bookingDateR = _readFirstStr(booking, ['bookingDate','date','bookDate','day']);
      final DateTime? bookDateR = _readBookingDate(booking);
      if (bookingDateR.trim().isEmpty && bookDateR != null) bookingDateR = _toYMD(bookDateR);


      await NotificationService.sendBookingApprovalMails(
        bookingId: bookingId,
        userId: userId,
        bookedBy: actor,
        facilityId: facilityId,
        managerId: managerId,
        approval: 'rejected',
        approvalReason: reason,
        // NEW ↓↓↓
        seatIndex: seatIndexR,
        bookingDate: bookingDateR,
        start: startR,
        end: endR,
      );

    });

    if (!ok) return;
    _toast(context, 'Booking rejected.');
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _onApproveAmendment(BuildContext context, {required String bookingId}) async {
    if (bookingId.isEmpty) {
      _toast(context, 'Missing booking id to approve amendment.');
      return;
    }

    final reason = await _askReasonDialog(context, title: 'Approve amendment');
    if (reason == null) return;

    // helper for safe YMD
    String _toYMDLocal(dynamic v) {
      if (v == null) return '';
      if (v is Timestamp) {
        final d = v.toDate();
        return '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
      }
      if (v is DateTime) {
        return '${v.year.toString().padLeft(4,'0')}-${v.month.toString().padLeft(2,'0')}-${v.day.toString().padLeft(2,'0')}';
      }
      final s = v.toString().trim();
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return s; // already Y-M-D
      // try DD/MM/YYYY
      try {
        final p = s.split('/');
        if (p.length == 3) {
          final d = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
          return '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
        }
      } catch (_) {}
      return s; // last resort
    }

    String _slotKeyFromStart(dynamic raw) {
      final s = (raw ?? '').toString();
      // keep only digits (handles "09:30", "0930", "09.30 am")
      final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 4) return digits.substring(0, 4);
      return digits.padLeft(4, '0');
    }

    final ok = await _busy(context, () async {
      final docRef = FirebaseFirestore.instance.collection('Bookings').doc(bookingId);
      final snap   = await docRef.get();
      final data   = snap.data() as Map<String, dynamic>? ?? {};

      // live booking (old/current values)
      final String oldFacilityId = (data['facilityId'] ?? data['facilityID'] ?? data['facilityDocId'] ?? data['facility_id'] ?? '').toString().trim();
      final String oldDateYMD    = _toYMDLocal(data['bookingDate'] ?? data['date'] ?? data['day']);
      final String oldSlotKey    = _slotKeyFromStart(data['slotKey'] ?? data['start'] ?? '');
      final int oldSeatIndex     = int.tryParse('${data['seatIndex'] ?? data['seat'] ?? data['seatNumber'] ?? ''}') ?? -1;

      // amendment preview (new values)
      final Map<String, dynamic> ap = (data['amendmentPreview'] is Map)
          ? Map<String, dynamic>.from(data['amendmentPreview'])
          : const {};

      // if no amendment payload, just clear flags and bail
      if (ap.isEmpty) {
        await docRef.update({
          'hasPendingAmendment': false,
          'amendmentPreview': FieldValue.delete(),
          'lastActivityAt': FieldValue.serverTimestamp(),
        });
        return;
      }

      final String newFacilityId = (ap['facilityId'] ?? ap['facilityID'] ?? ap['facilityDocId'] ?? ap['facility_id'] ?? oldFacilityId).toString().trim();
      final String newDateYMD    = _toYMDLocal(ap['bookingDate'] ?? oldDateYMD);
      final String newSlotKey    = (ap['slotKey'] != null && ap['slotKey'].toString().trim().isNotEmpty)
          ? ap['slotKey'].toString().trim()
          : _slotKeyFromStart(ap['start'] ?? oldSlotKey);
      final int newSeatIndex     = int.tryParse('${ap['seatIndex'] ?? ''}') ?? (oldSeatIndex > 0 ? oldSeatIndex : 1);
      final String? newStartStr  = (ap['start']?.toString().trim().isNotEmpty ?? false) ? ap['start'].toString().trim() : null;
      final String? newEndStr    = (ap['end']?.toString().trim().isNotEmpty ?? false) ? ap['end'].toString().trim() : null;

      // 1) Move like pending->approved would, but for an already accepted booking:
      //    - free old seat / decrement old slot if slot changed
      //    - take new seat / increment new slot
      //    - update booking fields (facilityId, bookingDate, slotKey, seatIndex, start/end)
      await BookingService.moveAcceptedBookingByIdTx(
        bookingId: bookingId,
        newFacilityId: newFacilityId,
        newDateYMD: newDateYMD,
        newSlotKey: newSlotKey,
        newSeatIndex: newSeatIndex,
        newStartStr: newStartStr,
        newEndStr: newEndStr,
      );

      // 2) Clear amendment flags on the booking AND mark completed
      await docRef.update({
        'hasPendingAmendment': false,
        'amendmentPreview': FieldValue.delete(),
        'completeAmendment': true,                // <-- NEW: lock future amendments
        'lastActivityAt': FieldValue.serverTimestamp(),
      });


      // 3) Notify exactly like pending approval (accepted)
      final String facilityId = newFacilityId.isNotEmpty ? newFacilityId
          : (oldFacilityId);
      final String userId     = _readFirstStr(data, ['uid','userId','bookedByUid','bookedById','bookedBy']);
      final String managerId  = _readFirstStr(data, ['managerId','managerUID','managerUid']);
      final String actor      = FirebaseAuth.instance.currentUser?.uid ?? '-';
      String _hmFromSlotKey(String key) =>
          (key.length >= 4) ? '${key.substring(0,2)}:${key.substring(2,4)}' : key;

// Prefer explicit strings from amendment; else derive from slotKey; else fall back to old booking times
      String startAm = (newStartStr != null && newStartStr.trim().isNotEmpty)
          ? newStartStr.trim()
          : _hmFromSlotKey(newSlotKey);

      String endAm = (newEndStr != null && newEndStr.trim().isNotEmpty)
          ? newEndStr.trim()
          : _readFirstStr(data, ['end','endTime','timeEnd']);  // fallback

      if (endAm.isEmpty) {
        final DateTime? tEnd0 = _readTime(data, ['end','endTime','timeEnd']);
        if (tEnd0 != null) endAm = _fmtHHmm(tEnd0);
      }

      await NotificationService.sendBookingApprovalMails(
        bookingId: bookingId,
        userId: userId,
        bookedBy: actor,
        facilityId: facilityId,
        managerId: managerId,
        approval: 'accepted',
        approvalReason: 'Amendment approved. ${reason.trim()}',
        // NEW ↓↓↓
        seatIndex: newSeatIndex,
        bookingDate: newDateYMD,      // already "YYYY-MM-DD"
        start: startAm,
        end: endAm,
      );


      // 4) Persist status reason (for audit trail)
      await _saveStatusReason(bookingId, 'Amendment approved: ${reason.trim()}');

      // 5) HARD delete amendments subcollection (any casing)
      await _hardDeleteAmendments(bookingId);
    });

    if (!ok) return;
    _toast(context, 'Amendment approved.');
    if (context.mounted) Navigator.of(context).pop();
  }


  Future<void> _onRejectAmendment(BuildContext context, {required String bookingId}) async {
    if (bookingId.isEmpty) {
      _toast(context, 'Missing booking id to reject amendment.');
      return;
    }

    final reason = await _askReasonDialog(context, title: 'Reject amendment');
    if (reason == null) return;

    final ok = await _busy(context, () async {
      final docRef = FirebaseFirestore.instance.collection('Bookings').doc(bookingId);

      await FirebaseFirestore.instance.runTransaction((tx) async {
        tx.update(docRef, {
          'hasPendingAmendment': false,
          'amendmentPreview': FieldValue.delete(),
          'completeAmendment': true,              // <-- NEW: lock future amendments
          'lastActivityAt': FieldValue.serverTimestamp(),
        });
      });


      // notify (reuse existing mail; note decision in reason)
      final String facilityId = _readFirstStr(booking, ['facilityId','facilityID','facilityDocId','facility_id']);
      final String userId     = _readFirstStr(booking, ['uid','userId','bookedByUid','bookedById','bookedBy']);
      final String managerId  = _readFirstStr(booking, ['managerId','managerUID','managerUid']);
      final String actor      = FirebaseAuth.instance.currentUser?.uid ?? '-';
      final String seatRawAR = _readFirstStr(booking, ['seatIndex','slotNumber','seatNumber','slot','seat']);
      final int seatIndexAR  = int.tryParse(seatRawAR) ?? -1;

      String startAR = _readFirstStr(booking, ['start','startTime','timeStart']);
      String endAR   = _readFirstStr(booking, ['end','endTime','timeEnd']);
      final DateTime? tStartAR = _readTime(booking, ['start','startTime','timeStart']);
      final DateTime? tEndAR   = _readTime(booking, ['end','endTime','timeEnd']);
      if (startAR.isEmpty && tStartAR != null) startAR = _fmtHHmm(tStartAR);
      if (endAR.isEmpty   && tEndAR   != null) endAR   = _fmtHHmm(tEndAR);

      String bookingDateAR = _readFirstStr(booking, ['bookingDate','date','bookDate','day']);
      final DateTime? bookDateAR = _readBookingDate(booking);
      if (bookingDateAR.trim().isEmpty && bookDateAR != null) bookingDateAR = _toYMD(bookDateAR);


      await NotificationService.sendBookingApprovalMails(
        bookingId: bookingId,
        userId: userId,
        bookedBy: actor,
        facilityId: facilityId,
        managerId: managerId,
        approval: 'rejected', // amendment rejected
        approvalReason: 'Amendment rejected. ${reason.trim()}',
        seatIndex: seatIndexAR,
        bookingDate: bookingDateAR,
        start: startAR,
        end: endAR,
      );


      await _saveStatusReason(bookingId, 'Amendment rejected: ${reason.trim()}');
      await _hardDeleteAmendments(bookingId);

    });

    if (!ok) return;
    _toast(context, 'Amendment rejected.');
    if (context.mounted) Navigator.of(context).pop();
  }

  Future<bool> _confirmDeleteBooking(BuildContext context) async {
    final bool? res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        title: Text(
          'Cancel booking?',
          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to cancel this booking?',
          style: TextStyle(fontSize: 14.sp),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF0707),
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            ),
            child: Text('Confirm', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return res ?? false;
  }


  Future<void> _onDeleteAccepted(BuildContext context, {required String bookingId}) async {
    if (bookingId.isEmpty) {
      _toast(context, 'Missing booking id to cancel.');
      return;
    }

    // pull IDs straight from the booking map
    final String facilityId = _readFirstStr(booking, ['facilityId','facilityID','facilityDocId','facility_id']);
    final String userId     = _readFirstStr(booking, ['uid','userId','bookedByUid','bookedById','bookedBy']);
    final String managerId  = _readFirstStr(booking, ['managerId','managerUID','managerUid']);
    final String actor      = FirebaseAuth.instance.currentUser?.uid ?? '';

    // slot/seat (try to parse to int, default to -1 if not numeric)
    final String seatRaw = _readFirstStr(booking, ['seatIndex','slotNumber','seatNumber','slot','seat']);
    final int seatIndex  = int.tryParse(seatRaw) ?? -1;

    // start/end time: prefer raw strings; if missing, format from DateTime
    String startStr = _readFirstStr(booking, ['start','startTime','timeStart']);
    String endStr   = _readFirstStr(booking, ['end','endTime','timeEnd']);
    final DateTime? tStart = _readTime(booking, ['start','startTime','timeStart']);
    final DateTime? tEnd   = _readTime(booking, ['end','endTime','timeEnd']);
    if (startStr.isEmpty && tStart != null) startStr = _fmtHHmm(tStart);
    if (endStr.isEmpty && tEnd != null)     endStr   = _fmtHHmm(tEnd);

    // booking date as YYYY-MM-DD
    final DateTime? d = _readBookingDate(booking);
    String bookingDate = _readFirstStr(booking, ['bookingDate','date','bookDate','day']);
    if ((bookingDate.trim().isEmpty) && d != null) {
      bookingDate =
      '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
    }

    final ok = await _busy(context, () async {
      // 1) delete it
      await BookingService.deleteAcceptedBookingByIdTx(bookingId: bookingId);

      // 2) notify user, manager, and actor
      await NotificationService.sendBookingDeletedMails(
        bookingId: bookingId,
        userId: userId,
        bookedBy: actor,      // who performed the deletion
        facilityId: facilityId,
        managerId: managerId,
        seatIndex: seatIndex,
        start: startStr,
        end: endStr,
        bookingDate: bookingDate,
      );
    });

    if (!ok) return;
    _toast(context, 'Booking Canceled.');
    if (context.mounted) Navigator.of(context).pop();
  }


// 1) Make _busy return success/failure
  Future<bool> _busy(BuildContext context, Future<void> Function() task) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await task();
      return true; // <-- success
    } catch (e) {
      _toast(context, _niceError(e));
      return false; // <-- failed
    } finally {
      if (context.mounted) Navigator.of(context).pop();
    }
  }



// 3) Friendlier error mapping (covers Firestore conflicts too)
  String _niceError(Object e) {
    final s = e.toString();

    // direct messages from your service
    if (s.contains('Slot is full') ||
        s.contains('Seat already taken') ||
        s.contains('No free seat found')) {
      return 'This slot is taken.';
    }

    // Firestore transaction/contention messages that occur when the slot just got taken
    if (s.contains('ABORTED') ||
        s.contains('FAILED_PRECONDITION') ||
        s.contains('has been modified') ||
        s.contains('document version') ||
        s.contains('requires all reads to be before writes') ||
        s.contains('Transaction') && s.contains('conflict')) {
      return 'This slot is taken.';
    }

    if (s.contains('Seat index out of range')) {
      return 'That seat is not available for this slot.';
    }
    if (s.contains('Booking already processed')) {
      return 'This booking was already processed.';
    }
    if (s.contains('Booking not found')) {
      return 'Booking not found.';
    }

    return 'Slot is taken';
  }



  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------- tiny styled buttons ----------
  Widget _pillButton({
    required String label,
    required IconData icon,
    required Color background,
    required Color foreground,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: background,
        foregroundColor: foreground,
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
    );
  }

  Widget _outlineButton({
    required String label,
    required IconData icon,
    required Color border,
    required Color foreground,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        side: BorderSide(color: border),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600)),
    );
  }

  // ===== Vertical summary (slot/date/time) =====
  Widget _summaryColumn({required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
          Text('${labelLower.toLowerCase()}: ',
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: const Color(0xFF111827))),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 12.sp, color: const Color(0xFF111827)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ---------- status / approval badges ----------
  Widget _approvalRejectedBadge() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('Rejected',
          style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }

  Widget _statusBadge(String statusLc) {
    String label;
    Color bg;
    Color fg = Colors.white;

    switch (statusLc) {
      case 'upcoming':
        label = 'Upcoming'; bg = const Color(0xFF10B981); break;
      case 'ongoing':
        label = 'Ongoing'; bg = const Color(0xFFF59E0B); break;
      case 'ended':
        label = 'Ended';   bg = const Color(0xFF9CA3AF); break;
      default:
        label = '-';       bg = const Color(0xFF9CA3AF); break;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: fg)),
    );
  }

  // ---------- parsing/formatting ----------
  // put these inside class WebBookingDetails, with the other static helpers
  static String _fmtHHmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  static String _toYMD(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _readBookingDate(Map<String, dynamic> m) {
    for (final k in ['bookingDate','date','bookDate','day']) {
      if (m.containsKey(k)) {
        final v = m[k];
        if (v is Timestamp) return v.toDate();
        if (v is DateTime) return v;
        if (v is String) {
          final d1 = _tryParseYMD(v);
          if (d1 != null) return d1;
          final d2 = _tryParseDMY(v);
          if (d2 != null) return d2;
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
          final t1 = _tryParseHMS(v);
          if (t1 != null) return t1;
          final t2 = _tryParseHM(v);
          if (t2 != null) return t2;
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

  static String _fmtDDMonYYYY(DateTime d) {
    const months = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    final day = d.day.toString().padLeft(2, '0');
    return '$day ${months[d.month - 1]} ${d.year}';
  }

  // "HH.mm am/pm" (e.g., "14.00 pm")
  static String _fmt24WithAmPm(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    final ampm = (d.hour >= 12) ? 'pm' : 'am';
    return '$hh.$mm $ampm';
  }

  static DateTime? _tryParseYMD(String s) {
    try {
      final p = s.split('-');
      if (p.length == 3) return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    } catch (_) {}
    return null;
  }

  static DateTime? _tryParseDMY(String s) {
    try {
      final p = s.split('/');
      if (p.length == 3) return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
    } catch (_) {}
    return null;
  }

  static DateTime? _tryParseHMS(String s) {
    try {
      final p = s.split(':');
      if (p.length == 3) {
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
      }
    } catch (_) {}
    return null;
  }

  static DateTime? _tryParseHM(String s) {
    try {
      final p = s.split(':');
      if (p.length == 2) {
        final now = DateTime.now();
        return DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
      }
    } catch (_) {}
    return null;
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
    if (facilityId.isEmpty) {
      return Text('', style: style, overflow: overflow);
    }
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
   Facility image (by facilityId) — stable & simple
   =========================== */
class _FacilityImageSmart extends StatelessWidget {
  const _FacilityImageSmart({
    Key? key,
    required this.facilityId,
  }) : super(key: key);

  final String facilityId;

  Future<_ImageSrc?> _resolve() async {
    if (facilityId.isEmpty) return null;

    final snap = await FirebaseFirestore.instance
        .collection('Facilities')
        .doc(facilityId)
        .get();

    final data = snap.data();
    if (data == null) return null;

    final imagePath = (data['imagePath'] as String?)?.trim() ?? '';
    if (imagePath.isNotEmpty) {
      return _ImageSrc.asset(imagePath);
    }

    final imageName = (data['imageName'] as String?)?.trim() ?? '';
    if (imageName.isNotEmpty) {
      return _ImageSrc.asset('asset/image/$imageName');
    }

    final url = (data['imageUrl'] as String?)?.trim() ?? '';
    if (url.startsWith('http')) {
      return _ImageSrc.network(url);
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final double size = 200.w.clamp(150.0, 240.0);
    return FutureBuilder<_ImageSrc?>(
      future: _resolve(),
      builder: (context, snap) {
        final src = snap.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(12.r),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E7EB)),
              color: const Color(0xFFF9FAFB),
            ),
            child: _buildImage(src),
          ),
        );
      },
    );
  }

  Widget _buildImage(_ImageSrc? src) {
    if (src == null) return _placeholder();

    if (src.isAsset) {
      return Image.asset(
        src.assetPath!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    if (src.isNetwork) {
      return Image.network(
        src.url!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    return _placeholder();
  }

  Widget _placeholder() =>
      const Center(child: Icon(Icons.image, size: 44, color: Color(0xFF9CA3AF)));
}

/* ===========================
   Simple image source holder
   =========================== */
class _ImageSrc {
  final String? assetPath;
  final String? url;

  const _ImageSrc._({this.assetPath, this.url});

  factory _ImageSrc.asset(String path) => _ImageSrc._(assetPath: path);
  factory _ImageSrc.network(String url) => _ImageSrc._(url: url);

  bool get isAsset => assetPath != null && assetPath!.isNotEmpty;
  bool get isNetwork => url != null && url!.isNotEmpty;
}

/* ===========================
   Person card (User/Manager) — LIVE from UserInformation/{uid}
   =========================== */
enum _PhotoMode { auto, base64, asset, network }

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
    this.assetName,
    this.url,
  }) : super(key: key);

  // Factory: load from UserInformation with uid
  static Widget fromUid({
    required String uid,
    required Color fillColor,
    required bool showStatusFromRole,
    _PhotoMode photoMode = _PhotoMode.auto,
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
        final String email = _pickFirst(data?['email'], data?['userEmail']);
        final String phone = _pickFirst(data?['contact'], data?['phone'], data?['mobile']);
        final String role  = _pickFirst(data?['role']);

        // Photo fields
        final String b64       = _pickFirst(data?['profileImageBase64'], data?['imageBase64'], data?['profileImage64']);
        final String nameAsset = _pickFirst(data?['profileImageName']);
        final String url       = _pickFirst(data?['profileImageUrl']);

        Uint8List? bytes;
        String? assetName;
        String? urlStr;

        switch (photoMode) {
          case _PhotoMode.base64:
            bytes = _tryDecodeBase64(b64);
            break;
          case _PhotoMode.asset:
            assetName = nameAsset.isNotEmpty ? nameAsset : null;
            break;
          case _PhotoMode.network:
            urlStr = url.startsWith('http') ? url : null;
            break;
          case _PhotoMode.auto:
            bytes = _tryDecodeBase64(b64);
            assetName = (bytes == null && nameAsset.isNotEmpty) ? nameAsset : null;
            urlStr = (bytes == null && assetName == null && url.startsWith('http')) ? url : null;
            break;
        }

        return _PersonCard(
          title: title,
          name: name,
          email: email,
          contact: phone,
          status: showStatusFromRole ? role : null,
          fillColor: fillColor,
          photoBytes: bytes,
          assetName: assetName,
          url: urlStr,
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

  final Uint8List? photoBytes; // for user (base64)
  final String? assetName;     // for asset name
  final String? url;           // optional network

  bool get _hasBytes => photoBytes != null && photoBytes!.isNotEmpty;
  bool get _hasAsset => assetName != null && assetName!.isNotEmpty;
  bool get _hasUrl   => url != null && url!.isNotEmpty;

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
      return Image.asset('asset/image/$assetName', fit: BoxFit.cover, errorBuilder: (_, __, ___) => _avatarFallback(name));
    }
    if (_hasUrl) {
      return Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _avatarFallback(name));
    }
    return _avatarFallback(name);
  }

  static Uint8List? _tryDecodeBase64(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final String s = raw.contains(',') ? raw.substring(raw.indexOf(',') + 1) : raw;
      return base64Decode(s);
    } catch (_) {
      return null;
    }
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
        Expanded(
          child: Text(
            v,
            style: TextStyle(fontSize: 12.sp, color: const Color(0xFF111827)),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _avatarFallback(String name) {
    final initials = _initials(name);
    return Center(
      child: Text(initials, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF9CA3AF))),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return ''; // no dash fallback
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

// ⬇️ Put near the bottom of web_booking_details.dart (outside any class)

// open the DETAILS popup (wrapper so we don't repeat code)
Future<void> openWebBookingDetailsDialog({
  required BuildContext context,
  required Map<String, dynamic> booking,
  bool use24HourFormat = false,
}) async {
  // show a centered dialog that contains WebBookingDetails
  await showDialog(
    context: context,
    barrierDismissible: true, // allow clicking outside to close
    builder: (_) {
      // Dialog ensures it is a popup (not full screen)
      return Dialog(
        insetPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        child: WebBookingDetails(
          booking: booking,
          use24HourFormat: use24HourFormat,
        ),
      );
    },
  );
}

