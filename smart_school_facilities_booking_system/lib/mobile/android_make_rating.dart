// android_make_rating.dart
//
// Rating & Review page (beginner-friendly, very simple).
// - App bar + bottom bar same style as other pages.
// - Facility name ABOVE the stars (reads from Facilities by facilityId).
// - Shows 5 GREY stars initially; when user taps, selected stars become YELLOW.
// - Shows Username and "Created on" (today date).
// - Review text box: fixed height, wraps long text, scrollable inside, hint on top-left.
// - Validate before submit: stars must be chosen AND review cannot be empty.
//   * If review is empty, show a red error text under the box: "Cannot be empty".
// - On submit: save to Facilities/{facilityId}/Rating subcollection
//   fields: createdAt (server time), rating (int), review (string), userName (string).
// - Uses only if/else (no ?: and no ??).
// - All sizes use .w .h .sp .sw .sh.
// - Simple, humanized comments for each action.

import 'package:cloud_firestore/cloud_firestore.dart';          // Firestore database
import 'package:firebase_auth/firebase_auth.dart';              // Current user info
import 'package:flutter/material.dart';                         // UI widgets
import 'package:flutter_screenutil/flutter_screenutil.dart';    // Responsive sizes
import 'package:intl/intl.dart';                                // Date formatting

// Bottom bar + other pages (keep navigation consistent)
import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_list_of_facilities.dart';
import 'android_notifications.dart';
import 'android_account.dart';

class AndroidMakeRating extends StatefulWidget {
  // Receive ids so we know where to save and what to show
  final String bookingId;
  final String facilityId;

  const AndroidMakeRating({
    Key? key,
    required this.bookingId,
    required this.facilityId,
  }) : super(key: key);

  @override
  State<AndroidMakeRating> createState() => _AndroidMakeRatingState();
}

class _AndroidMakeRatingState extends State<AndroidMakeRating> {
  // -------------------- basic screen states --------------------
  int _currentIndex = 1;                                    // bottom bar highlight (Bookings tab)
  final TextEditingController _reviewCtrl = TextEditingController(); // review input controller
  int _stars = 0;                                           // user selected stars: 0..5
  String _username = '';                                    // display user name
  String _userId = '';                                      // save userId if needed later
  DateTime _created = DateTime.now();                       // today date to display
  String _facilityName = '';                                // show above stars
  String _reviewError = '';                                 // show error text under review if empty
  bool _isEditing = false;          // true = we found an existing rating for this booking
  String _ratingDocId = '';
  // -------------------- life-cycle --------------------
  @override
  void initState() {
    // 3) Try to find an existing rating for this booking so we can edit
    _loadExistingRatingForThisBooking();
    super.initState();

    // 1) Read current user and pick a username to show
    final User? u = FirebaseAuth.instance.currentUser;
    if (u != null) {
      _userId = u.uid;

      FirebaseFirestore.instance.collection('UserInformation').doc(u.uid).get().then((doc) {
        String name = '';
        if (doc.exists) {
          final data = doc.data();
          if (data != null) {
            if (data.containsKey('username')) {
              if (data['username'] != null) { name = data['username'].toString(); }
            }
            if (name.isEmpty == true) {
              if (data.containsKey('name')) {
                if (data['name'] != null) { name = data['name'].toString(); }
              }
            }
          }
        }
        if (name.isEmpty == true) {
          if (u.email != null) { name = u.email!; } else { name = 'User'; }
        }
        if (mounted) {
          setState(() { _username = name; });
        }
      }).catchError((e) {
        String fallback = '';
        if (u.email != null) { fallback = u.email!; } else { fallback = 'User'; }
        if (mounted) {
          setState(() { _username = fallback; });
        }
      });
    } else {
      _userId = '';
      _username = 'Guest';
    }

    // 2) Fetch facility name once to show above stars
    FirebaseFirestore.instance.collection('Facilities').doc(widget.facilityId).get().then((doc) {
      String fname = '';
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          if (data.containsKey('name')) {
            if (data['name'] != null) { fname = data['name'].toString(); }
          }
        }
      }
      if (mounted) {
        setState(() { _facilityName = fname; });
      }
    }).catchError((e) {
      // if failed, just keep empty -> UI will show '-'
      if (mounted) {
        setState(() { _facilityName = ''; });
      }
    });
  }

  @override
  void dispose() {
    _reviewCtrl.dispose(); // avoid memory leak
    super.dispose();
  }

  // -------------------- small helpers --------------------

  // Format date like "Fri, 29 Aug 2025"
  String _formatFullDate(DateTime d) {
    final DateFormat f = DateFormat('EEE, d MMM yyyy');
    return f.format(d);
  }

  // When user taps one of the stars, update _stars 1..5
  void _selectStars(int count) {
    if (count < 0) { count = 0; }
    if (count > 5) { count = 5; }
    setState(() {
      _stars = count;
    });
  }

  // Build a single star (index 1..5); selected -> YELLOW, else GREY
  Widget _buildStar(int index) {
    Color color;
    if (_stars >= index) {
      color = Colors.amber;     // YELLOW when selected
    } else {
      color = Colors.grey;      // GREY when not selected
    }

    return InkWell(
      onTap: () { _selectStars(index); },
      child: Padding(
        padding: EdgeInsets.all(6.w),                 // bigger touch area
        child: Icon(Icons.star, size: 32.w, color: color),
      ),
    );
  }

  // Bottom bar tab change (same rules as other pages)
  void _onTabSelected(int i) {
    if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAgenda()));
    } else {
      if (i == 1) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
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
// Find existing rating doc by bookingId so user can edit it
  Future<void> _loadExistingRatingForThisBooking() async {
    try {
      // go into Facilities/{facilityId}/Rating and search bookingId == current booking
      final QuerySnapshot<Map<String, dynamic>> qs = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .collection('Rating')
          .where('bookingId', isEqualTo: widget.bookingId)
          .limit(1)
          .get();

      if (qs.docs.isNotEmpty == true) {
        final DocumentSnapshot<Map<String, dynamic>> doc = qs.docs.first;
        final Map<String, dynamic>? data = doc.data();

        int stars = 0;
        String review = '';
        DateTime? createdAtDT;

        if (data != null) {
          // pick stars (int)
          if (data.containsKey('rating')) {
            if (data['rating'] != null) {
              try { stars = int.parse(data['rating'].toString()); } catch (_) { stars = 0; }
            }
          }
          // pick review (string)
          if (data.containsKey('review')) {
            if (data['review'] != null) { review = data['review'].toString(); }
          }
          // pick createdAt to show in UI (do NOT change it in DB later)
          if (data.containsKey('createdAt')) {
            final dynamic v = data['createdAt'];
            if (v is Timestamp) {
              createdAtDT = v.toDate();
            } else {
              if (v is DateTime) {
                createdAtDT = v;
              } else {
                if (v is String) {
                  try { createdAtDT = DateTime.tryParse(v); } catch (_) { createdAtDT = null; }
                }
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            _isEditing = true;          // mark editing mode
            _ratingDocId = doc.id;      // keep id for update
            if (stars > 0) { _stars = stars; }   // preselect stars
            _reviewCtrl.text = review;          // prefill review box
            if (createdAtDT != null) { _created = createdAtDT!; } // show original created date
          });
        }
      }
    } catch (e) {
      // if anything fails, just stay in create mode
    }
  }

// handle submit button tap
  Future<void> _submitRating() async {
    // Reset review error first
    if (_reviewError.isNotEmpty == true) {
      setState(() { _reviewError = ''; });
    }

    // Validate: must choose >= 1 star
    if (_stars <= 0) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select your star rating.', style: TextStyle(fontSize: 13.sp))),
      );
      return;
    }

    // Validate: review cannot be empty
    String review = _reviewCtrl.text;
    if (review.isNotEmpty == true) {
      review = review.trim();
    } else {
      review = '';
    }
    if (review.isEmpty == true) {
      setState(() { _reviewError = 'Cannot be empty'; });
      return;
    }

    try {
      if (_isEditing == true && _ratingDocId.isNotEmpty == true) {
        // ---------- EDIT MODE ----------
        // only update fields that can change; do NOT touch createdAt or userId
        await FirebaseFirestore.instance
            .collection('Facilities')
            .doc(widget.facilityId)
            .collection('Rating')
            .doc(_ratingDocId)
            .update(<String, dynamic>{
          'rating': _stars,
          'review': review,
          // optional: keep a lastUpdated field if you want (not required)
          // 'lastUpdatedAt': FieldValue.serverTimestamp(),
        });

        // Booking already rated; no need to set again, but harmless if we do
        try {
          await FirebaseFirestore.instance
              .collection('Bookings')
              .doc(widget.bookingId)
              .update({'rated': true});
        } catch (_) {}

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Rating updated.', style: TextStyle(fontSize: 13.sp))),
          );
          Navigator.pop(context);
        }
      } else {
        // ---------- CREATE MODE ----------
        // Build payload for subcollection "Rating" under Facilities/{facilityId}
        final Map<String, dynamic> data = <String, dynamic>{};
        data['createdAt'] = FieldValue.serverTimestamp();  // server time
        data['rating'] = _stars;                           // 1..5
        data['review'] = review;                           // user text
        data['userId'] = _userId;                          // store userId
        data['bookingId'] = widget.bookingId;              // link to booking

        await FirebaseFirestore.instance
            .collection('Facilities')
            .doc(widget.facilityId)
            .collection('Rating')
            .add(data);

        // mark booking as rated
        try {
          await FirebaseFirestore.instance
              .collection('Bookings')
              .doc(widget.bookingId)
              .update({'rated': true});
        } catch (_) {}

        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Thanks for your rating!', style: TextStyle(fontSize: 13.sp))),
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit. Please try again.', style: TextStyle(fontSize: 13.sp))),
        );
      }
    }
  }




  // -------------------- UI --------------------
  @override
  Widget build(BuildContext context) {
    final double barHeight = 0.07.sh;  // bottom bar height
    final double sw = 1.0.sw;          // screen width for 90% content

    // Decide what to show for facility name (fallback "-")
    String nameDisplay = _facilityName;
    if (nameDisplay.isEmpty == true) {
      nameDisplay = '-';
    }

    return Scaffold(
      // ===== Top purple app bar =====
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
          title: Text('Rating and review', style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600)),
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

      // ===== Page body =====
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Center(
          child: SizedBox(
            width: sw * 0.90, // 90% width like other pages
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // -------- facility name --------
                Text(
                  nameDisplay,
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                SizedBox(height: 12.h),

                // -------- star row --------
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStar(1),
                      _buildStar(2),
                      _buildStar(3),
                      _buildStar(4),
                      _buildStar(5),
                    ],
                  ),
                ),

                SizedBox(height: 18.h),

                // -------- username & created on --------
                Text('Username', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                SizedBox(height: 6.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(_username, style: TextStyle(fontSize: 14.sp)),
                ),

                SizedBox(height: 14.h),

                Text('Created on', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                SizedBox(height: 6.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(_formatFullDate(_created), style: TextStyle(fontSize: 14.sp)),
                ),

                SizedBox(height: 18.h),

                // -------- review input (fixed height + scroll + wrap) --------
                Text('Your review', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                SizedBox(height: 6.h),
                Container(
                  width: double.infinity,
                  height: 160.h, // fixed height so when too long it becomes scrollable
                  padding: EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.grey.shade400, width: 1.w),
                  ),
                  child: Scrollbar( // show small scrollbar when content exceeds box
                    thumbVisibility: true,
                    child: TextField(
                      controller: _reviewCtrl,
                      keyboardType: TextInputType.multiline,     // show multi-line keyboard
                      maxLines: null,                             // allow many lines (no hard limit)
                      expands: true,                              // fill the fixed height and become scrollable
                      textAlignVertical: TextAlignVertical.top,   // position text/hint at the top-left
                      style: TextStyle(fontSize: 14.sp, color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Write your review here...',
                        hintStyle: TextStyle(fontSize: 13.sp, color: Colors.black45),
                        contentPadding: EdgeInsets.all(12.w),     // keep hint top-left
                        border: InputBorder.none,                 // border drawn by Container
                      ),
                      onChanged: (v) {
                        // clear error as soon as user types something
                        if (_reviewError.isNotEmpty == true) {
                          if (v.trim().isNotEmpty == true) {
                            setState(() { _reviewError = ''; });
                          }
                        }
                      },
                    ),
                  ),
                ),

                // error text under review box (red)
                if (_reviewError.isNotEmpty == true)
                  Padding(
                    padding: EdgeInsets.only(top: 6.h, left: 4.w),
                    child: Text(
                      _reviewError,
                      style: TextStyle(fontSize: 12.sp, color: Colors.red),
                    ),
                  ),

                SizedBox(height: 22.h),

                // -------- submit button --------
                SizedBox(
                  width: double.infinity,
                  height: 48.h,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8620E5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                    ),
                    onPressed: () { _submitRating();
                      },
                    child: Text(
                      _isEditing ? 'Update' : 'Submit',
                      style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600, color: Colors.white),
                    ),

                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      // ===== Bottom navigation bar =====
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}
