import 'dart:convert'; // decode Base64 strings to bytes
import 'dart:typed_data'; // typed bytes for Image.memory

import 'package:flutter/material.dart'; // core UI toolkit
import 'package:flutter_screenutil/flutter_screenutil.dart'; // responsive .w .h .sp
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore streams and reads

// bottom nav and main sections
import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart';

class AndroidRatingReview extends StatefulWidget {

  final String facilityId;
  final String facilityName;

  // basic constructor
  const AndroidRatingReview({
    Key? key,
    required this.facilityId,
    required this.facilityName,
  }) : super(key: key);

  @override
  State<AndroidRatingReview> createState() => _AndroidRatingReviewState();
}

class _AndroidRatingReviewState extends State<AndroidRatingReview> {
//---------------------------------------
// current page
//---------------------------------------

  int _currentIndex = 2;

//---------------------------------------
// go back navigation
//---------------------------------------

  void _goBackToDetails() {
    Navigator.pop(context);
  }

//---------------------------------------
// close the page
//---------------------------------------

  void _closeToList() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => AndroidListOfFacilities()),
          (route) => false,
    );
  }

//---------------------------------------
// navigation index
//---------------------------------------

  void _onTabSelected(int i) {
    if (i == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
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
// main build
//---------------------------------------

  @override
  Widget build(BuildContext context) {

    final double barHeight = MediaQuery.of(context).size.height * 0.07;

    final String fid = widget.facilityId;

//---------------------------------------
// get the rating from database
//---------------------------------------

    final Stream<QuerySnapshot<Map<String, dynamic>>> ratingStream = FirebaseFirestore.instance
        .collection('Facilities')
        .doc(fid)
        .collection('Rating')
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
            onPressed: _goBackToDetails, // go back to details
            tooltip: 'Back',
          ),
          title: Text(
            "Rating and Reviews", // page title
            style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _closeToList, // close to list
              tooltip: 'Close',
            ),
          ],
        ),
      ),

      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
//---------------------------------------
// get the rating from database
//---------------------------------------
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ratingStream,
              builder: (context, snap) {

                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator()),
                  );
                }

                int count = 0;
                double total = 0.0;

                // collect numbers robustly
                if (snap.hasData) {
                  final docs = snap.data!.docs;
                  count = docs.length;
                  for (final d in docs) {
                    final m = d.data();
                    if (m.containsKey('rating')) {
                      final v = m['rating'];
                      if (v is int) {
                        total += v.toDouble();
                      }
                    }
                  }
                }
//---------------------------------------
// compute the average
//---------------------------------------
                double avg;
                if (count > 0) {
                  avg = total / count;
                } else {
                  avg = 0.0;
                }

//---------------------------------------
// format to 1 decimal
//---------------------------------------

                final String avgText = avg.toStringAsFixed(1);

                // build ratings count label
                String countLabel = '';

                countLabel = '$count ratings';

//---------------------------------------
// design the top review card
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
//---------------------------------------
//review text
//---------------------------------------

                      Text('Review', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                      SizedBox(height: 4.h),
//---------------------------------------
// overall rating
//---------------------------------------
                      Text('Overall rating', style: TextStyle(fontSize: 13.sp, color: Colors.black54)),
                      SizedBox(height: 8.h),
                      Text(avgText, style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w700)),
                      SizedBox(height: 6.h),
//---------------------------------------
// star design
//---------------------------------------
                      _buildStars(avg),
                      SizedBox(height: 6.h),
//---------------------------------------
// total rating
//---------------------------------------
                      Text(
                        countLabel,
                        style: TextStyle(fontSize: 12.5.sp, color: Colors.black87, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                );
              },
            ),

            SizedBox(height: 14.h),

//---------------------------------------
// get the rating database again
//---------------------------------------
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ratingStream,
              builder: (context, snap) {

                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator()),
                  );
                }

//---------------------------------------
// if empty
//---------------------------------------

                final docs = (snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]).toList();
//---------------------------------------
// sort the data by date
//---------------------------------------

                docs.sort((a, b) {
                  final ma = a.data();
                  final mb = b.data();
                  final ta = (ma['createdAt'] is Timestamp) ? (ma['createdAt'] as Timestamp).millisecondsSinceEpoch : 0;
                  final tb = (mb['createdAt'] is Timestamp) ? (mb['createdAt'] as Timestamp).millisecondsSinceEpoch : 0;
                  return tb.compareTo(ta);
                });

//---------------------------------------
// if no review
//---------------------------------------
                if (docs.isEmpty == true) {
                  return Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 20.h),
                    alignment: Alignment.center,
                    child: Text('No reviews yet', style: TextStyle(fontSize: 14.sp, color: Colors.black54)),
                  );
                }

//---------------------------------------
// build the review design
//---------------------------------------
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10.h),
                  itemBuilder: (context, i) {
                    final m = docs[i].data();

//---------------------------------------
// get user id
//---------------------------------------

                    String userId = '';
                    if (m['userId'] is String) {
                      userId = m['userId'];
                    }

//---------------------------------------
// get review text
//---------------------------------------

                    String review = '';
                    if (m['review'] is String) {
                      review = m['review'];
                    }

//---------------------------------------
// get and count rating again
//---------------------------------------

                    double rating = 0.0;
                    if (m['rating'] is int) {
                      rating = (m['rating'] as int).toDouble();
                    } else {
                      if (m['rating'] is double) {
                        rating = m['rating'] as double;
                      }
                    }
                    if (rating < 0) {
                      rating = 0;
                    } else {
                      if (rating > 5) {
                        rating = 5;
                      }
                    }

//---------------------------------------
// get the time created at
//---------------------------------------

                    DateTime? createdAt;
                    final dynamic ca = m['createdAt'];
                      createdAt = ca.toDate().toLocal();

//---------------------------------------
// start list out the review in this format
//---------------------------------------
                    return _reviewTile(
                      userId: userId,
                      rating: rating,
                      review: review,
                      createdAt: createdAt,
                    );
                  },
                );
              },
            ),
          ],
        ),
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

//---------------------------------------
// each of the review and rating design
//---------------------------------------

  Widget _reviewTile({
    required String userId,
    required double rating,
    required String review,
    DateTime? createdAt,
  }) {
    String dateText = '-';
    if (createdAt != null) {
      dateText = _fmtDate(createdAt);
    }

//---------------------------------------
// get userinformation from database
//---------------------------------------

    Stream<DocumentSnapshot<Map<String, dynamic>>>? userStream;
    if (userId.isNotEmpty == true) {
      userStream = FirebaseFirestore.instance
          .collection('UserInformation')
          .doc(userId)
          .snapshots();
    }

    //---------------------------------------
// display
//---------------------------------------

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userStream,
        builder: (context, snap) {

          String displayName = 'Anonymous';

//---------------------------------------
// if no user
//---------------------------------------

          if (userStream == null) {
            displayName = 'Anonymous';
          } else {
            // keep placeholder while loading
            if (snap.connectionState == ConnectionState.waiting) {
              displayName = 'Anonymous';
            } else {
//---------------------------------------
// get the name
//---------------------------------------
              if (snap.hasData && snap.data != null && snap.data!.exists) {
                final Map<String, dynamic>? um = snap.data!.data();
                if (um != null) {
                    if (um['username'] != null) {
                      displayName = um['username'].toString();
                    }
                }
              }
            }
          }

          //---------------------------------------
// build the desgin
//---------------------------------------

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
 //---------------------------------------
// display image
//---------------------------------------
                  ClipRRect(
                    borderRadius: BorderRadius.circular(40.r),
                    child: _userAvatar(userId),
                  ),
                  SizedBox(width: 12.w),
 //---------------------------------------
// display name
//---------------------------------------
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4.h),
//---------------------------------------
// display star
//---------------------------------------
                        _buildStars(rating),
                      ],
                    ),
                  ),
                ],
              ),

              SizedBox(height: 8.h),

              // review message text
              Text(
                review,
                style: TextStyle(fontSize: 13.sp, color: Colors.black87),
                softWrap: true,
              ),

              SizedBox(height: 6.h),

              // right-aligned created date
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  dateText,
                  style: TextStyle(fontSize: 12.sp, color: Colors.black54),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

//---------------------------------------
// get the image
//---------------------------------------

  Widget _userAvatar(String userId) {
    if (userId.isEmpty == true) {
      //---------------------------------------
// display placeholder image if no image found
//---------------------------------------
      return _placeholderAvatar();
    }

//---------------------------------------
// get image from database
//---------------------------------------
    final userDocStream = FirebaseFirestore.instance
        .collection('UserInformation')
        .doc(userId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting || !snap.hasData || !snap.data!.exists) {
          return _placeholderAvatar();
        }

        final Map<String, dynamic> m = snap.data!.data() ?? <String, dynamic>{};

        if (m['profileImageBase64'] is String) {
          final String b64 = m['profileImageBase64'];
          if (b64.isNotEmpty == true) {
            try {
//---------------------------------------
// decode the image
//---------------------------------------
              final Uint8List bytes = base64Decode(b64);
              return Image.memory(bytes, width: 48.w, height: 48.w, fit: BoxFit.cover);
            } catch (_) {
            }
          }
        }

        // try asset image name next
        if (m['profileImageName'] is String) {
          final String name = (m['profileImageName'] as String).trim();
          if (name.isNotEmpty == true) {
            return Image.asset('asset/image/$name', width: 48.w, height: 48.w, fit: BoxFit.cover);
          }
        }

        // final fallback to placeholder
        return _placeholderAvatar();
      },
    );
  }

  // -------------------------------------------------------
  // Placeholder avatar: neutral box with person icon inside
  // -------------------------------------------------------
  Widget _placeholderAvatar() {
    return Container(
      width: 48.w,
      height: 48.w,
      color: Colors.grey.shade400,
      alignment: Alignment.center,
      child: const Icon(Icons.person, color: Colors.white),
    );
  }
}

//---------------------------------------
// build the star
//---------------------------------------

Widget _buildStars(double avg) {
  //---------------------------------------
// list to store five star
//---------------------------------------
  final List<Widget> list = <Widget>[];

  for (int i = 1; i <= 5; i++) {
    IconData icon;

    // full star when avg crosses the index
    if (avg >= i) {
      icon = Icons.star;
    } else {
      // half star when diff <= 0.5
      final double diff = i - avg;
      if (diff <= 0.5) {
        icon = Icons.star_half;
      } else {
        icon = Icons.star_border;
      }
    }

//---------------------------------------
// add star into list and display
//---------------------------------------

    list.add(Icon(icon, size: 20.sp, color: const Color(0xFFFFC107)));
    if (i < 5) list.add(SizedBox(width: 2.w));
  }

  // return a compact row of stars
  return Row(children: list);
}

// ----------------------------------------------
// Small friendly date formatter "5 Jan 2025"
// ----------------------------------------------
String _fmtDate(DateTime d) {
  const List<String> months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final String day = d.day.toString();       // unpadded day
  final String mon = months[d.month - 1];    // month short name
  final String yr  = d.year.toString();      // full year
  return '$day $mon $yr';
}
