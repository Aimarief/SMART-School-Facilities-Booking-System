import 'dart:convert'; // for base64Decode
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// bottom nav + other main pages (so the bar behaves the same)
import 'android_bottom_menu.dart';
import 'android_calendar.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart';

class AndroidRatingReview extends StatefulWidget {
  final String facilityId;
  final String facilityName;

  const AndroidRatingReview({
    Key? key,
    required this.facilityId,
    required this.facilityName,
  }) : super(key: key);

  @override
  State<AndroidRatingReview> createState() => _AndroidRatingReviewState();
}

class _AndroidRatingReviewState extends State<AndroidRatingReview> {
  int _currentIndex = 2; // keep Facilities selected (same as other pages)

  void _goBackToDetails() {
    Navigator.pop(context);
  }

  void _closeToList() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => AndroidListOfFacilities()),
          (route) => false,
    );
  }

  void _onTabSelected(int i) {
    if (i == 2) {
      // Facilities
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
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

  @override
  Widget build(BuildContext context) {
    final double barHeight = MediaQuery.of(context).size.height * 0.07;
    final String fid = widget.facilityId;

    // stream of all ratings for this facility
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
            onPressed: _goBackToDetails,
            tooltip: 'Back',
          ),
          title: Text(
            "Rating and Reviews",
            style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _closeToList,
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
            // -------- Top summary (overall rating) --------
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

                if (snap.hasData) {
                  final docs = snap.data!.docs;
                  count = docs.length;
                  for (final d in docs) {
                    final m = d.data();
                    if (m.containsKey('rating')) {
                      final v = m['rating'];
                      if (v is int) {
                        total += v.toDouble();
                      } else if (v is double) {
                        total += v;
                      } else if (v is String) {
                        final p = double.tryParse(v);
                        if (p != null) total += p;
                      }
                    }
                  }
                }

                final double avg = (count > 0) ? (total / count) : 0.0;
                final String avgText = avg.toStringAsFixed(1);
                final String countLabel = (count == 1) ? '1 rating' : '$count ratings';

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
                    ],
                  ),
                );
              },
            ),

            SizedBox(height: 14.h),

            // -------- List of individual reviews --------
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ratingStream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator()),
                  );
                }

                final docs = (snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]).toList();

                // if you store 'createdAt' in each rating doc, sort by it (desc)
                docs.sort((a, b) {
                  final ma = a.data();
                  final mb = b.data();
                  final ta = (ma['createdAt'] is Timestamp) ? (ma['createdAt'] as Timestamp).millisecondsSinceEpoch : 0;
                  final tb = (mb['createdAt'] is Timestamp) ? (mb['createdAt'] as Timestamp).millisecondsSinceEpoch : 0;
                  return tb.compareTo(ta);
                });

                if (docs.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 20.h),
                    alignment: Alignment.center,
                    child: Text('No reviews yet', style: TextStyle(fontSize: 14.sp, color: Colors.black54)),
                  );
                }



                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10.h),
                  itemBuilder: (context, i) {
                    final m = docs[i].data();

                    // read rating fields safely
                    String userId = '';
                    if (m['userId'] is String) userId = m['userId'];

                    String username = '';
                    if (m['username'] is String) username = m['username'];

                    String review = '';
                    if (m['review'] is String) review = m['review'];

                    double rating = 0.0;
                    if (m['rating'] is int) {
                      rating = (m['rating'] as int).toDouble();
                    } else if (m['rating'] is double) {
                      rating = m['rating'] as double;
                    } else if (m['rating'] is String) {
                      final p = double.tryParse(m['rating'] as String);
                      if (p != null) rating = p;
                    }
                    if (rating < 0) rating = 0;
                    if (rating > 5) rating = 5;

                    // extract createdAt safely
                    DateTime? createdAt;
                    final ca = m['createdAt'];
                    if (ca is Timestamp) {
                      createdAt = ca.toDate().toLocal();
                    } else if (ca is int) {
                      createdAt = DateTime.fromMillisecondsSinceEpoch(ca).toLocal();
                    } else if (ca is String) {
                      try { createdAt = DateTime.parse(ca).toLocal(); } catch (_) {}
                    }

                    // now build the tile ONCE
                    return _reviewTile(
                      userId: userId,
                      username: username,
                      rating: rating,
                      review: review,
                      createdAt: createdAt, // shows "20 Jan 2025" bottom-right
                    );
                  },
                );

              },
            ),
          ],
        ),
      ),

      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }

  // One review card: avatar, username, stars, review text
Widget _reviewTile({
  required String userId,
  required String username,
  required double rating,
  required String review,
  DateTime? createdAt,
}) {
  final String dateText = (createdAt == null) ? '-' : _fmtDate(createdAt);

  return Container(
    width: double.infinity,
    padding: EdgeInsets.all(12.w),
    decoration: BoxDecoration(
      color: Colors.grey.shade200,
      borderRadius: BorderRadius.circular(12.r),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row: avatar | (name, stars)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(40.r),
              child: _userAvatar(userId),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (username.isEmpty ? 'Anonymous' : username),
                    style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 4.h),
                  _buildStars(rating), // left-aligned stars under the name
                ],
              ),
            ),
          ],
        ),

        SizedBox(height: 8.h),

        // Review text under the row
        Text(
          review,
          style: TextStyle(fontSize: 13.sp, color: Colors.black87),
          softWrap: true,
        ),

        SizedBox(height: 6.h),

        // Date bottom-right
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            dateText,
            style: TextStyle(fontSize: 12.sp, color: Colors.black54),
          ),
        ),
      ],
    ),
  );
}



// avatar loader reading from UserInformation/{userId}
  Widget _userAvatar(String userId) {
    if (userId.isEmpty) {
      return _placeholderAvatar();
    }

    final userDocStream = FirebaseFirestore.instance
        .collection('UserInformation')
        .doc(userId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, snap) {
        // quick placeholder while loading / missing
        if (snap.connectionState == ConnectionState.waiting || !snap.hasData || !snap.data!.exists) {
          return _placeholderAvatar();
        }

        final m = snap.data!.data() ?? <String, dynamic>{};

        // try Base64 first
        if (m['profileImageBase64'] is String) {
          final String b64 = m['profileImageBase64'];
          if (b64.isNotEmpty) {
            try {
              final Uint8List bytes = base64Decode(b64);
              return Image.memory(bytes, width: 48.w, height: 48.w, fit: BoxFit.cover);
            } catch (_) {
              // fall through to asset
            }
          }
        }

        // fallback to asset name
        if (m['profileImageName'] is String) {
          final String name = (m['profileImageName'] as String).trim();
          if (name.isNotEmpty) {
            return Image.asset('asset/image/$name', width: 48.w, height: 48.w, fit: BoxFit.cover);
          }
        }

        // fallback: placeholder
        return _placeholderAvatar();
      },
    );
  }

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

// same visual star builder you used elsewhere (supports halves)
Widget _buildStars(double avg) {
  final List<Widget> list = <Widget>[];
  for (int i = 1; i <= 5; i++) {
    IconData icon;
    if (avg >= i) {
      icon = Icons.star;
    } else {
      final double diff = i - avg;
      if (diff <= 0.5) {
        icon = Icons.star_half;
      } else {
        icon = Icons.star_border;
      }
    }
    list.add(Icon(icon, size: 20.sp, color: const Color(0xFFFFC107)));
    if (i < 5) list.add(SizedBox(width: 2.w));
  }
  return Row(children: list);
}
String _fmtDate(DateTime d) {
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final day = d.day.toString(); // no leading zero -> "5 Jan 2025"
  final mon = months[d.month - 1];
  final yr  = d.year.toString();
  return '$day $mon $yr';
}