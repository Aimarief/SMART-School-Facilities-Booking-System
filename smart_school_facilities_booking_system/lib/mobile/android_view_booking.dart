import 'package:cloud_firestore/cloud_firestore.dart';         // Firestore
import 'package:firebase_auth/firebase_auth.dart';             // current user
import 'package:flutter/material.dart';                        // UI
import 'package:flutter_screenutil/flutter_screenutil.dart';   // responsive sizes
import 'package:intl/intl.dart';                               // date/time formatting
import 'android_booking_details.dart';

import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_list_of_facilities.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_login.dart';


class AndroidViewBooking extends StatefulWidget {
  @override
  State<AndroidViewBooking> createState() => _AndroidViewBookingState();
}

class _AndroidViewBookingState extends State<AndroidViewBooking> {
//---------------------------------------
// current index
//---------------------------------------

  int _currentIndex = 1;

  DateTime? _filterDate;

  late DateTime _today;

  bool _use24HourFormat = false;

  bool _didRunHousekeeping = false;

  final Map<String, String> _facilityNameCache = {};

//---------------------------------------
// do init state first before anything
//---------------------------------------
  @override
  void initState() {
    super.initState();
    //---------------------------------------
// get today date
//---------------------------------------
    _today = DateTime.now();

//---------------------------------------
// run the house keeping
//---------------------------------------
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runHousekeepingOnce();
    });
  }

//---------------------------------------
// navigation page
//---------------------------------------
  void _onTabSelected(int i) {
    if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAgenda()));
    } else {
      if (i == 1) {
        setState(() { _currentIndex = 1; }); // stay on this page
      } else {
        if (i == 2) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
        } else {
          if (i == 3) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
          } else {
            if (i == 4) {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
            }
          }
        }
      }
    }
  }

//---------------------------------------
// date picker to pick date
//---------------------------------------

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime first = DateTime(now.year - 5, 1, 1);
    final DateTime last  = DateTime(now.year + 5, 12, 31);

    //---------------------------------------
// show date picker
//---------------------------------------
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _filterDate == null ? now : _filterDate!,
      firstDate: first,
      lastDate: last,
    );

//---------------------------------------
// if picked set the UI to the picked date
//---------------------------------------

    if (picked != null) {
      setState(() {
        _filterDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

//---------------------------------------
// for mat date like 23 May 2024
//---------------------------------------
  String _formatLongDate(DateTime d) {
    final DateFormat f = DateFormat('d MMMM yyyy');
    return f.format(d);
  }

//---------------------------------------
// where there is filter date which is picked
//---------------------------------------
  DateTime _headerDate() {
    if (_filterDate != null) {
      return _filterDate!;
    } else {
      return _today;
    }
  }

//---------------------------------------
// date header display
//---------------------------------------

  Widget _dateHeaderRow() {
    final DateTime d = _headerDate();
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 8.h),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              _formatLongDate(d),
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
//---------------------------------------
// calender picker
//---------------------------------------
          InkWell(
            onTap: _pickDate,
            child: Container(
              width: 36.w,
              height: 36.w,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8.w),
                border: Border.all(color: const Color(0xFFE5E5E5), width: 1.w),
              ),
              child: Icon(Icons.calendar_today, size: 18.w, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

//---------------------------------------
// where the date is picked then show clear button at center
//---------------------------------------
  Widget _clearCenterIfNeeded() {
    if (_filterDate != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(top: 4.h),
          child: TextButton(
            onPressed: _clearDate,
            child: Text(
              "Clear",
              style: TextStyle(fontSize: 13.sp, color: const Color(0xFF9747FF), fontWeight: FontWeight.w600),
            ),
          ),
        ),
      );
    } else {
      return SizedBox(height: 0.h);
    }
  }

//---------------------------------------
// set state and remove date filter
//---------------------------------------
  void _clearDate() {
    setState(() { _filterDate = null; });
  }

//---------------------------------------
// format date to day, date month year, like Fri , 23,May,2024
//---------------------------------------

  String _formatFullDate(DateTime d) {
    final DateFormat f = DateFormat('EEE, d MMM yyyy');
    return f.format(d);
  }

//---------------------------------------
// format date and time to am pm
//---------------------------------------

  String _formatTime(DateTime d) {
    String s = '';
      final DateFormat f12 = DateFormat('h.mm a');
      s = f12.format(d).toLowerCase();

    s = s.replaceAll(' ', '\u00A0');
    return s;
  }

  //---------------------------------------
// compare if same day
//---------------------------------------
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

//---------------------------------------
// get the string
//---------------------------------------

  String _readString(Map<String, dynamic> m, List<String> keys) {
    int i = 0;
    while (i < keys.length) {
      final String k = keys[i];
      if (m.containsKey(k)) {
        final dynamic v = m[k];
        if (v != null) {
          return v.toString();
        }
      }
      i = i + 1;
    }
    return '';
  }

  //---------------------------------------
// read the time
//---------------------------------------
  DateTime? _readDateTime(Map<String, dynamic> m, List<String> keys) {

    for (int i = 0; i < keys.length; i++) {
      final String k = keys[i];
      if (m.containsKey(k)) {
        final dynamic v = m[k];

        if (v is Timestamp) {
          return v.toDate();
        }
        if (v is DateTime) {
          return v;
        }
      }
    }
    return null;
  }

//---------------------------------------
// read teh date
//---------------------------------------
  DateTime? _readDate(Map<String, dynamic> m, List<String> keys) {
    int i = 0;
    while (i < keys.length) {
      final String k = keys[i];
      if (m.containsKey(k)) {
        final dynamic v = m[k];

        if (v is String) {
          DateTime? parsed;
          try { parsed = DateTime.tryParse(v); } catch (_) { parsed = null; }

          if (parsed != null) {
            return DateTime(parsed.year, parsed.month, parsed.day);
          }
        }
      }
      i = i + 1;
    }
    return null;
  }

//---------------------------------------
// get the time h , m so it can be parse later
//---------------------------------------
  List<int>? _parseHourMinute(String s) {
    if (s.isEmpty == true) {
      return null;
    } else {
      String t = s.trim();

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

        // return only valid 24h times
        if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
          return [h, m];
        } else {
          return null;
        }
      }
    }
  }

//---------------------------------------
// get booking date in date format hour minute format
//---------------------------------------
  DateTime? _composeDateTime(Map<String, dynamic> m, List<String> timeKeys) {

    final String tStr = _readString(m, timeKeys);
    if (tStr.isNotEmpty == true) {
      //---------------------------------------
// the string for the time will parse into h,m format
//---------------------------------------
      final List<int>? hm = _parseHourMinute(tStr);
      if (hm != null) {
        DateTime? base = _readDate(m, ['bookingDate']);
        if (base == null) {
          base = DateTime.now();
        }
        return DateTime(base.year, base.month, base.day, hm[0], hm[1]);
      }
    }

    return null;
  }

//---------------------------------------
// get the approval text
//---------------------------------------
  String _approvalText(dynamic approvalValue) {
        return approvalValue.toString().toLowerCase();
  }

//---------------------------------------
// get the facility name through cache first if no then
//---------------------------------------
  Future<String> _getFacilityName(String facilityId) async {
    if (_facilityNameCache.containsKey(facilityId) == true) {
      return _facilityNameCache[facilityId]!;
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> d =
      await FirebaseFirestore.instance.collection('Facilities').doc(facilityId).get();
//---------------------------------------
// make sure the facility really exist
//---------------------------------------
      if (d.exists == true) {
        final Map<String, dynamic>? data = d.data();
        if (data != null) {
          final String name = _readString(data, ['name']);
          if (name.isNotEmpty == true) {
            _facilityNameCache[facilityId] = name;
            return name;
          } else {
            _facilityNameCache[facilityId] = 'Facility';
            return 'Facility';
          }
        } else {
          _facilityNameCache[facilityId] = 'Facility';
          return 'Facility';
        }
      } else {
        _facilityNameCache[facilityId] = 'Facility';
        return 'Facility';
      }
    } catch (_) {
      _facilityNameCache[facilityId] = 'Facility';
      return 'Facility';
    }
  }

  //---------------------------------------
// each chip for approval
//---------------------------------------

  Widget _buildChip(String text, Color fill, Color border, {Color? textColor}) {
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
        style: TextStyle(
          fontSize: 12.sp,
          fontWeight: FontWeight.w600,
          color: textColor ?? Colors.black87,
        ),
      ),
    );
  }


//---------------------------------------
// each chip by status
//---------------------------------------

  List<Color> _chipColors(String labelLower) {
    // choose consistent color coding by status/approval string
    if (labelLower == 'accepted' || labelLower == 'upcoming') {
      return [Colors.green.shade200, Colors.green];
    } else {
      if (labelLower == 'rejected') {
        return [Colors.red.shade200, Colors.red];
      } else {
        if (labelLower == 'pending' || labelLower == 'ongoing') {
          return [Colors.amber.shade200, Colors.amber];
        } else {
          if (labelLower == 'ended') {
            return [Colors.grey.shade300, Colors.grey];
          } else {
            return [Colors.grey.shade200, Colors.grey];
          }
        }
      }
    }
  }

//---------------------------------------
// each of a the booking
//---------------------------------------

  Widget _buildBookingRow(Map<String, dynamic> m, String docId) {

    final String facilityId = _readString(m, ['facilityId']);
    final DateTime? start = _composeDateTime(m, ['start']);
    final DateTime? end   = _composeDateTime(m,  ['end']);
    final String approval = (m['approval'] as String).trim();
    final String status   = _readString(m, ['status']).toLowerCase().trim();
    final String seat = _readString(m, ['seatIndex']);

    //---------------------------------------
// format time am and pm
//---------------------------------------
    String startStr = '--.--';
    if (start != null) {
      startStr = _formatTime(start);
    }
    String endStr = '--.--';
    if (end != null) {
      endStr = _formatTime(end);
    }

    final bool hasAmendment = (m['hasPendingAmendment'] == true);
//---------------------------------------
// check if have amendment then change the box colour
//---------------------------------------
    final List<Widget> chips = [];
    if (hasAmendment) {
      const Color amendBlue = Color(0xFF1D4ED8);
      chips.add(_buildChip('Amendment', Colors.white, amendBlue, textColor: amendBlue));
    } else {
      //---------------------------------------
// for other approval or status design
//---------------------------------------

      if (approval.isNotEmpty == true) {
        final List<Color> c = _chipColors(approval);
        chips.add(_buildChip(_capitalize(approval), c[0], c[1]));
      }
      if (approval != 'pending' && approval != 'rejected') {
        if (status.isNotEmpty == true) {
          final List<Color> s = _chipColors(status);
          chips.add(_buildChip(_capitalize(status), s[0], s[1]));
        }
      }
    }

//---------------------------------------
// get faility name
//---------------------------------------
    return FutureBuilder<String>(
      future: _getFacilityName(facilityId),
      builder: (context, snap) {
        String facilityName = 'Facility';
        if (snap.connectionState == ConnectionState.waiting) {
          facilityName = 'Loading...';
        } else {
          if (snap.hasError == true) {
            facilityName = 'Facility';
          } else {
            if (snap.data != null) {
              facilityName = snap.data!;
            } else {
              facilityName = 'Facility';
            }
          }
        }
//---------------------------------------
// return each facility booking as button
//---------------------------------------
        return InkWell(
          onTap: () {

            final String bookingId = docId;
            final String facId = facilityId;

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AndroidBookingDetails(
                  bookingId: bookingId,
                  facilityId: facId,
                ),
              ),
            );
          },

          //---------------------------------------
// each button container design
//---------------------------------------
          child: Container(
            width: 1.0.sw,
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            margin: EdgeInsets.only(bottom: 12.h),
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
                SizedBox(
                  width: 78.w,
                  height: 68.h,
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
//---------------------------------------
// display start time
//---------------------------------------

                        child: Text(
                          startStr,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.clip,
                          style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: Colors.black87),
                        ),
                      ),
//---------------------------------------
// the to |  symbol
//---------------------------------------
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('       |', style: TextStyle(fontSize: 16.sp, color: Colors.black45)),
                      ),
//---------------------------------------
// display end time
//---------------------------------------

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

//---------------------------------------
// devider
//---------------------------------------
                Container(
                  width: 2.w,
                  height: 50.h,
                  margin: EdgeInsets.symmetric(horizontal: 12.w),
                  color: const Color(0xFF7E57C2),
                ),

//---------------------------------------
// facility name
//---------------------------------------
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        facilityName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18.sp,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),

                      SizedBox(height: 6.h),

                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.event_seat, size: 18.w, color: Colors.black54),
  //---------------------------------------
// display slot
//---------------------------------------
                          Text(
                            "Slot : ",
                            style: TextStyle(fontSize: 13.sp, color: Colors.black87, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(width: 6.w),
//---------------------------------------
// display seat
//---------------------------------------
                          Text(
                            seat,
                            style: TextStyle(fontSize: 13.sp, color: Colors.black87, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),

                      SizedBox(height: 8.h),
//---------------------------------------
// display teh chip some have 2 some have 1 base on the approval
//---------------------------------------
                      Wrap(children: chips),
                    ],
                  ),
                ),

//---------------------------------------
// icon
//---------------------------------------

                Icon(Icons.chevron_right, size: 26.w, color: Colors.black54),
              ],
            ),
          ),
        );
      },
    );
  }

//---------------------------------------
// allow to first string to capital
//---------------------------------------

  String _capitalize(String s) {
    if (s.isEmpty == true) { return s; } else {
      final String first = s.substring(0, 1).toUpperCase();
      final String rest  = s.substring(1);
      return first + rest;
    }
  }

  // -------------------- same-day helper (Y/M/D) --------------------
  bool _isSameYMD(DateTime a, DateTime b) {
    if (a.year == b.year) {
      if (a.month == b.month) {
        if (a.day == b.day) {
          return true;
        } else {
          return false;
        }
      } else {
        return false;
      }
    } else {
      return false;
    }
  }

//---------------------------------------
// read booking date and parse the date
//---------------------------------------

  DateTime? _readBookingDate(Map<String, dynamic> m) {
    return _readDate(m, ['bookingDate']);
  }

//---------------------------------------
// read the string and parse it to lower case
//---------------------------------------

  String _readLowerStr(Map<String, dynamic> m, List<String> keys) {
    final String s = _readString(m, keys);
    if (s.isEmpty == true) {
      return '';
    } else {
      return s.toLowerCase().trim();
    }
  }

//---------------------------------------
// get the time of day h and m
//---------------------------------------

  TimeOfDay? _readTime(Map<String, dynamic> m, List<String> keys) {
    int i = 0;
    while (i < keys.length) {
      final String k = keys[i];
      if (m.containsKey(k)) {
        final dynamic v = m[k];

            if (v is String) {
              final List<int>? hm = _parseHourMinute(v);
              if (hm != null) {
                return TimeOfDay(hour: hm[0], minute: hm[1]);
          }
        }
      }
      i = i + 1;                            // increment i to check next key
    }
    return null;
  }

//---------------------------------------
// run house keeping method
//---------------------------------------

  Future<void> _runHousekeepingOnce() async {
    if (_didRunHousekeeping == true) {
      return;
    } else {
      _didRunHousekeeping = true;
    }

    try {
      //---------------------------------------
// get today date and time
//---------------------------------------
      final DateTime now = DateTime.now();
      final DateTime todayStart = DateTime(now.year, now.month, now.day);

//---------------------------------------
// get all the accepted booking
//---------------------------------------
      final QuerySnapshot<Map<String, dynamic>> acceptedSnap = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('approval', isEqualTo: 'accepted')
          .get();


      int i = 0;
      while (i < acceptedSnap.docs.length) {
        final doc = acceptedSnap.docs[i];
        final Map<String, dynamic>? m = doc.data();
        if (m != null) {
//---------------------------------------
// get the booking date
//---------------------------------------
          final DateTime? bookDate = _readDate(m, ['bookingDate']);;
          if (bookDate != null) {

            final DateTime bookDayStart = DateTime(bookDate.year, bookDate.month, bookDate.day);
            String newStatus = '';

//---------------------------------------
//  check if the booking day is before today
//---------------------------------------
            if (bookDayStart.isBefore(todayStart) == true) {
              newStatus = 'ended';
            } else {
//---------------------------------------
// check if they are same day
//---------------------------------------
              if (_isSameYMD(bookDate, now) == true) {
                final TimeOfDay? tStart = _readTime(m, ['start']);
                final TimeOfDay? tEnd   = _readTime(m, ['end']);

//---------------------------------------
// get the time and date
//---------------------------------------
                if (tStart != null && tEnd != null) {
                  final DateTime startDT = DateTime(bookDate.year, bookDate.month, bookDate.day,
                      tStart.hour, tStart.minute, 0);
                  final DateTime endDT = DateTime(bookDate.year, bookDate.month, bookDate.day,
                      tEnd.hour, tEnd.minute, 0);

//---------------------------------------
// if end is after start time or now is before start time
//---------------------------------------

                  if (endDT.isAfter(startDT) == true) {
                    if (now.isBefore(startDT) == true) {

                    } else {
                      if (now.isBefore(endDT) == true) {
                        newStatus = 'ongoing'; // if now is within the booking time
                      } else {
                        newStatus = 'ended';
                      }
                    }
                  }
                }
              }
            }
            //---------------------------------------
// if there is new status
//---------------------------------------

            if (newStatus.isNotEmpty == true) {
              final String current = _readLowerStr(m, ['status']);
              //---------------------------------------
// update the status
//---------------------------------------
              if (current != newStatus) {
                await doc.reference.update({'status': newStatus});
              }
            }
          }
        }
        i = i + 1;
      }

//---------------------------------------
// now do if the booking time pass and still pending
//---------------------------------------
      final QuerySnapshot<Map<String, dynamic>> pendingSnap = await FirebaseFirestore.instance
          .collection('Bookings')
          .where('approval', isEqualTo: 'pending')
          .get();

      int j = 0;
      while (j < pendingSnap.docs.length) {
        final doc = pendingSnap.docs[j];
        final Map<String, dynamic>? m = doc.data();
        if (m != null) {
          //---------------------------------------
// get the booking date
//---------------------------------------
          final DateTime? bookDate = _readBookingDate(m);
          if (bookDate != null) {
            final DateTime bookDayStart = DateTime(bookDate.year, bookDate.month, bookDate.day);
            bool shouldReject = false;

            //---------------------------------------
// if booking day is before today turn it to reject
//---------------------------------------
            if (bookDayStart.isBefore(todayStart) == true) {
              shouldReject = true;
            } else {
//---------------------------------------
// if today , compare the strt time
//---------------------------------------
              if (_isSameYMD(bookDate, now) == true) {
                final TimeOfDay? tStart = _readTime(m, ['start']);
                if (tStart != null) {
                  final DateTime startDT = DateTime(bookDate.year, bookDate.month, bookDate.day,
                      tStart.hour, tStart.minute, 0);
                  //---------------------------------------
// if now is before the start
//---------------------------------------
                  if (now.isBefore(startDT) == false) {
                    shouldReject = true;
                  }
                }
              }
            }

//---------------------------------------
// if it should reject is true then set approval = rejected
//---------------------------------------

            if (shouldReject == true) {
              final String currAppr = _readLowerStr(m, ['approval']);
              if (currAppr != 'rejected') {
                await doc.reference.update({
                  'approval': 'rejected',
                });
              }
            }
          }
        }
        j = j + 1;
      }
    } catch (e) {
      debugPrint('housekeeping error: $e');
    }
  }

//---------------------------------------
// main build
//---------------------------------------

  @override
  Widget build(BuildContext context) {

    final double barHeight = 0.07.sh;
//---------------------------------------
// get current user
//---------------------------------------
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,

      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: Text("Booking List", style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(40.r),
              bottomRight: Radius.circular(40.r),
            ),
          ),
        ),
      ),

//---------------------------------------
// content
//---------------------------------------

      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
//---------------------------------------
// show date
//---------------------------------------
            _dateHeaderRow(),

//---------------------------------------
// clear button if needed
//---------------------------------------
            _clearCenterIfNeeded(),

            SizedBox(height: 8.h),
            Divider(height: 1.h, color: const Color(0xFFEAEAEA)),
            SizedBox(height: 8.h),

//---------------------------------------
// if use not sign in
//---------------------------------------
            if (user == null)
              Expanded(
                child: Center(
                  child: Text(
                    "Please sign in to see your bookings.",
                    style: TextStyle(fontSize: 14.sp, color: Colors.black54),
                  ),
                ),
              )
            else
            //---------------------------------------
// use stream to get booking from database
//---------------------------------------
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('Bookings')
                      .where('userId', isEqualTo: user.uid)
                      .where('deleted', isEqualTo: false)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError == true) {
                      return Center(
                        child: Text(
                          "Failed to load bookings",
                          style: TextStyle(fontSize: 14.sp, color: Colors.redAccent),
                        ),
                      );
                    }

//---------------------------------------
// if booking is empty
//---------------------------------------

                    if (snap.hasData != true || snap.data == null || snap.data!.docs.isEmpty == true) {
                      return Center(
                        child: Text(
                          "No bookings found.",
                          style: TextStyle(fontSize: 14.sp, color: Colors.black54),
                        ),
                      );
                    }

//---------------------------------------
// get the doc
//----------------------------------------
                    final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = snap.data!.docs;

                    List<QueryDocumentSnapshot<Map<String, dynamic>>> filteredDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
//---------------------------------------
// if no filter date
//---------------------------------------
                    if (_filterDate == null) {
                      filteredDocs = docs;
                    } else {
                      int j = 0;
                      while (j < docs.length) {
                        final Map<String, dynamic> m = docs[j].data();
//---------------------------------------
// get the booking date
//---------------------------------------
                        final DateTime? bdate = _readDate(m, ['bookingDate']);
                        if (bdate != null) {
//---------------------------------------
// check with filter date, if it is true then add it to filter doc
//---------------------------------------
                          if (_isSameDay(bdate, _filterDate!) == true) {
                            filteredDocs.add(docs[j]);// keep this doc
                          }
                        }
                        j = j + 1;// next doc
                      }
                    }

//---------------------------------------
// if empty show no booking
//---------------------------------------
                    if (filteredDocs.isEmpty == true) {
                      return Center(
                        child: Text(
                          "No bookings for this date.",
                          style: TextStyle(fontSize: 14.sp, color: Colors.black54),
                        ),
                      );
                    }

//---------------------------------------
// if have then sort by start time by ascending order
//---------------------------------------
                    filteredDocs.sort((a, b) {
                      final DateTime? sa = _composeDateTime(a.data(), ['start']);
                      final DateTime? sb = _composeDateTime(b.data(), ['start']);

                      if (sa == null && sb == null) { return 0; }
                      if (sa == null) { return 1; }
                      if (sb == null) { return -1; }

                      return sa.compareTo(sb);
                    });

                    final byDate = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
                    final DateFormat keyFmt = DateFormat('yyyy-MM-dd');

                    int k = 0;
                    while (k < filteredDocs.length) {
                      final doc = filteredDocs[k];
                      final Map<String, dynamic> m = doc.data();

//---------------------------------------
// parse the booking date and add back into a new list
//---------------------------------------
                      final DateTime? bdate = _readDate(m, ['bookingDate']);
                      if (bdate != null) {
//---------------------------------------
// format the date key
//---------------------------------------
                        final String key = keyFmt.format(bdate);

//---------------------------------------
// if the key is not exist yet, create the key
//---------------------------------------
                        if (byDate.containsKey(key) == false) {
                          byDate[key] = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                        }
//---------------------------------------
// Then the date belongs to the key will be added into the list belong to the key
//---------------------------------------
                        byDate[key]!.add(doc);
                      }
                      k = k + 1;
                    }

                    final List<String> futureKeys = <String>[];
                    final List<String> pastKeys = <String>[];
//---------------------------------------
// get today date and now time
//---------------------------------------
                    final DateTime now = DateTime.now();
                    final DateTime todayOnly = DateTime(now.year, now.month, now.day);
//---------------------------------------
// sort them by adding them into different list , future day list and past day list
//---------------------------------------
                    for (final kd in byDate.keys) {
                      final DateTime d = DateTime.parse(kd);
                      final DateTime dOnly = DateTime(d.year, d.month, d.day);
                      if (dOnly.isBefore(todayOnly)) {
                        pastKeys.add(kd);
                      } else {
                        futureKeys.add(kd);
                      }
                    }
//---------------------------------------
// sort those list by date, then place future key first then place past keys
//---------------------------------------
                    futureKeys.sort((a, b) => DateTime.parse(a).compareTo(DateTime.parse(b)));
                    pastKeys.sort((a, b) => DateTime.parse(b).compareTo(DateTime.parse(a)));

                    final List<String> keys = <String>[...futureKeys, ...pastKeys];

//---------------------------------------
// design the list
//---------------------------------------
                    return ListView.builder(
                      padding: EdgeInsets.only(top: 6.h, bottom: 14.h),
                      itemCount: keys.length,
                      itemBuilder: (context, idx) {
                        final String kdate = keys[idx];
//---------------------------------------
// parse the date then format it to a full date and time
//---------------------------------------
                        final DateTime parsed = DateTime.parse(kdate);
                        final String headerText = _formatFullDate(parsed);

                        final List<QueryDocumentSnapshot<Map<String, dynamic>>> group =
                            byDate[kdate] ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                        final List<Widget> rows = <Widget>[];
                        int i = 0;
                        while (i < group.length) {
                          final doc = group[i];
                          final Map<String, dynamic> m = doc.data();
//---------------------------------------
// get id then build the booking row
//---------------------------------------

                          final String docId = doc.id;

                          final Widget row = _buildBookingRow(m, docId);
//---------------------------------------
// then add it to row
//---------------------------------------

                          rows.add(row);

                          i = i + 1;
                        }

//---------------------------------------
//design each box of booking
//---------------------------------------

                        return Container(
                          width: 1.0.sw,
                          margin: EdgeInsets.only(bottom: 16.h),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(left: 4.w, bottom: 8.h),
//---------------------------------------
// display header first
//---------------------------------------
                                child: Text(
                                  headerText,
                                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700, color: Colors.black87),
                                ),
                              ),
//---------------------------------------
// display each row
//---------------------------------------
                              Column(
                                children: rows,
                              ),
                            ],
                          ),
                        );
                      },

                    );

                  },
                ),
              ),
          ],
        ),
      ),

//---------------------------------------
// show bottom navigation bar
//---------------------------------------

      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}
