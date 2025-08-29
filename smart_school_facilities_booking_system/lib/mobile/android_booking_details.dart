// android_booking_details.dart
//
// Design-only details page for a single booking.
// - Reads facility by facilityId
// - Reads booking by bookingId
// - Shows chips + a single bottom action (Edit or Rate) based on approval/status
// - Removed all "availability" UI and rating section
// - Uses only if/else (no ?: and no ??) and .w .h .sp .sw .sh everywhere.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'android_edit_booking.dart';
import 'android_make_rating.dart';

import 'android_bottom_menu.dart';
import 'android_calendar.dart';
import 'android_list_of_facilities.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_view_booking.dart';
import 'android_login.dart';

// If you ever need to navigate somewhere else later, import here.
// (No bottom menu on this page per your design.)

class AndroidBookingDetails extends StatefulWidget {
  final String bookingId;   // from list page tap
  final String facilityId;  // from the tapped item

  const AndroidBookingDetails({
    Key? key,
    required this.bookingId,
    required this.facilityId,
  }) : super(key: key);

  @override
  State<AndroidBookingDetails> createState() => _AndroidBookingDetailsState();
}

class _AndroidBookingDetailsState extends State<AndroidBookingDetails> {

  int _currentIndex = 1; // this page = left-most tab

  void _onTabSelected(int i) {
    // simple navigation for bottom bar
    if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidCalendar()));
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
  // -------------------- format helpers --------------------
  String _formatFullDate(DateTime d) {
    final DateFormat f = DateFormat('EEE, d MMM yyyy');
    return f.format(d);
  }

  String _formatTime12(DateTime d) {
    // "h.mm am/pm" with non-breaking space to keep one line
    final DateFormat f = DateFormat('h.mm a');
    String s = f.format(d).toLowerCase();
    s = s.replaceAll(' ', '\u00A0');
    return s;
  }



  // -------- read date-only from mixed fields --------
  DateTime? _readDateOnly(dynamic v) {
    if (v is Timestamp) {
      final DateTime d = v.toDate();
      return DateTime(d.year, d.month, d.day);
    } else {
      if (v is DateTime) {
        return DateTime(v.year, v.month, v.day);
      } else {
        if (v is String) {
          DateTime? parsed;
          try { parsed = DateTime.tryParse(v); } catch (_) { parsed = null; }
          if (parsed == null) {
            try {
              final DateFormat fmt = DateFormat('yyyy-MM-dd');
              parsed = fmt.parseStrict(v);
            } catch (_) { parsed = null; }
          }
          if (parsed != null) {
            return DateTime(parsed.year, parsed.month, parsed.day);
          } else {
            return null;
          }
        } else {
          return null;
        }
      }
    }
  }

  // -------- read DateTime (legacy Timestamp/DateTime support) --------
  DateTime? _readDateTime(dynamic v) {
    if (v is Timestamp) {
      return v.toDate();
    } else {
      if (v is DateTime) {
        return v;
      } else {
        return null;
      }
    }
  }

  // -------- parse 24h time string like "13:30","1330","13.30","9:05" --------
  List<int>? _parseHourMinute(String s) {
    if (s.isEmpty == true) {
      return null;
    } else {
      String t = s.trim();
      t = t.replaceAll(' ', '');
      t = t.replaceAll('.', ':');
      t = t.replaceAll('-', ':');

      if (t.contains(':') == true) {
        final List<String> parts = t.split(':');
        int h = 0;
        int m = 0;

        if (parts.isNotEmpty == true) {
          try { h = int.parse(parts[0]); } catch (_) { h = -1; }
        }
        if (parts.length > 1) {
          try { m = int.parse(parts[1]); } catch (_) { m = -1; }
        } else {
          m = 0;
        }

        if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
          return [h, m];
        } else {
          return null;
        }
      } else {
        String d = '';
        int i = 0;
        while (i < t.length) {
          final String ch = t.substring(i, i + 1);
          if (ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57) {
            d = d + ch;
          }
          i = i + 1;
        }

        int h = -1;
        int m = -1;

        if (d.length == 4) {
          try { h = int.parse(d.substring(0, 2)); } catch (_) { h = -1; }
          try { m = int.parse(d.substring(2, 4)); } catch (_) { m = -1; }
        } else {
          if (d.length == 3) {
            try { h = int.parse(d.substring(0, 1)); } catch (_) { h = -1; }
            try { m = int.parse(d.substring(1, 3)); } catch (_) { m = -1; }
          } else {
            if (d.length == 2) {
              try { h = int.parse(d); } catch (_) { h = -1; }
              m = 0;
            } else {
              h = -1;
              m = -1;
            }
          }
        }

        if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
          return [h, m];
        } else {
          return null;
        }
      }
    }
  }

  // Build DateTime from bookingDate + time string OR use existing Timestamp
  DateTime? _composeFromBookingDate(dynamic bookingDateField, dynamic timeField) {
    final DateTime? ts = _readDateTime(timeField);
    if (ts != null) {
      return ts;
    }

    String tStr = '';
    if (timeField != null) {
      tStr = timeField.toString();
    }

    if (tStr.isNotEmpty == true) {
      final List<int>? hm = _parseHourMinute(tStr);
      if (hm != null) {
        final DateTime? base = _readDateOnly(bookingDateField);
        if (base != null) {
          return DateTime(base.year, base.month, base.day, hm[0], hm[1]);
        } else {
          final DateTime now = DateTime.now();
          return DateTime(now.year, now.month, now.day, hm[0], hm[1]);
        }
      }
    }
    return null;
  }

  // approval to string
  String _approvalText(dynamic v) {
    if (v is bool) {
      if (v == true) { return 'approved'; } else { return 'pending'; }
    } else {
      if (v == null) { return ''; } else { return v.toString().toLowerCase(); }
    }
  }

  // chip colors
  List<Color> _chipColors(String labelLower) {
    if (labelLower == 'approved' || labelLower == 'accept' || labelLower == 'accepted' || labelLower == 'upcoming') {
      return [Colors.green.shade200, Colors.green];
    } else {
      if (labelLower == 'rejected') {
        return [Colors.red.shade200, Colors.red];
      } else {
        if (labelLower == 'pending' || labelLower == 'ongoing') {
          return [Colors.amber.shade200, Colors.amber];
        } else {
          if (labelLower == 'ended' || labelLower == 'complete' || labelLower == 'completed') {
            return [Colors.grey.shade300, Colors.grey];
          } else {
            return [Colors.grey.shade200, Colors.grey];
          }
        }
      }
    }
  }

  Widget _buildChip(String text, Color fill, Color border) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      margin: EdgeInsets.only(right: 8.w, top: 6.h),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(40.r),
        border: Border.all(color: border, width: 1.w),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.black87),
      ),
    );
  }

  String _capitalize(String s) {
    if (s.isEmpty == true) { return s; } else {
      final String first = s.substring(0, 1).toUpperCase();
      final String rest  = s.substring(1);
      return first + rest;
    }
  }

  @override
  Widget build(BuildContext context) {
    final double sw = 1.0.sw;
    final double barHeight = 0.07.sh;

    // live streams: booking + facility
    final Stream<DocumentSnapshot<Map<String, dynamic>>> bookingStream =
    FirebaseFirestore.instance.collection('Bookings').doc(widget.bookingId).snapshots();

    final Stream<DocumentSnapshot<Map<String, dynamic>>> facilityStream =
    FirebaseFirestore.instance.collection('Facilities').doc(widget.facilityId).snapshots();

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (Navigator.canPop(context)) { Navigator.pop(context); }
            },
            tooltip: 'Back',
          ),
          title: Text("Details", style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600)),
          actions: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                if (Navigator.canPop(context)) { Navigator.pop(context); }
              },
              tooltip: 'Close',
            ),
          ],
        ),
      ),

      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: facilityStream,
        builder: (context, facSnap) {
          if (facSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!facSnap.hasData || !facSnap.data!.exists) {
            return Center(child: Text('Facility not found', style: TextStyle(fontSize: 14.sp)));
          }

          final Map<String, dynamic> fac = facSnap.data!.data()!;

          // Facility fields
          String name = '';
          if (fac.containsKey('name')) {
            if (fac['name'] != null) { name = fac['name'].toString(); }
          }
          String imageName = '';
          if (fac.containsKey('imageName')) {
            if (fac['imageName'] != null) { imageName = fac['imageName'].toString().trim(); }
          }
          String facilityImagePath = '';
          if (imageName.isNotEmpty == true) {
            facilityImagePath = 'asset/image/$imageName';
          }

          String location = '';
          if (fac.containsKey('location')) {
            if (fac['location'] != null) { location = fac['location'].toString(); }
          }


          String description = '';
          if (fac.containsKey('details')) {
            if (fac['details'] != null) { description = fac['details'].toString(); }
          }

          String managerId = '';
          if (fac.containsKey('managerId')) {
            if (fac['managerId'] != null) { managerId = fac['managerId'].toString(); }
          }

          String durationText = '';
          if (fac.containsKey('bookingDurationHours')) {
            final dynamic dur = fac['bookingDurationHours'];
            if (dur is int) {
              if (dur == 1) { durationText = '1 hour'; } else { durationText = '$dur hours'; }
            } else {
              if (dur is double) {
                final int intPart = dur.toInt();
                if (dur == intPart) {
                  if (intPart == 1) { durationText = '1 hour'; } else { durationText = '$intPart hours'; }
                } else {
                  durationText = '$dur hours';
                }
              } else {
                durationText = dur.toString();
              }
            }
          }

          bool requireApproval = false;
          if (fac.containsKey('requireApproval')) {
            final dynamic v = fac['requireApproval'];
            if (v is bool) {
              requireApproval = v;
            } else {
              if (v is String) {
                if (v.toLowerCase() == 'true') {
                  requireApproval = true;
                } else {
                  requireApproval = false;
                }
              } else if (v is num) {
                if (v != 0) {
                  requireApproval = true;
                } else {
                  requireApproval = false;
                }
              }
            }
          }

          // Manager stream
          final Stream<DocumentSnapshot<Map<String, dynamic>>> mgrStream =
          FirebaseFirestore.instance.collection('UserInformation').doc(managerId).snapshots();

          // Now read booking doc
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: bookingStream,
            builder: (context, bookSnap) {
              if (bookSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!bookSnap.hasData || !bookSnap.data!.exists) {
                return Center(child: Text('Booking not found', style: TextStyle(fontSize: 14.sp)));
              }

              final Map<String, dynamic> bk = bookSnap.data!.data()!;

              // Booking fields
              dynamic bookingDateField;
              if (bk.containsKey('bookingDate')) { bookingDateField = bk['bookingDate']; }
              else {
                if (bk.containsKey('booking_date')) { bookingDateField = bk['booking_date']; }
                else {
                  if (bk.containsKey('date')) { bookingDateField = bk['date']; } else { bookingDateField = null; }
                }
              }
              final DateTime? bookingDate = _readDateOnly(bookingDateField);

              final DateTime? startDT = _composeFromBookingDate(bookingDateField, bk['start'] ?? bk['startTime']);
              final DateTime? endDT   = _composeFromBookingDate(bookingDateField, bk['end']   ?? bk['endTime']);

              String startStr = '--.--';
              if (startDT != null) { startStr = _formatTime12(startDT); }
              String endStr = '--.--';
              if (endDT != null) { endStr = _formatTime12(endDT); }

              // Seat / slot
              String seatText = '-';
              if (bk.containsKey('seatIndex')) {
                if (bk['seatIndex'] != null) { seatText = bk['seatIndex'].toString(); }
              } else {
                if (bk.containsKey('slotIndex')) {
                  if (bk['slotIndex'] != null) { seatText = bk['slotIndex'].toString(); }
                }
              }

              // approval + status
              final String approval = _approvalText(bk['approval']).trim();
              String status = '';
              if (bk.containsKey('status')) {
                if (bk['status'] != null) { status = bk['status'].toString().toLowerCase().trim(); }
              } else {
                if (bk.containsKey('state')) {
                  if (bk['state'] != null) { status = bk['state'].toString().toLowerCase().trim(); }
                }
              }

              // Build chips by rules:
              // - pending: show approval only (hide status)
              // - rejected: show approval only, no buttons
              // - ongoing: show chips as normal, no buttons
              // - ended: hide approval chip, show grey Ended chip, Rate button
              final List<Widget> chips = <Widget>[];

              bool isPending = false;
              bool isRejected = false;
              bool isEnded = false;
              bool isOngoing = false;
              bool isAccepted = false;

              if (approval == 'pending') { isPending = true; }
              if (approval == 'rejected') { isRejected = true; }
              if (approval == 'approved' || approval == 'accept' || approval == 'accepted') { isAccepted = true; }
              if (status == 'ended' || status == 'complete' || status == 'completed') { isEnded = true; }
              if (status == 'ongoing') { isOngoing = true; }

              // Chips:
              if (isEnded == true) {
                // ended -> no approval chip, only an Ended status chip (grey)
                final List<Color> c = _chipColors('ended');
                chips.add(_buildChip('Ended', c[0], c[1]));
              } else {
                // show approval chip unless empty
                if (approval.isNotEmpty == true) {
                  final List<Color> a = _chipColors(approval);
                  chips.add(_buildChip(_capitalize(approval), a[0], a[1]));
                }
                // show status chip only if not pending/rejected
                if (isPending == false && isRejected == false) {
                  if (status.isNotEmpty == true) {
                    final List<Color> s = _chipColors(status);
                    chips.add(_buildChip(_capitalize(status), s[0], s[1]));
                  }
                }
              }

              // Which button to show below Manager card:
              // - pending  -> Edit
              // - accepted -> Edit
              // - rejected -> none
              // - ongoing  -> none
              // - ended    -> Rate
              bool showEdit = false;
              bool showRate = false;

              if (isEnded == true) {
                // ended -> Rate
                showRate = true;
              } else {
                if (isRejected == true) {
                  // rejected -> no buttons
                  showEdit = false;
                  showRate = false;
                } else {
                  if (isOngoing == true) {
                    // ongoing -> no buttons
                    showEdit = false;
                    showRate = false;
                  } else {
                    // pending or accepted
                    if (isPending == true) {
                      // pending -> Edit
                      showEdit = true;
                    } else {
                      // accepted
                      if (requireApproval == true) {
                        // accepted + facility requires approval -> NO edit
                        showEdit = false;
                      } else {
                        // accepted + no facility approval gate -> Edit
                        showEdit = true;
                      }
                    }
                  }
                }
              }

              bool ratedAlready = false;
              if (bk.containsKey('rated')) {
                final dynamic rv = bk['rated'];
                if (rv is bool) {
                  if (rv == true) { ratedAlready = true; } else { ratedAlready = false; }
                } else {
                  if (rv is String) {
                    if (rv.toLowerCase() == 'true') { ratedAlready = true; } else { ratedAlready = false; }
                  } else {
                    if (rv is num) {
                      if (rv != 0) { ratedAlready = true; } else { ratedAlready = false; }
                    }
                  }
                }
              }


              // Responsive image height
              double imgH = sw * 0.75;
              if (imgH < 240.h) { imgH = 240.h; } else { if (imgH > 420.h) { imgH = 420.h; } }

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Facility image
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

                    // Content at 90% width
                    SizedBox(
                      width: sw * 0.90,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name
                          Text(
                            name,
                            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                          SizedBox(height: 10.h),

                          // Booking date line
                          if (bookingDate != null)
                            Text(
                              "Booking Date: ${_formatFullDate(bookingDate)}",
                              style: TextStyle(fontSize: 14.sp, color: Colors.black87, fontWeight: FontWeight.w600),
                            ),

                          SizedBox(height: 12.h),

                          // Time block + Slot (mirrors list style)
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE9D7FF),
                              borderRadius: BorderRadius.circular(14.r),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0x22000000),
                                  blurRadius: 8.r,
                                  offset: Offset(0, 3.h),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // left times with centered "|"
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
                                          softWrap: false,
                                          overflow: TextOverflow.clip,
                                          style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: Colors.black87),
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text('|', style: TextStyle(fontSize: 16.sp, color: Colors.black45)),
                                      ),
                                      Align(
                                        alignment: Alignment.bottomLeft,
                                        child: Text(
                                          endStr,
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.clip,
                                          style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: Colors.black54),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // divider
                                Container(
                                  width: 2.w,
                                  height: 50.h,
                                  margin: EdgeInsets.symmetric(horizontal: 12.w),
                                  color: const Color(0xFF7E57C2),
                                ),

                                // right: slot + chips
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.event_seat, size: 18.w, color: Colors.black54),
                                          Text("Slot : ",
                                              style: TextStyle(fontSize: 13.sp, color: Colors.black87, fontWeight: FontWeight.w600)),
                                          SizedBox(width: 6.w),
                                          Text(seatText,
                                              style: TextStyle(fontSize: 13.sp, color: Colors.black87, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                      SizedBox(height: 8.h),
                                      Wrap(children: chips),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: 18.h),

                          // Location
                          Text('Location', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                          SizedBox(height: 6.h),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(12.w),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Text(location, style: TextStyle(fontSize: 14.sp)),
                          ),

                          SizedBox(height: 18.h),

                          // Description
                          Text('Description', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                          SizedBox(height: 6.h),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(12.w),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Text(description, style: TextStyle(fontSize: 14.sp)),
                          ),

                          SizedBox(height: 18.h),

                          // Duration
                          Text('Duration per slot', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                          SizedBox(height: 6.h),
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.all(12.w),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Text(durationText, style: TextStyle(fontSize: 14.sp)),
                          ),

                          SizedBox(height: 18.h),

                          // Manager
                          Text('Manager', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                          SizedBox(height: 6.h),

                          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                            stream: mgrStream,
                            builder: (context, mgrSnap) {
                              if (mgrSnap.connectionState == ConnectionState.waiting) {
                                return Container(
                                  width: double.infinity,
                                  height: 135.h,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE2CCFF),
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                  child: const CircularProgressIndicator(),
                                );
                              }

                              Map<String, dynamic> mm = <String, dynamic>{};
                              if (mgrSnap.hasData) {
                                if (mgrSnap.data != null) {
                                  if (mgrSnap.data!.data() != null) {
                                    mm = mgrSnap.data!.data()!;
                                  }
                                }
                              }

                              String username = '';
                              if (mm.containsKey('username')) {
                                if (mm['username'] != null) { username = mm['username'].toString(); }
                              }
                              if (username.isEmpty == true) {
                                if (mm.containsKey('name')) {
                                  if (mm['name'] != null) { username = mm['name'].toString(); }
                                }
                              }

                              String email = '';
                              if (mm.containsKey('email')) {
                                if (mm['email'] != null) { email = mm['email'].toString(); }
                              }

                              String contact = '';
                              if (mm.containsKey('contact')) {
                                if (mm['contact'] != null) { contact = mm['contact'].toString(); }
                              }

                              String managerAssetPath = '';
                              if (mm.containsKey('profileImageName')) {
                                if (mm['profileImageName'] != null) {
                                  final String trimmed = mm['profileImageName'].toString().trim();
                                  if (trimmed.isNotEmpty == true) {
                                    managerAssetPath = 'asset/image/$trimmed';
                                  }
                                }
                              }

                              return Column(
                                children: [
                                  // manager info card (auto height)
                                  Container(
                                    width: double.infinity,
                                    constraints: BoxConstraints(minHeight: 135.h),
                                    padding: EdgeInsets.all(10.w),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE2CCFF),
                                      borderRadius: BorderRadius.circular(12.r),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8.r),
                                          child: SizedBox(
                                            width: 110.w,
                                            height: 110.w,
                                            child: (managerAssetPath.isEmpty)
                                                ? Container(
                                              color: Colors.grey.shade400,
                                              alignment: Alignment.center,
                                              child: const Icon(Icons.person_off, color: Colors.white),
                                            )
                                                : Image.asset(managerAssetPath, fit: BoxFit.cover),
                                          ),
                                        ),
                                        SizedBox(width: 15.w),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _kvLine(label: 'Name', value: username),
                                              SizedBox(height: 6.h),
                                              _kvLine(label: 'Email', value: email),
                                              SizedBox(height: 6.h),
                                              _kvLine(label: 'Contact', value: contact),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  SizedBox(height: 16.h),

                                  // Bottom single action area (same size/position as old "Book")
                                  Builder(
                                    builder: (_) {
                                      if (showEdit == true) {
                                        return SizedBox(
                                          width: sw * 0.90,
                                          height: 48.h,
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF8620E5),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(10.r),
                                              ),
                                            ),
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => AndroidEditBooking(
                                                    bookingId: widget.bookingId,

                                                  ),
                                                ),
                                              );
                                            },

                                            child: Text('Edit', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                                          ),
                                        );
                                      } else {
                                        if (showRate == true) {
                                          // If already rated -> grey "Rated" button that does not navigate.
                                          // If not rated -> purple "Rate" button that navigates to rating page.
                                          Color btnColor;
                                          String btnLabel;
                                          if (ratedAlready == true) {
                                            btnColor = Colors.grey;     // disabled look
                                            btnLabel = 'Rated';
                                          } else {
                                            btnColor = const Color(0xFF8620E5); // active
                                            btnLabel = 'Rate';
                                          }

                                          return SizedBox(
                                            width: sw * 0.90,
                                            height: 48.h,
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: btnColor,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(10.r),
                                                ),
                                              ),
                                              onPressed: () {
                                                if (ratedAlready == true) {
                                                  // Already rated -> do not go anywhere, show snack
                                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('User have rated on current booking', style: TextStyle(fontSize: 13.sp))),
                                                  );
                                                } else {
                                                  // Not rated yet -> navigate to rating page
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => AndroidMakeRating(
                                                        bookingId: widget.bookingId,
                                                        facilityId: widget.facilityId,
                                                      ),
                                                    ),
                                                  );
                                                }
                                              },
                                              child: Text(btnLabel, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                                            ),
                                          );
                                        } else {
                                          // nothing (ongoing / rejected)
                                          return const SizedBox.shrink();
                                        }
                                      }
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
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

// ---------- Small UI helpers ----------
Widget _kvLine({required String label, required String value}) {
  return Padding(
    padding: EdgeInsets.only(bottom: 6.h),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$label: ",
          style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.black),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 13.sp, color: Colors.black87),
            softWrap: true,
          ),
        ),
      ],
    ),
  );
}
