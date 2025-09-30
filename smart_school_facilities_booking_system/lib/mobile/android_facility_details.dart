import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'android_bottom_menu.dart';

import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart';
import 'android_rating_review.dart';
import 'android_booking_date.dart';

class AndroidFacilityDetails extends StatefulWidget {
  // incoming arguments from the list page
  final String facilityId;
  final String facilityName;
  final int userCapacity;

  const AndroidFacilityDetails({
    Key? key,
    required this.facilityId,
    required this.facilityName,
    this.userCapacity = 1,
  }) : super(key: key);

  @override
  State<AndroidFacilityDetails> createState() => _AndroidFacilityDetailsState();
}

class _AndroidFacilityDetailsState extends State<AndroidFacilityDetails> {
//---------------------------------------
// current page
//---------------------------------------
  int _currentIndex = 2;

//---------------------------------------
// navigate back
//---------------------------------------

  void _goToList() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AndroidListOfFacilities()),
      );
    }
  }

//---------------------------------------
// naviagation list
//---------------------------------------

  void _onTabSelected(int i) {
    if (i == 2) {
      _goToList();
    } else if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAgenda()));
    } else if (i == 1) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } else if (i == 3) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
    } else if (i == 4) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
    }
  }

//---------------------------------------
// change to am pm
//---------------------------------------

  String _toAmPm(String hhmm) {
    final parts = hhmm.split(':');
    int hour = 0;
    int minute = 0;

    if (parts.isNotEmpty) {
      hour = int.parse(parts[0]);
    }
    if (parts.length > 1) {
      minute = int.parse(parts[1]);
    }

    final String suffix = hour >= 12 ? 'pm' : 'am';
    final String hh = hour.toString().padLeft(2, '0');
    final String mm = minute.toString().padLeft(2, '0');
    return '$hh:$mm $suffix';
  }

  // parse any number-ish value to int (fallback used if invalid)
  int _parseCapInt(dynamic v, int fallback) {
    if (v == null) {
      return fallback;
    } else {
      if (v is int) {
        return v;
      } else {
        if (v is double) {
          return v.floor();
        } else {
          if (v is String) {
            final t = v.trim();
            final p = int.tryParse(t);
            if (p == null) {
              return fallback;
            } else {
              return p;
            }
          } else {
            return fallback;
          }
        }
      }
    }
  }

//---------------------------------------
// check if user fits the capacity
//---------------------------------------

  bool _fitsCapacity(int userCap, int reqCap, int maxCap) {
    bool withinMax;
    if (maxCap <= 0) {
      withinMax = true; // unlimited
    } else {
      if (userCap <= maxCap) {
        withinMax = true;
      } else {
        withinMax = false;
      }
    }

    if (userCap >= reqCap && withinMax == true) {
      return true;
    } else {
      return false;
    }
  }

//---------------------------------------
// main build
//---------------------------------------

  @override
  Widget build(BuildContext context) {
    // sizes for responsiveness
    final double barHeight = MediaQuery.of(context).size.height * 0.07;
    final double sw = MediaQuery.of(context).size.width;

//---------------------------------------
// get the facility from database
//---------------------------------------
    final Stream<DocumentSnapshot<Map<String, dynamic>>> docStream = FirebaseFirestore.instance
        .collection('Facilities')
        .doc(widget.facilityId)
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
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _goToList,
            tooltip: 'Back',
          ),
          title: Text(
            "Details",
            style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _goToList,
              tooltip: 'Close',
            ),
          ],
        ),
      ),

      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docStream,
        builder: (context, snap) {

          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // missing doc
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Facility not found'));
          }

//---------------------------------------
// read teh facility data
//---------------------------------------

          final Map<String, dynamic> data = snap.data!.data()!;

//---------------------------------------
// get facility name
//---------------------------------------
          String name = '';
          if (data.containsKey('name') && data['name'] is String) {
            name = data['name'];
          } else {
            name = widget.facilityName;
          }

//---------------------------------------
// get facility image name from path and database
//---------------------------------------

          String imageName = '';
          if (data.containsKey('imageName') && data['imageName'] is String) {
            imageName = (data['imageName'] as String).trim();
          }
          String facilityImagePath = '';
          if (imageName.isNotEmpty) {
            facilityImagePath = 'asset/image/$imageName';
          }

//---------------------------------------
// check if the facility is active
//---------------------------------------

          bool active = false;
          if (data.containsKey('active') && data['active'] is bool) {
            active = data['active'];
          }

//---------------------------------------
// get the inactive reason
//---------------------------------------

          String inactiveReason = '';
          if (data.containsKey('inactiveReason')) {
            final dynamic ir = data['inactiveReason'];
            if (ir is String) {
              inactiveReason = ir.trim();
            } else {
              if (ir != null) {
                inactiveReason = ir.toString();
              } else {
                inactiveReason = '';
              }
            }
          }

//---------------------------------------
// get the facility available time
//---------------------------------------

          String start24 = '';
          String end24 = '';
          if (data.containsKey('availableTime') && data['availableTime'] is Map<String, dynamic>) {
            final Map<String, dynamic> at = data['availableTime'];
            if (at.containsKey('start') && at['start'] is String) {
              start24 = at['start'];
            }
            if (at.containsKey('end') && at['end'] is String) {
              end24 = at['end'];
            }
          }
//---------------------------------------
// convert to am pm
//---------------------------------------

          final String timeRange = 'From ${_toAmPm(start24)} to ${_toAmPm(end24)}';

//---------------------------------------
// get location
//---------------------------------------
          String location = '';
          if (data.containsKey('location') && data['location'] is String) {
            location = data['location'];
          }

//---------------------------------------
// get the details description
//---------------------------------------

          String description = '';
          if (data.containsKey('details') && data['details'] is String) {
            description = data['details'];
          }

//---------------------------------------
// get the buking duration
//---------------------------------------

          String durationText = '';
          if (data.containsKey('bookingDurationHours')) {
            final dynamic dur = data['bookingDurationHours'];

                durationText = '$dur hours';

          }

//---------------------------------------
// set the imaage hight
//---------------------------------------

          double imgH = sw * 0.75;
          if (imgH < 240.h) {
            imgH = 240.h;
          } else if (imgH > 420.h) {
            imgH = 420.h;
          }

//---------------------------------------
// get manager id
//---------------------------------------

          String managerId = '';
          if (data.containsKey('managerId') && data['managerId'] is String) {
            managerId = data['managerId'];
          }

//---------------------------------------
// get req and max capacity
//---------------------------------------

          int reqCap = 1;
          int maxCap = 0;

          reqCap = _parseCapInt(data['requiredCapacity'], 1);
          maxCap = _parseCapInt(data['maxCapacity'], 0);

//---------------------------------------
// user capacity from previous page
//---------------------------------------
          final int userCap = widget.userCapacity;

//---------------------------------------
// check if it fits the capacity
//---------------------------------------
          final bool capacityOk = _fitsCapacity(userCap, reqCap, maxCap);

//---------------------------------------
// get manager Id information
//---------------------------------------
          final Stream<DocumentSnapshot<Map<String, dynamic>>> mgrStream = FirebaseFirestore.instance
              .collection('UserInformation')
              .doc(managerId)
              .snapshots();

//---------------------------------------
// whole page design
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
//---------------------------------------
// if facility no image
//---------------------------------------
                      ? Center(child: Icon(Icons.image_not_supported, size: 40.sp, color: Colors.white))
                      : Image.asset(facilityImagePath, fit: BoxFit.cover),
                ),

                SizedBox(height: 16.h),

                SizedBox(
                  width: sw * 0.90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
//---------------------------------------
// display name
//---------------------------------------
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              name.isNotEmpty ? name : widget.facilityName,
                              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(width: 8.w),
//---------------------------------------
// show is available or not
//---------------------------------------
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                            decoration: BoxDecoration(
                              color: active ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(color: active ? Colors.green : Colors.red),
                            ),
                            child: Text(
                              active ? 'Available' : 'Unavailable',
                              style: TextStyle(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w600,
                                color: active ? Colors.green : Colors.red,
                              ),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: 8.h),

//---------------------------------------
// available time for facility to book
//---------------------------------------
                      Text(
                        timeRange,
                        style: TextStyle(fontSize: 14.sp, color: Colors.black87, fontWeight: FontWeight.w500),
                      ),

                      SizedBox(height: 12.h),

//---------------------------------------
// display facility unavailable
//---------------------------------------

                      if (active == false) ...[
                        Builder(
                          builder: (_) {
                            String reasonMsg = '';
                            if (inactiveReason.isNotEmpty) {
                              reasonMsg = inactiveReason;        // show database reason
                            } else {
                              reasonMsg = 'This facility is currently unavailable'; // fallback
                            }
//---------------------------------------
// design for the unavilable box
//---------------------------------------
                            return Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFCC2CF),
                                borderRadius: BorderRadius.circular(10.r),
                                border: Border.all(color: const Color(0xFFFF0707)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.error_outline, color: const Color(0xFFFF0707), size: 20.sp),
                                  SizedBox(width: 8.w),
                                  Expanded(
                                    child: Text(
                                      reasonMsg,
                                      style: TextStyle(
                                        fontSize: 12.5.sp,
                                        color: const Color(0xFFFF0707),
                                        fontWeight: FontWeight.w600,
                                      ),
                                      softWrap: true,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],

                      SizedBox(height: 18.h),

//---------------------------------------
//  display location
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
// display description
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
// display manager
//---------------------------------------

                      Text('Manager', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                      SizedBox(height: 6.h),

//---------------------------------------
// get manager name through id
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
                            if (mgrSnap.data != null) {
                              if (mgrSnap.data!.data() != null) {
                                mm = mgrSnap.data!.data()!;
                              }
                            }
                          }

//---------------------------------------
// get manager name
//---------------------------------------

                          String username = '';
                          if (mm.containsKey('username')) {
                            if (mm['username'] is String) {
                              username = mm['username'];
                            }
                          }

//---------------------------------------
// manager email
//---------------------------------------

                          String email = '';
                          if (mm.containsKey('email')) {
                            if (mm['email'] is String) {
                              email = mm['email'];
                            }
                          }

//---------------------------------------
// contact
//---------------------------------------

                          String contact = '';
                          if (mm.containsKey('contact')) {
                            if (mm['contact'] is String) {
                              contact = mm['contact'];
                            }
                          }

//---------------------------------------
// profile image
//---------------------------------------
                          String managerAssetPath = '';
                          final dynamic imgNameDyn = mm['profileImageName'];
                          if (imgNameDyn is String) {
                            final String trimmed = imgNameDyn.trim();
                            if (trimmed.isNotEmpty) {
                              managerAssetPath = 'asset/image/$trimmed';
                            }
                          }

                          bool requireApproval = true;

 //---------------------------------------
// continue design
//---------------------------------------

                          return Column(
                            children: [
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

//---------------------------------------
// right info form manager card
//---------------------------------------
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
 //---------------------------------------
// use kv line to make it align
//---------------------------------------
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

                              SizedBox(height: 12.h),

//---------------------------------------
// require approval box
//---------------------------------------
                              if (requireApproval == true) ...[
                                Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.all(12.w),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD9F0FF),
                                    borderRadius: BorderRadius.circular(10.r),
                                    border: Border.all(color: const Color(0xFF2196F3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline, color: const Color(0xFF2196F3), size: 20.sp),
                                      SizedBox(width: 8.w),
                                      Expanded(
                                        child: Text(
                                          'This facility requires manager approval before booking.',
                                          style: TextStyle(
                                            fontSize: 13.sp,
                                            color: const Color(0xFF2196F3),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: 16.h),
                              ],

//---------------------------------------
// book button
//---------------------------------------
                              Builder(
                                builder: (_) {
//---------------------------------------
// if active then will show book button
//---------------------------------------
                                  if (active == true) {
                                    return SizedBox(
                                      width: sw * 0.90,
                                      height: 48.h,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: capacityOk ? const Color(0xFF8620E5) : Colors.grey.shade400,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10.r),
                                          ),
                                        ),
                                        onPressed: () {
//---------------------------------------
// if capacity did not meet requieement
//---------------------------------------
                                          if (capacityOk == false) {
                                            final String msg = 'Capacity does not meet requirement. ';
                                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text(msg, style: TextStyle(fontSize: 13.sp)),
                                                duration: const Duration(seconds: 2),
                                              ),
                                            );
                                            return;
                                          }
//---------------------------------------
// or else allows to enter booking page
//---------------------------------------
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => Booking_Date(
                                                facilityId: widget.facilityId,
                                                facilityName: name,
                                              ),
                                            ),
                                          );
                                        },
                                        child: Text(
                                          "Book",
                                          style: TextStyle(
                                            fontSize: 16.sp,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    );
                                  } else {
                                    return const SizedBox.shrink();
                                  }
                                },
                              ),
                            ],
                          );
                        },
                      ),

                      SizedBox(height: 16.h),

//---------------------------------------
// get the rating of facility id
//---------------------------------------
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('Facilities')
                            .doc(widget.facilityId)
                            .collection('Rating')
                            .snapshots(),
                        builder: (context, rateSnap) {
                          if (rateSnap.connectionState == ConnectionState.waiting) {
                            return Center(
                              child: SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator()),
                            );
                          }

                          // accumulate ratings
                          int count = 0;
                          double total = 0.0;

                          if (rateSnap.hasData) {
                            final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = rateSnap.data!.docs;
                            count = docs.length;

                            for (final d in docs) {
                              final Map<String, dynamic> r = d.data();
//---------------------------------------
// get all the rating and total it
//---------------------------------------
                              if (r.containsKey('rating')) {
                                final dynamic v = r['rating'];
                                if (v is int) {
                                  total = total + v.toDouble();
                                }
                              }
                            }
                          }
//---------------------------------------
// calculate average
//---------------------------------------
                          double avg = 0.0;
                          if (count > 0) {
                            avg = total / count;
                          } else {
                            avg = 0.0;
                          }

                          // format texts
                          String avgText = avg.toStringAsFixed(1);
                          String countLabel = '';

                          countLabel = '$count ratings';


//---------------------------------------
// rating box design
//---------------------------------------

                          return Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 12.w),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text('Review', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                                SizedBox(height: 4.h),
                                Text('Overall rating', style: TextStyle(fontSize: 13.sp, color: Colors.black54)),
                                SizedBox(height: 8.h),
                                Text(avgText, style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w700)),
                                SizedBox(height: 6.h),
                                _buildStars(avg),
                                SizedBox(height: 6.h),
                                Text(countLabel, style: TextStyle(fontSize: 12.5.sp, color: Colors.black87, fontWeight: FontWeight.w500)),
                                SizedBox(height: 10.h),
 //---------------------------------------
// view rating button
//---------------------------------------

                                SizedBox(
                                  height: 36.h,
                                  child: OutlinedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AndroidRatingReview(
                                            facilityId: widget.facilityId,
                                            facilityName: name,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Text('View more', style: TextStyle(fontSize: 14.sp)),
                                  ),
                                ),
                              ],
                            ),
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
      ),

//---------------------------------------
// bottom menu
//---------------------------------------

      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}

// ---------------------
// UI Helper: Label:Value
// ---------------------
Widget _kvLine({required String label, required String value}) {
  return Padding(
    padding: EdgeInsets.only(bottom: 6.h),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "$label: ",
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
            color: Colors.black,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13.sp,
              color: Colors.black87,
            ),
            softWrap: true,
          ),
        ),
      ],
    ),
  );
}

//---------------------------------------
// design for star
//---------------------------------------
Widget _buildStars(double avg) {
  final List<Widget> list = <Widget>[];

  for (int i = 1; i <= 5; i++) {
    IconData icon;

    if (avg >= i) {
      icon = Icons.star;
    } else {
      double diff = i - avg;
      if (diff <= 0.5) {
        icon = Icons.star_half;
      } else {
        icon = Icons.star_border;
      }
    }

    list.add(Icon(icon, size: 22.sp, color: const Color(0xFFFFC107)));
    if (i < 5) {
      list.add(SizedBox(width: 2.w));
    }
  }

  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: list,
  );
}
