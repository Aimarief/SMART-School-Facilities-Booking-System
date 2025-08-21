import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'android_bottom_menu.dart';

// other pages (for bottom nav)
import 'android_calendar.dart';
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

  const AndroidFacilityDetails({
    Key? key,
    required this.facilityId,
    required this.facilityName,
  }) : super(key: key);

  @override
  State<AndroidFacilityDetails> createState() => _AndroidFacilityDetailsState();
}

class _AndroidFacilityDetailsState extends State<AndroidFacilityDetails> {
  // keep Facilities tab selected
  int _currentIndex = 2;

  // go back to list page
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

  // handle bottom menu taps
  void _onTabSelected(int i) {
    if (i == 2) {
      _goToList();
    } else if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidCalendar()));
    } else if (i == 1) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } else if (i == 3) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
    } else if (i == 4) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
    }
  }

  // turn "HH:mm" into "HH:mm am/pm" (keep 24h digits, only add suffix)
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

  @override
  Widget build(BuildContext context) {
    // sizes for responsiveness
    final double barHeight = MediaQuery.of(context).size.height * 0.07;
    final double sw = MediaQuery.of(context).size.width;

    // live stream of the facility doc
    final Stream<DocumentSnapshot<Map<String, dynamic>>> docStream = FirebaseFirestore.instance
        .collection('Facilities')
        .doc(widget.facilityId)
        .snapshots();

    return Scaffold(
      // purple app bar with back + close
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

      // body content
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docStream,
        builder: (context, snap) {
          // show loader
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // missing doc
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Facility not found'));
          }

          // read facility data
          final Map<String, dynamic> data = snap.data!.data()!;

          // facility name
          String name = '';
          if (data.containsKey('name') && data['name'] is String) {
            name = data['name'];
          } else {
            name = widget.facilityName;
          }

          // facility image from assets
          String imageName = '';
          if (data.containsKey('imageName') && data['imageName'] is String) {
            imageName = (data['imageName'] as String).trim();
          }
          String facilityImagePath = '';
          if (imageName.isNotEmpty) {
            facilityImagePath = 'asset/image/$imageName';
          }

          // availability flag
          bool active = false;
          if (data.containsKey('active') && data['active'] is bool) {
            active = data['active'];
          }

          // reason why facility is inactive (from database)
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


          // available time
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
          final String timeRange = 'From ${_toAmPm(start24)} to ${_toAmPm(end24)}';

          // location
          String location = '';
          if (data.containsKey('location') && data['location'] is String) {
            location = data['location'];
          }

          // description
          String description = '';
          if (data.containsKey('details') && data['details'] is String) {
            description = data['details'];
          }

          // booking duration text
          String durationText = '';
          if (data.containsKey('bookingDurationHours')) {
            final dynamic dur = data['bookingDurationHours'];
            if (dur is int) {
              if (dur == 1) {
                durationText = '1 hour';
              } else {
                durationText = '$dur hours';
              }
            } else if (dur is double) {
              final int intPart = dur.toInt();
              if (dur == intPart) {
                if (intPart == 1) {
                  durationText = '1 hour';
                } else {
                  durationText = '$intPart hours';
                }
              } else {
                durationText = '$dur hours';
              }
            } else {
              durationText = dur.toString();
            }
          }

          // responsive image height
          double imgH = sw * 0.75;
          if (imgH < 240.h) {
            imgH = 240.h;
          } else if (imgH > 420.h) {
            imgH = 420.h;
          }

          // manager id
          String managerId = '';
          if (data.containsKey('managerId') && data['managerId'] is String) {
            managerId = data['managerId'];
          }

          // manager stream
          final Stream<DocumentSnapshot<Map<String, dynamic>>> mgrStream = FirebaseFirestore.instance
              .collection('UserInformation')
              .doc(managerId)
              .snapshots();

          // page content
          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // facility image (placeholder if empty)
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

                // content at 90% width
                SizedBox(
                  width: sw * 0.90,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // name + small status box
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

                      // time range
                      Text(
                        timeRange,
                        style: TextStyle(fontSize: 14.sp, color: Colors.black87, fontWeight: FontWeight.w500),
                      ),

                      // red warning when unavailable
                      // red warning when unavailable
                      if (active == false) ...[
                        SizedBox(height: 12.h),

                        // build the message using inactiveReason (fallback if empty)
                        Builder(
                          builder: (_) {
                            String reasonMsg = '';
                            if (inactiveReason.isNotEmpty) {
                              reasonMsg = inactiveReason;        // show database reason
                            } else {
                              reasonMsg = 'This facility is currently unavailable'; // fallback
                            }

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

                      // manager heading
                      Text('Manager', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                      SizedBox(height: 6.h),

                      // manager card
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        // listen to manager document live
                        stream: mgrStream,
                        builder: (context, mgrSnap) {
                          // show small loader box while manager data loading
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

                          // prepare simple map for manager values
                          Map<String, dynamic> mm = <String, dynamic>{};
                          if (mgrSnap.hasData) {
                            if (mgrSnap.data != null) {
                              if (mgrSnap.data!.data() != null) {
                                mm = mgrSnap.data!.data()!;
                              }
                            }
                          }

                          // read manager name
                          String username = '';
                          if (mm.containsKey('username')) {
                            if (mm['username'] is String) {
                              username = mm['username'];
                            }
                          }
                          if (username.isEmpty) {
                            if (mm.containsKey('name')) {
                              if (mm['name'] is String) {
                                username = mm['name'];
                              }
                            }
                          }

                          // read manager email
                          String email = '';
                          if (mm.containsKey('email')) {
                            if (mm['email'] is String) {
                              email = mm['email'];
                            }
                          }

                          // read manager contact
                          String contact = '';
                          if (mm.containsKey('contact')) {
                            if (mm['contact'] is String) {
                              contact = mm['contact'];
                            }
                          }

                          // build manager image asset path if present
                          String managerAssetPath = '';
                          final dynamic imgNameDyn = mm['profileImageName'];
                          if (imgNameDyn is String) {
                            final String trimmed = imgNameDyn.trim();
                            if (trimmed.isNotEmpty) {
                              managerAssetPath = 'asset/image/$trimmed';
                            }
                          }

                          // check requireApproval from the facility doc (data comes from outer scope)
                          bool requireApproval = false;
                          if (data.containsKey('requireApproval')) {
                            if (data['requireApproval'] is bool) {
                              requireApproval = data['requireApproval'];
                            } else {
                              // simple conversion if stored as string/number
                              final v = data['requireApproval'];
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

                          // NOTE:
                          // 'active' is already read above from the facility doc (outer scope).
                          // If active == false -> we will NOT show the Book button.

                          // return the whole section
                          return Column(
                            children: [
                              // manager info card
                              // manager info card (auto height so it never overflows)
                              Container(
                                width: double.infinity,
                                // let height grow; keep a comfortable minimum height
                                constraints: BoxConstraints(minHeight: 135.h),
                                padding: EdgeInsets.all(10.w),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE2CCFF),
                                  borderRadius: BorderRadius.circular(12.r),
                                ),
                                child: Row(
                                  // top-align so long texts add lines downward (no overflow)
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // left: image or grey placeholder (fixed box)
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

                                    // right: fields (let it wrap + grow)
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min, // only as tall as needed
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


                              SizedBox(height: 12.h),

                              // show info box only if this facility needs approval
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

                              // Book button:
                              // If active == true -> show button
                              // If active == false -> do NOT show (hide)
                              Builder(
                                builder: (_) {
                                  if (active == true) {
                                    return SizedBox(
                                      width: sw * 0.90, // 90% screen width
                                      height: 48.h,
                                      child: ElevatedButton(
                                        // purple background (#8620E5)
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF8620E5),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10.r),
                                          ),
                                        ),
                                        onPressed: () {
                                          Navigator.push(context, MaterialPageRoute(
                                            builder: (_) => Booking_Date(
                                              facilityId: widget.facilityId,
                                              facilityName: name,
                                            ),
                                          ));
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
                                    // active == false -> return an empty box (no button displayed)
                                    return const SizedBox.shrink();
                                  }
                                },
                              ),
                            ],
                          );
                        },
                      ),



                      SizedBox(height: 16.h),

                      // ------------------------
// Review summary (read-only)
// Subcollection: Facilities/{facilityId}/Rating
// Each doc should have a numeric field "rating" (1..5) and maybe "review" text
// ------------------------
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        // listen to all rating docs for this facility
                        stream: FirebaseFirestore.instance
                            .collection('Facilities')
                            .doc(widget.facilityId)
                            .collection('Rating')
                            .snapshots(),
                        builder: (context, rateSnap) {
                          // show spinner while loading
                          if (rateSnap.connectionState == ConnectionState.waiting) {
                            return Center(
                              child: SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator()),
                            );
                          }

                          // count how many ratings + sum all rating values
                          int count = 0;
                          double total = 0.0;

                          if (rateSnap.hasData) {
                            final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = rateSnap.data!.docs;
                            count = docs.length;

                            for (final d in docs) {
                              final Map<String, dynamic> r = d.data();

                              // get "rating" value (int/double/string) in a safe way
                              if (r.containsKey('rating')) {
                                final dynamic v = r['rating'];
                                if (v is int) {
                                  total = total + v.toDouble();
                                } else if (v is double) {
                                  total = total + v;
                                } else if (v is String) {
                                  final double? p = double.tryParse(v);
                                  if (p != null) {
                                    total = total + p;
                                  }
                                }
                              }
                            }
                          }

                          // compute average = total / count (if no rating -> 0.0)
                          double avg = 0.0;
                          if (count > 0) {
                            avg = total / count;
                          } else {
                            avg = 0.0;
                          }

                          // format average text with 1 decimal, e.g. "4.0"
                          String avgText = avg.toStringAsFixed(1);

                          // build "x ratings" / "1 rating" label without ternary
                          String countLabel = '';
                          if (count == 1) {
                            countLabel = '1 rating';
                          } else {
                            countLabel = '$count ratings';
                          }

                          // UI card
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
                                // title
                                Text(
                                  'Review',
                                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                                ),
                                SizedBox(height: 4.h),

                                // subtitle
                                Text(
                                  'Overall rating',
                                  style: TextStyle(fontSize: 13.sp, color: Colors.black54),
                                ),
                                SizedBox(height: 8.h),

                                // big average number
                                Text(
                                  avgText,
                                  style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w700),
                                ),
                                SizedBox(height: 6.h),

                                // 5 stars (read-only)
                                _buildStars(avg),

                                SizedBox(height: 6.h),

                                // how many users rated
                                Text(
                                  countLabel,
                                  style: TextStyle(fontSize: 12.5.sp, color: Colors.black87, fontWeight: FontWeight.w500),
                                ),

                                SizedBox(height: 10.h),

                                // "View more" button (no action for now)
                                SizedBox(
                                  height: 36.h,
                                  child: OutlinedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AndroidRatingReview(
                                            facilityId: widget.facilityId,
                                            facilityName: name, // use the resolved facility name variable you already have
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

      // bottom menu
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}

// small helper to render "Label: Value" so easier to write the value later no need repeat
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
            softWrap: true, // wraps long text
          ),
        ),
      ],
    ),
  );
}
// build 5 stars based on average value (0.0 to 5.0). Read-only.
Widget _buildStars(double avg) {
  // list to hold 5 star icons
  final List<Widget> list = <Widget>[];

  // loop from 1 to 5 to decide each star
  for (int i = 1; i <= 5; i++) {
    IconData icon;

    // if avg >= i -> full star
    if (avg >= i) {
      icon = Icons.star;
    } else {
      // else check if close enough for half star
      double diff = i - avg; // example: i=4, avg=3.6 -> diff = 0.4 (half)
      if (diff <= 0.5) {
        icon = Icons.star_half;
      } else {
        icon = Icons.star_border;
      }
    }

    list.add(Icon(icon, size: 22.sp, color: const Color(0xFFFFC107))); // yellow star
    if (i < 5) {
      list.add(SizedBox(width: 2.w)); // small gap between stars
    }
  }

  // center the stars row
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: list,
  );
}
