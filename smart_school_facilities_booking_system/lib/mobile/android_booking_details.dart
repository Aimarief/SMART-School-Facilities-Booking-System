import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'android_edit_booking.dart';
import 'android_make_rating.dart';
import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_list_of_facilities.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_view_booking.dart';

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

// state and navigation
class _AndroidBookingDetailsState extends State<AndroidBookingDetails> {
  int _currentIndex = 1; // this page index in bottom bar

  // bottom bar navigation
  void _onTabSelected(int i) {
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

  // format helpers
  String _formatFullDate(DateTime d) {
    final DateFormat f = DateFormat('EEE, d MMM yyyy');
    return f.format(d);
  }

  // format helpers
  String _formatTime12(DateTime d) {
    final DateFormat f = DateFormat('h.mm a');
    String s = f.format(d).toLowerCase();
    s = s.replaceAll(' ', '\u00A0');
    return s;
  }

  // read date-only from mixed fields
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

  // read DateTime (legacy Timestamp/DateTime support)
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

  // parse 24h time string like "13:30","1330","13.30","9:05"
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
          return <int>[h, m];
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
          return <int>[h, m];
        } else {
          return null;
        }
      }
    }
  }

  // compose DateTime from bookingDate + time string or use existing Timestamp
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

  bool _isEditLocked(DateTime? startDT) {
    if (startDT == null) {
      return false; // cannot decide, so do not lock
    } else {
      final DateTime now = DateTime.now();                           // get current local time
      final DateTime deadline = startDT.subtract(const Duration(hours: 3)); // 3 hours before start
      if (now.isAfter(deadline)) {
        return true;  // already inside last 3 hours (or past), lock it
      } else {
        return false; // still earlier than (start - 3h), allow edit
      }
    }
  }

  // approval text to lowercase string
  String _approvalText(dynamic v) {
    if (v is bool) {
      if (v == true) { return 'approved'; } else { return 'pending'; }
    } else {
      if (v == null) { return ''; } else { return v.toString().toLowerCase(); }
    }
  }

  // chip color resolver
  List<Color> _chipColors(String labelLower) {
    if (labelLower == 'approved' || labelLower == 'accept' || labelLower == 'accepted' || labelLower == 'upcoming') {
      return <Color>[Colors.green.shade200, Colors.green];
    } else {
      if (labelLower == 'rejected') {
        return <Color>[Colors.red.shade200, Colors.red];
      } else {
        if (labelLower == 'pending' || labelLower == 'ongoing') {
          return <Color>[Colors.amber.shade200, Colors.amber];
        } else {
          if (labelLower == 'ended' || labelLower == 'complete' || labelLower == 'completed') {
            return <Color>[Colors.grey.shade300, Colors.grey];
          } else {
            return <Color>[Colors.grey.shade200, Colors.grey];
          }
        }
      }
    }
  }

  // chip builder
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

  // capitalize first letter
  String _capitalize(String s) {
    if (s.isEmpty == true) { return s; } else {
      final String first = s.substring(0, 1).toUpperCase();
      final String rest  = s.substring(1);
      return first + rest;
    }
  }

  // build
  @override
  Widget build(BuildContext context) {
    final double sw = 1.0.sw;
    final double barHeight = 0.07.sh;

    // live streams
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
          actions: <Widget>[
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

          // facility fields
          String name = fac['name']?.toString() ?? '';
          String imageName = fac['imageName']?.toString().trim() ?? '';
          String facilityImagePath = '';
          if (imageName.isNotEmpty == true) {
            facilityImagePath = 'asset/image/$imageName';
          }
          String location = fac['location']?.toString() ?? '';
          String description = fac['details']?.toString() ?? '';
          String managerId = fac['managerId']?.toString() ?? '';

          // duration text
          String durationText = '';
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
              if (dur != null) { durationText = dur.toString(); } else { durationText = ''; }
            }
          }

          // require approval
          bool requireApproval = false;
          final dynamic vRequire = fac['requireApproval'];
          if (vRequire is bool) {
            requireApproval = vRequire;
          } else {
            if (vRequire is String) {
              if (vRequire.toLowerCase() == 'true') {
                requireApproval = true;
              } else {
                requireApproval = false;
              }
            } else if (vRequire is num) {
              if (vRequire != 0) {
                requireApproval = true;
              } else {
                requireApproval = false;
              }
            }
          }

          // manager stream
          final Stream<DocumentSnapshot<Map<String, dynamic>>> mgrStream =
          FirebaseFirestore.instance.collection('UserInformation').doc(managerId).snapshots();

          // booking stream
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

              // booking fields
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

              final bool editLocked = _isEditLocked(startDT);

              String startStr = '--.--';
              if (startDT != null) { startStr = _formatTime12(startDT); }
              String endStr = '--.--';
              if (endDT != null) { endStr = _formatTime12(endDT); }



              String seatText = '-';
              if (bk.containsKey('seatIndex')) {
                if (bk['seatIndex'] != null) { seatText = bk['seatIndex'].toString(); }
              } else {
                if (bk.containsKey('slotIndex')) {
                  if (bk['slotIndex'] != null) { seatText = bk['slotIndex'].toString(); }
                }
              }

              final String approval = _approvalText(bk['approval']).trim();
              String status = '';
              if (bk.containsKey('status')) {
                if (bk['status'] != null) { status = bk['status'].toString().toLowerCase().trim(); }
              } else {
                if (bk.containsKey('state')) {
                  if (bk['state'] != null) { status = bk['state'].toString().toLowerCase().trim(); }
                }
              }

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

              if (isEnded == true) {
                final List<Color> c = _chipColors('ended');
                chips.add(_buildChip('Ended', c[0], c[1]));
              } else {
                if (approval.isNotEmpty == true) {
                  final List<Color> a = _chipColors(approval);
                  chips.add(_buildChip(_capitalize(approval), a[0], a[1]));
                }
                if (isPending == false && isRejected == false) {
                  if (status.isNotEmpty == true) {
                    final List<Color> s = _chipColors(status);
                    chips.add(_buildChip(_capitalize(status), s[0], s[1]));
                  }
                }
              }

              bool showEdit = false;
              bool showRate = false;

              if (isEnded == true) {
                showRate = true;
              } else {
                if (isRejected == true) {
                  showEdit = false;
                  showRate = false;
                } else {
                  if (isOngoing == true) {
                    showEdit = false;
                    showRate = false;
                  } else {
                    if (isPending == true) {
                      showEdit = true; // pending can edit
                    } else {
                      if (requireApproval == true) {
                        showEdit = false; // approved + requireApproval => do not edit
                      } else {
                        showEdit = true;  // normal case => can edit
                      }
                    }
                  }
                }
              }

// APPLY THE 3-HOUR LOCK (final gate):
              if (showEdit == true) {
                if (editLocked == true) {
                  showEdit = false; // hide Edit once we are within 3 hours to start
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

              double imgH = sw * 0.75;
              if (imgH < 240.h) { imgH = 240.h; } else { if (imgH > 420.h) { imgH = 420.h; } }

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    // facility image
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

                    // main content
                    SizedBox(
                      width: sw * 0.90,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          // name
                          Text(
                            name,
                            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                          SizedBox(height: 10.h),

                          // booking date
                          if (bookingDate != null)
                            Text(
                              'Booking Date: ${_formatFullDate(bookingDate)}',
                              style: TextStyle(fontSize: 14.sp, color: Colors.black87, fontWeight: FontWeight.w600),
                            ),

                          SizedBox(height: 12.h),

                          // time + slot + chips
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE9D7FF),
                              borderRadius: BorderRadius.circular(14.r),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: const Color(0x22000000),
                                  blurRadius: 8.r,
                                  offset: Offset(0, 3.h),
                                ),
                              ],
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: <Widget>[
                                // times
                                SizedBox(
                                  width: 78.w,
                                  height: 68.h,
                                  child: Stack(
                                    children: <Widget>[
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
                                        child: Text('      |', style: TextStyle(fontSize: 16.sp, color: Colors.black45)),
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

                                // vertical divider
                                Container(
                                  width: 2.w,
                                  height: 50.h,
                                  margin: EdgeInsets.symmetric(horizontal: 12.w),
                                  color: const Color(0xFF7E57C2),
                                ),

                                // slot + chips
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          Icon(Icons.event_seat, size: 18.w, color: Colors.black54),
                                          Text(
                                            'Slot : ',
                                            style: TextStyle(fontSize: 13.sp, color: Colors.black87, fontWeight: FontWeight.w600),
                                          ),
                                          SizedBox(width: 6.w),
                                          Text(
                                            seatText,
                                            style: TextStyle(fontSize: 13.sp, color: Colors.black87, fontWeight: FontWeight.w600),
                                          ),
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

                          // location
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

                          // description
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

                          // duration
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

                          // manager header
                          Text('Manager', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                          SizedBox(height: 6.h),

                          // manager card and action button
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
                                final Map<String, dynamic>? dd = mgrSnap.data!.data();
                                if (dd != null) { mm = dd; }
                              }

                              String username = mm['username']?.toString() ?? '';
                              if (username.isEmpty == true) {
                                username = mm['name']?.toString() ?? '';
                              }
                              String email = mm['email']?.toString() ?? '';
                              String contact = mm['contact']?.toString() ?? '';

                              String managerAssetPath = '';
                              final String img = mm['profileImageName']?.toString().trim() ?? '';
                              if (img.isNotEmpty == true) {
                                managerAssetPath = 'asset/image/$img';
                              }

                              return Column(
                                children: <Widget>[
                                  // manager info card
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
                                      children: <Widget>[
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
                                            children: <Widget>[
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

                                  // bottom single action (Edit or Rate or none)
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
                                          Color btnColor;
                                          String btnLabel;
                                          if (ratedAlready == true) {
                                            btnColor = Colors.grey;
                                            btnLabel = 'Rated';
                                          } else {
                                            btnColor = const Color(0xFF8620E5);
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
                                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('User have rated on current booking', style: TextStyle(fontSize: 13.sp))),
                                                  );
                                                } else {
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

// small ui helper
Widget _kvLine({required String label, required String value}) {
  return Padding(
    padding: EdgeInsets.only(bottom: 6.h),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$label: ',
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
