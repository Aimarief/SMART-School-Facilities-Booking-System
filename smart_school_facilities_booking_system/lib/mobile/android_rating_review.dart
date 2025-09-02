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

// -------------------------------
// Widget: Rating & Reviews page
// -------------------------------
class AndroidRatingReview extends StatefulWidget {
  // facility id to read ratings from
  final String facilityId;
  // facility name for display/context
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

// -------------------------------------------
// State: holds nav index and page behaviours
// -------------------------------------------
class _AndroidRatingReviewState extends State<AndroidRatingReview> {
  // keep Facilities tab highlighted in bottom bar
  int _currentIndex = 2;

  // go back to previous facility details
  void _goBackToDetails() {
    Navigator.pop(context);
  }

  // close to facilities list directly
  void _closeToList() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => AndroidListOfFacilities()),
          (route) => false,
    );
  }

  // handle bottom navigation tab routing
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

  // build page scaffold and content
  @override
  Widget build(BuildContext context) {
    // compute bottom bar height once
    final double barHeight = MediaQuery.of(context).size.height * 0.07;
    // keep local copy of facility id
    final String fid = widget.facilityId;

    // create ratings stream for this facility
    final Stream<QuerySnapshot<Map<String, dynamic>>> ratingStream = FirebaseFirestore.instance
        .collection('Facilities')
        .doc(fid)
        .collection('Rating')
        .snapshots();

    // return the full page
    return Scaffold(
      // top app bar with back/close
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

      // scrollable body
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // top card: overall summary from ratings
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ratingStream,
              builder: (context, snap) {
                // show small loader while ratings arrive
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator()),
                  );
                }

                // aggregate ratings count and sum
                int count = 0;            // total number of ratings
                double total = 0.0;       // sum of rating values

                // collect numbers robustly
                if (snap.hasData) {
                  final docs = snap.data!.docs;
                  count = docs.length;
                  for (final d in docs) {
                    final m = d.data();
                    if (m.containsKey('rating')) {
                      final v = m['rating'];
                      if (v is int) {
                        total += v.toDouble(); // add int rating
                      } else if (v is double) {
                        total += v;            // add double rating
                      } else if (v is String) {
                        final p = double.tryParse(v); // parse string rating
                        if (p != null) total += p;
                      }
                    }
                  }
                }

                // compute average or 0 when none
                double avg;
                if (count > 0) {
                  avg = total / count;
                } else {
                  avg = 0.0;
                }

                // format average text like "4.3"
                final String avgText = avg.toStringAsFixed(1);

                // build ratings count label
                String countLabel = '';
                if (count == 1) {
                  countLabel = '1 rating';
                } else {
                  countLabel = '$count ratings';
                }

                // render summary card
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
                      // section label
                      Text('Review', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                      SizedBox(height: 4.h),
                      // small caption
                      Text('Overall rating', style: TextStyle(fontSize: 13.sp, color: Colors.black54)),
                      SizedBox(height: 8.h),
                      // large average text
                      Text(avgText, style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w700)),
                      SizedBox(height: 6.h),
                      // star visuals
                      _buildStars(avg),
                      SizedBox(height: 6.h),
                      // count label
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

            // list of individual reviews below
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: ratingStream,
              builder: (context, snap) {
                // loading spinner while waiting
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator()),
                  );
                }

                // collect docs or empty list
                final docs = (snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]).toList();

                // sort by createdAt desc when available
                docs.sort((a, b) {
                  final ma = a.data();
                  final mb = b.data();
                  final ta = (ma['createdAt'] is Timestamp) ? (ma['createdAt'] as Timestamp).millisecondsSinceEpoch : 0;
                  final tb = (mb['createdAt'] is Timestamp) ? (mb['createdAt'] as Timestamp).millisecondsSinceEpoch : 0;
                  return tb.compareTo(ta);
                });

                // no reviews fallback
                if (docs.isEmpty == true) {
                  return Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 20.h),
                    alignment: Alignment.center,
                    child: Text('No reviews yet', style: TextStyle(fontSize: 14.sp, color: Colors.black54)),
                  );
                }

                // build the reviews list
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10.h),
                  itemBuilder: (context, i) {
                    final m = docs[i].data();

                    // read rating's userId
                    String userId = '';
                    if (m['userId'] is String) {
                      userId = m['userId'];
                    }

                    // read review text
                    String review = '';
                    if (m['review'] is String) {
                      review = m['review'];
                    }

                    // normalize rating to 0..5
                    double rating = 0.0;
                    if (m['rating'] is int) {
                      rating = (m['rating'] as int).toDouble();
                    } else {
                      if (m['rating'] is double) {
                        rating = m['rating'] as double;
                      } else {
                        if (m['rating'] is String) {
                          final double? p = double.tryParse(m['rating'] as String);
                          if (p != null) {
                            rating = p;
                          }
                        }
                      }
                    }
                    if (rating < 0) {
                      rating = 0;
                    } else {
                      if (rating > 5) {
                        rating = 5;
                      }
                    }

                    // parse createdAt in multiple shapes
                    DateTime? createdAt;
                    final dynamic ca = m['createdAt'];
                    if (ca is Timestamp) {
                      createdAt = ca.toDate().toLocal();
                    } else {
                      if (ca is int) {
                        createdAt = DateTime.fromMillisecondsSinceEpoch(ca).toLocal();
                      } else {
                        if (ca is String) {
                          try {
                            createdAt = DateTime.parse(ca).toLocal();
                          } catch (_) {}
                        }
                      }
                    }

                    // render one review tile
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

      // bottom navigation with current index
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }

  // -----------------------------------------
  // Tile: shows avatar, name, stars, comment
  // -----------------------------------------
  Widget _reviewTile({
    required String userId,
    required double rating,
    required String review,
    DateTime? createdAt,
  }) {
    // build friendly date text
    String dateText = '-';
    if (createdAt != null) {
      dateText = _fmtDate(createdAt);
    }

    // create user info stream when userId exists
    Stream<DocumentSnapshot<Map<String, dynamic>>>? userStream;
    if (userId.isNotEmpty == true) {
      userStream = FirebaseFirestore.instance
          .collection('UserInformation')
          .doc(userId)
          .snapshots();
    }

    // return decorated card with a small StreamBuilder for user display name
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
          // default name
          String displayName = 'Anonymous';

          // use placeholder if no stream
          if (userStream == null) {
            displayName = 'Anonymous';
          } else {
            // keep placeholder while loading
            if (snap.connectionState == ConnectionState.waiting) {
              displayName = 'Anonymous';
            } else {
              // read username from user doc when available
              if (snap.hasData && snap.data != null && snap.data!.exists) {
                final Map<String, dynamic>? um = snap.data!.data();
                if (um != null) {
                  if (um.containsKey('username')) {
                    if (um['username'] != null) {
                      final String v = um['username'].toString();
                      if (v.isNotEmpty == true) {
                        displayName = v;
                      }
                    }
                  }
                }
              }
            }
          }

          // build tile content
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // top row with avatar and user info
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(40.r),
                    child: _userAvatar(userId), // avatar that tries base64 > asset > placeholder
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // display name text
                        Text(
                          displayName,
                          style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4.h),
                        // star rating visuals
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

  // ----------------------------------------
  // Avatar loader: base64 -> asset -> dummy
  // ----------------------------------------
  Widget _userAvatar(String userId) {
    // return placeholder when empty id
    if (userId.isEmpty == true) {
      return _placeholderAvatar();
    }

    // create stream to watch user info
    final userDocStream = FirebaseFirestore.instance
        .collection('UserInformation')
        .doc(userId)
        .snapshots();

    // build avatar depending on stored fields
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, snap) {
        // fallback while loading or missing doc
        if (snap.connectionState == ConnectionState.waiting || !snap.hasData || !snap.data!.exists) {
          return _placeholderAvatar();
        }

        // unwrap map safely
        final Map<String, dynamic> m = snap.data!.data() ?? <String, dynamic>{};

        // try base64 image first
        if (m['profileImageBase64'] is String) {
          final String b64 = m['profileImageBase64'];
          if (b64.isNotEmpty == true) {
            try {
              final Uint8List bytes = base64Decode(b64);
              return Image.memory(bytes, width: 48.w, height: 48.w, fit: BoxFit.cover);
            } catch (_) {
              // fall through to asset if decode fails
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

// ---------------------------------------------------
// Shared star builder: draws up to 5 with half-stars
// ---------------------------------------------------
Widget _buildStars(double avg) {
  // hold 5 icons with small gaps
  final List<Widget> list = <Widget>[];

  // walk from 1..5 and decide icon
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

    // push icon then optional spacer
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
