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

//---------------------------------------
// get the item that is click from previouse page
//---------------------------------------
class AndroidBookingDetails extends StatefulWidget {
  final String bookingId;
  final String facilityId;

  const AndroidBookingDetails({
    Key? key,
    required this.bookingId,
    required this.facilityId,
  }) : super(key: key);

  @override
  State<AndroidBookingDetails> createState() => _AndroidBookingDetailsState();
}

class _AndroidBookingDetailsState extends State<AndroidBookingDetails> {
  //---------------------------------------
// current page
//---------------------------------------

  int _currentIndex = 1;

//---------------------------------------
// bottom navigation bar
//---------------------------------------

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

//---------------------------------------
// fromat date to day, date month year
//---------------------------------------

  String _formatFullDate(DateTime d) {
    final DateFormat f = DateFormat('EEE, d MMM yyyy');
    return f.format(d);
  }

//---------------------------------------
// format time to am pm
//---------------------------------------

  String _formatTime12(DateTime d) {
    final DateFormat f = DateFormat('h.mm a');
    String s = f.format(d).toLowerCase();
    s = s.replaceAll(' ', '\u00A0');
    return s;
  }

//---------------------------------------
// read and parse into date format
//---------------------------------------

  DateTime? _readDateOnly(dynamic v) {

        if (v is String) {
          DateTime? parsed;
          try { parsed = DateTime.tryParse(v); } catch (_) { parsed = null; }
          if (parsed != null) {
            return DateTime(parsed.year, parsed.month, parsed.day);
          } else {
            return null;
          }
        } else {
          return null;
        }
  }

//---------------------------------------
// get the date time
//---------------------------------------
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

//---------------------------------------
// parse time into h and m
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

        if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
          return <int>[h, m];
        } else {
          return null;
        }
      }
    }
  }

//---------------------------------------
// get the full date and time
//---------------------------------------

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
//---------------------------------------
// lock edit button when within 3 hour before the booking start
//---------------------------------------

  bool _isEditLocked(DateTime? startDT) {
    if (startDT == null) {
      return false;
    } else {
      final DateTime now = DateTime.now();
      final DateTime deadline = startDT.subtract(const Duration(hours: 3));
      if (now.isAfter(deadline)) {
        return true;  // already inside last 3 hours (or past), lock it
      } else {
        return false; // still earlier than (start - 3h), allow edit
      }
    }
  }

//---------------------------------------
// get approval text
//---------------------------------------
  String _approvalText(dynamic v) {
    if (v is bool) {
      if (v == true) { return 'approved'; } else { return 'pending'; }
    } else {
      if (v == null) { return ''; } else { return v.toString().toLowerCase(); }
    }
  }

  //---------------------------------------
// assign chip colour and back ground
//---------------------------------------

  List<Color> _chipColors(String labelLower) {
    if ( labelLower == 'accepted' || labelLower == 'upcoming') {
      return <Color>[Colors.green.shade200, Colors.green];
    } else {
      if (labelLower == 'rejected') {
        return <Color>[Colors.red.shade200, Colors.red];
      } else {
        if (labelLower == 'pending' || labelLower == 'ongoing') {
          return <Color>[Colors.amber.shade200, Colors.amber];
        } else {
          if (labelLower == 'ended') {
            return <Color>[Colors.grey.shade300, Colors.grey];
          } else {
            return <Color>[Colors.grey.shade200, Colors.grey];
          }
        }
      }
    }
  }

//---------------------------------------
// build each chip for status and approval
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
// capitalize the first word
//---------------------------------------
  String _capitalize(String s) {
    if (s.isEmpty == true) { return s; } else {
      final String first = s.substring(0, 1).toUpperCase();
      final String rest  = s.substring(1);
      return first + rest;
    }
  }

  //---------------------------------------
// for cancel amendment pop up
//---------------------------------------

  Future<void> _confirmCancelAmendment() async {
    final bool? ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            'Cancel amendment?',
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
          ),
          content: Text(
            'Are you sure you want to cancel this amendment request?',
            style: TextStyle(fontSize: 14.sp),
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
 //---------------------------------------
// close dislog when press cancel
//---------------------------------------
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop(false);
              },
              child: Text(
                'Cancel',
                style: TextStyle(fontSize: 14.sp),
              ),
            ),
//---------------------------------------
// close dialog and return true when confirm press
//---------------------------------------
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF0707),
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
              ),
              child: Text(
                'Confirm',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
//---------------------------------------
// if ok then will perform the cancel amendment proccess
//---------------------------------------
    if (ok == true) {
      await _performCancelAmendment();
    }
  }
  //---------------------------------------
// cancel amendment proccess
//---------------------------------------
  Future<void> _performCancelAmendment() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
//---------------------------------------
// get the bookings from database
//---------------------------------------

      final docRef = FirebaseFirestore.instance.collection('Bookings').doc(widget.bookingId);

      //---------------------------------------
// delete and set false to the required field
//---------------------------------------
      await docRef.set({
        'hasPendingAmendment': false,
        'amendmentPreview': FieldValue.delete(),
        'lastActivityAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      Future<void> wipe(String sub) async {
        final qs = await docRef.collection(sub).get();
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

      await wipe('Amendments');

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Amendment cancelled.')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // close spinner
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel amendment: $e')),
        );
      }
    }
  }

//---------------------------------------
// get when the rating is created and belong to the booking Id
//---------------------------------------

  Future<DateTime?> _getRatingCreatedAt(String facilityId, String bookingId) async {
    final qs = await FirebaseFirestore.instance
        .collection('Facilities')
        .doc(facilityId)
        .collection('Rating')
        .where('bookingId', isEqualTo: bookingId)
        .limit(1)
        .get();

    if (qs.docs.isEmpty) return null;

    final data = qs.docs.first.data();
    final v = data['createdAt'];

    if (v is Timestamp) return
      v.toDate();
    return null;
  }

//---------------------------------------
// main build
//---------------------------------------
  @override
  Widget build(BuildContext context) {
    final double sw = 1.0.sw;
    final double barHeight = 0.07.sh;

    //---------------------------------------
// stream for booking id and facilities
//---------------------------------------
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

      //---------------------------------------
// stream facility first
//---------------------------------------
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

//---------------------------------------
// get all facilities details
//---------------------------------------
          String name = fac['name']?.toString() ?? '';
          String imageName = fac['imageName']?.toString().trim() ?? '';
          String facilityImagePath = '';
          if (imageName.isNotEmpty == true) {
            facilityImagePath = 'asset/image/$imageName';
          }
          String location = fac['location']?.toString() ?? '';
          String description = fac['details']?.toString() ?? '';
//---------------------------------------
// get booking duration
//---------------------------------------
          String durationText = '';
          final int dur = fac['bookingDurationHours'] as int;
          durationText = '$dur hours';

//---------------------------------------
// get the manager from database
//---------------------------------------
          final String managerId = fac['managerId']?.toString() ?? '';
          final Stream<DocumentSnapshot<Map<String, dynamic>>> mgrStream =
          FirebaseFirestore.instance.collection('UserInformation').doc(managerId).snapshots();

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

//---------------------------------------
// get the booking date
//---------------------------------------
              String bookingDateField;
              bookingDateField = bk['bookingDate'];

              final DateTime? bookingDate = _readDateOnly(bookingDateField);
              DateTime? shownBookingDate = bookingDate;

              final DateTime? startDT = _composeFromBookingDate(bookingDateField, bk['start'] );
              final DateTime? endDT   = _composeFromBookingDate(bookingDateField, bk['end'] );

              final bool editLocked = _isEditLocked(startDT);

//---------------------------------------
// get and format the start and end date to am pm
//---------------------------------------
              String startStr = '--.--';
              if (startDT != null) { startStr = _formatTime12(startDT); }
              String endStr = '--.--';
              if (endDT != null) { endStr = _formatTime12(endDT); }

              String seatText = '-';
              seatText = bk['seatIndex'].toString();

              final String approval = bk['approval'].trim();
              String status = '';
              status = bk['status'].toString().toLowerCase().trim();

              bool isPending = false;
              bool isRejected = false;
              bool isEnded = false;
              bool isOngoing = false;
              bool isAccepted = false;
              if (approval == 'pending') isPending = true;
              if (approval == 'rejected') isRejected = true;
              if (approval == 'accepted') isAccepted = true;
              if (status == 'ended') isEnded = true;
              if (status == 'ongoing') isOngoing = true;


              final List<Widget> chips = <Widget>[];
//---------------------------------------
// check if amendment is complete before
//---------------------------------------
              final bool hasAmendment =
                  (bk['hasPendingAmendment'] == true);
              bool completedAmendment = false;
              if (bk.containsKey('completeAmendment')) {
                final dynamic ca = bk['completeAmendment'];
                if (ca is bool) {
                  completedAmendment = ca;
                }
              }
//---------------------------------------
// check for the status
//---------------------------------------
              if (isEnded == true) {
                final List<Color> c = _chipColors('ended');
                chips.add(_buildChip('Ended', c[0], c[1]));
              } else if (hasAmendment) {
                const Color amendBlue = Color(0xFF1D4ED8);
                chips.add(_buildChip('Amendment', Colors.white, amendBlue, textColor: amendBlue));
              } else {
                if (approval.isNotEmpty == true) {
                  final List<Color> a = _chipColors(approval);
                  chips.add(_buildChip(_capitalize(approval), a[0], a[1]));
                }
                if (approval != 'pending' && approval != 'rejected') {
                  if (status.isNotEmpty == true) {
                    final List<Color> s = _chipColors(status);
                    chips.add(_buildChip(_capitalize(status), s[0], s[1]));
                  }
                }
              }
//---------------------------------------
// decide to show which button
//---------------------------------------
              bool showEdit = false;
              bool showAmend = false;
              bool showRate = false;
              bool showCancelAmend = hasAmendment;

//---------------------------------------
// if had amendment then show cancel amendment
//---------------------------------------
              if (showCancelAmend) {
              } else {
//---------------------------------------
// if ended then show rating button
//---------------------------------------
                if (isEnded == true) {
                  showRate = true;
 //---------------------------------------
// if rejected show nothing
//---------------------------------------
                } else if (isRejected == true) {
//---------------------------------------
// if ongoing show nothing also
//---------------------------------------
                } else if (isOngoing == true) {
                } else {
//---------------------------------------
// if pending then show edit button
//---------------------------------------
                  if (isPending == true) {
                    showEdit = true;
//---------------------------------------
// if accepted and upcoming then show amendment button
//---------------------------------------
                  } else if (isAccepted == true && status == 'upcoming') {
                    showAmend = true;
                  }
                }
              }

//---------------------------------------
// then check if its within 3 hour if yes then lock the button means disable it
//---------------------------------------
              if (_isEditLocked(startDT) == true) {
                showEdit = false;
                showAmend = false;
              }
//---------------------------------------
// check if completed emendment is equal true, if yes disable the amendment button
//---------------------------------------
              final bool disableAmendButton = completedAmendment == true;


//---------------------------------------
// check if its already rated
//---------------------------------------

              bool ratedAlready = false;
              if (bk.containsKey('rated')) {
                final dynamic rv = bk['rated'];
                if (rv is bool) {
                  ratedAlready = rv == true;
                }
              }
//---------------------------------------
// prepare image size
//---------------------------------------

              double imgH = sw * 0.75;
              if (imgH < 240.h) { imgH = 240.h; } else { if (imgH > 420.h) { imgH = 420.h; } }

 //---------------------------------------
// check for amendment preview
//---------------------------------------
              Map<String, dynamic>? amend;
              if (bk['amendmentPreview'] is Map) {
                amend = Map<String, dynamic>.from(bk['amendmentPreview'] as Map);
              }
//---------------------------------------
// get all information from amendment preview  if there is amendment
//---------------------------------------
              if (hasAmendment && amend != null) {
                final dynamic amendDateField = amend['bookingDate'];
                final DateTime? amendDateOnly = _readDateOnly(amendDateField);

                final DateTime? amendStartDT = _composeFromBookingDate(amendDateField, amend['start']);
                final DateTime? amendEndDT   = _composeFromBookingDate(amendDateField, amend['end']);

                if (amendDateOnly != null) {
                  shownBookingDate = amendDateOnly;
                }

                if (amendStartDT != null) {
                  final String s = _formatTime12(amendStartDT);
                  startStr = s;
                }
                if (amendEndDT != null) {
                  final String e = _formatTime12(amendEndDT);
                  endStr = e;
                }

                final int seatNew = amend['seatIndex'];
                  seatText = seatNew.toString();
              }
//---------------------------------------
// main design for the booking details
//---------------------------------------
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
//---------------------------------------
// display image
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
// display facility name
//---------------------------------------
                    SizedBox(
                      width: sw * 0.90,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            name,
                            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),

                          SizedBox(height: 10.h),

//---------------------------------------
// display booking date
//---------------------------------------

                          if (shownBookingDate != null)
                            Text(
                              'Booking Date: ${_formatFullDate(shownBookingDate!)}',
                              style: TextStyle(fontSize: 14.sp, color: Colors.black87, fontWeight: FontWeight.w600),
                            ),

                          SizedBox(height: 12.h),

//---------------------------------------
//
//---------------------------------------

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
//---------------------------------------
// show start time
//---------------------------------------
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
//---------------------------------------
// something like devider
//---------------------------------------
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text('      |', style: TextStyle(fontSize: 16.sp, color: Colors.black45)),
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
// another devider
//---------------------------------------
                                Container(
                                  width: 2.w,
                                  height: 50.h,
                                  margin: EdgeInsets.symmetric(horizontal: 12.w),
                                  color: const Color(0xFF7E57C2),
                                ),
//---------------------------------------
// display seat
//---------------------------------------
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
//---------------------------------------
// display arppoval chip
//---------------------------------------

                                      Wrap(children: chips),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          SizedBox(height: 18.h),

//---------------------------------------
// display location
//---------------------------------------
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

//---------------------------------------
// display decription
//---------------------------------------
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

//---------------------------------------
// display duration per slot
//---------------------------------------
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

//---------------------------------------
// display manager info
//---------------------------------------
                          Text('Manager', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                          SizedBox(height: 6.h),

 //---------------------------------------
// use the manager stream builder wheich called previously
//---------------------------------------
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
                              String email = mm['email']?.toString() ?? '';
                              String contact = mm['contact']?.toString() ?? '';
                              String managerAssetPath = '';
                              final String img = mm['profileImageName']?.toString().trim() ?? '';
                              if (img.isNotEmpty == true) {
                                managerAssetPath = 'asset/image/$img';
                              }

                              return Column(
                                children: <Widget>[
//---------------------------------------
// display the card and using kv line to align them
//---------------------------------------
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
//---------------------------------------
// use place holder if no image
//---------------------------------------
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
//---------------------------------------
// use kvline to display them
//---------------------------------------
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

//---------------------------------------
// show button for cancel amendment
//---------------------------------------
                                  Builder(
                                    builder: (_) {
                                      if (showCancelAmend == true) {
                                        return SizedBox(
                                          width: sw * 0.90,
                                          height: 48.h,
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                                            ),
                                            onPressed: () => _confirmCancelAmendment(),
                                            child: Text('Cancel amendment', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                                          ),
                                        );
                                      }
//---------------------------------------
// show edit button while in pending approval
//---------------------------------------
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
                                                    approval: approval,
                                                  ),
                                                ),
                                              );
                                            },
                                            child: Text('Edit', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                                          ),
                                        );
//---------------------------------------
// if show amend button means approval is accepted and is upcoming
//---------------------------------------

                                      } else if (showAmend == true) {
//---------------------------------------
// then check if user done amendent before
//---------------------------------------
                                        final bool isAmendDisabled = disableAmendButton;
                                        final String amendText = isAmendDisabled ? 'Amendment used' : 'Request amendment';

                                        return SizedBox(
                                          width: sw * 0.90,
                                          height: 48.h,
                                          child: ElevatedButton(
                                            style: ElevatedButton.styleFrom(
 //---------------------------------------
// for disable and enable background
//---------------------------------------

                                            backgroundColor: const Color(0xFF8620E5),
                                              foregroundColor: Colors.white,
                                              disabledBackgroundColor: const Color(0xFF9E9E9E),
                                              disabledForegroundColor: Colors.white,
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                                            ),
                                            onPressed: isAmendDisabled
                                                ? null
                                                : () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => AndroidEditBooking(
                                                    bookingId: widget.bookingId,
                                                    approval: approval,
                                                  ),
                                                ),
                                              );
                                            },
                                            child: Text(amendText, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                                          ),
                                        );
                                      }

//---------------------------------------
// if it is already end , show rating button
//---------------------------------------
                                      else if (showRate == true) {
                                        return FutureBuilder<DateTime?>(
//---------------------------------------
// get the rating date if done
//---------------------------------------
                                        future: _getRatingCreatedAt(widget.facilityId, widget.bookingId),
                                          builder: (context, snap) {
                                            bool canEditRating = false;
                                            bool isDisabled = false;
                                            String btnLabel = 'Rate';
//---------------------------------------
// if use rated before
//---------------------------------------
                                            if (ratedAlready == true) {
                                              canEditRating = true;

                                              if (snap.connectionState == ConnectionState.done && snap.data != null) {
                                                final DateTime ratedAtLocal = snap.data!.toLocal();
 //---------------------------------------
// check the difference wit the created date
//---------------------------------------
                                                final Duration diff = DateTime.now().difference(ratedAtLocal);
                                                if (diff.inDays >= 7) {
                                                  canEditRating = false;
                                                }
                                              }
//---------------------------------------
// if can edit rating set the text
//---------------------------------------
                                              if (canEditRating == true) {
                                                btnLabel = 'Edit rating';
                                              } else {
                                                btnLabel = 'Rated';
                                                isDisabled = true;
                                              }
                                            } else {
                                              btnLabel = 'Rate';
                                            }
//---------------------------------------
// set the button colour
//---------------------------------------
                                            final Color btnColor = (isDisabled) ? Colors.grey : const Color(0xFF8620E5);

                                            return SizedBox(
                                              width: sw * 0.90,
                                              height: 48.h,
                                              child: ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: btnColor,
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                                                ),
                                                onPressed: isDisabled
                                                    ? null
                                                    : () {
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (_) => AndroidMakeRating(
                                                        bookingId: widget.bookingId,
                                                        facilityId: widget.facilityId,
                                                      ),
                                                    ),
                                                  );
                                                },
                                                child: Text(
                                                  btnLabel,
                                                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.white),
                                                ),
                                              ),
                                            );
                                          },
                                        );
                                      }
//---------------------------------------
// if it was rejected or ongoing, will show nothing so shrink it means just nothing
//---------------------------------------
                                      else {
                                        return const SizedBox.shrink();
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
//---------------------------------------
// bottom navigation bar
//---------------------------------------
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}

//---------------------------------------
// display them allign way
//---------------------------------------

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
