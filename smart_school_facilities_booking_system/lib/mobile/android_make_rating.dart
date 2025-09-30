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
//---------------------------------------
// current page
//---------------------------------------
  int _currentIndex = 1;
  final TextEditingController _reviewCtrl = TextEditingController();
  int _stars = 0;
  String _username = '';
  String _userId = '';
  DateTime _created = DateTime.now();
  String _facilityName = '';
  String _reviewError = '';
  bool _isEditing = false;
  String _ratingDocId = '';
//---------------------------------------
// run init state first
//---------------------------------------
  @override
  void initState() {
    _loadExistingRatingForThisBooking();
    super.initState();

  //---------------------------------------
// get curent user from database
//---------------------------------------
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

//---------------------------------------
// get the facility name from database
//---------------------------------------
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

//---------------------------------------
// format the date
//---------------------------------------

  String _formatFullDate(DateTime d) {
    final DateFormat f = DateFormat('EEE, d MMM yyyy');
    return f.format(d);
  }

//---------------------------------------
// when user select the star
//---------------------------------------

  void _selectStars(int count) {
    if (count < 0) { count = 0; }
    if (count > 5) { count = 5; }
    setState(() {
      _stars = count;
    });
  }

//---------------------------------------
// when select star
//---------------------------------------

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

//---------------------------------------
// bottom navigation
//---------------------------------------

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
//---------------------------------------
// load the reating first for this booking
//---------------------------------------

  Future<void> _loadExistingRatingForThisBooking() async {
    try {
      //---------------------------------------
// get the rating for this booking id form database
//---------------------------------------

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
            _isEditing = true;
            _ratingDocId = doc.id;
            if (stars > 0) { _stars = stars; }
            _reviewCtrl.text = review;
            if (createdAtDT != null) { _created = createdAtDT!; }
          });
        }
      }
    } catch (e) {
      // if anything fails, just stay in create mode
    }
  }

//---------------------------------------
// when submit
//---------------------------------------

  Future<void> _submitRating() async {
    if (_reviewError.isNotEmpty == true) {
      setState(() { _reviewError = ''; });
    }

    //---------------------------------------
// must rate star first
//---------------------------------------

    if (_stars <= 0) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select your star rating.', style: TextStyle(fontSize: 13.sp))),
      );
      return;
    }

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
        //---------------------------------------
// if it is edit rating
//---------------------------------------
        await FirebaseFirestore.instance
            .collection('Facilities')
            .doc(widget.facilityId)
            .collection('Rating')
            .doc(_ratingDocId)
            .update(<String, dynamic>{
          'rating': _stars,
          'review': review,
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
        //---------------------------------------
// if it is creating rating
//---------------------------------------

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

//---------------------------------------
// mark booking id rated to true
//---------------------------------------
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

//---------------------------------------
// main build
//---------------------------------------

  @override
  Widget build(BuildContext context) {
    final double barHeight = 0.07.sh;  // bottom bar height
    final double sw = 1.0.sw;          // screen width for 90% content

    String nameDisplay = _facilityName;
    if (nameDisplay.isEmpty == true) {
      nameDisplay = '-';
    }

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

      //---------------------------------------
// display facility name
//---------------------------------------
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Center(
          child: SizedBox(
            width: sw * 0.90, // 90% width like other pages
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nameDisplay,
                  style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                SizedBox(height: 12.h),
//---------------------------------------
// display star base on index
//---------------------------------------

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

//---------------------------------------
// display username
//---------------------------------------

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
//---------------------------------------
// display date
//---------------------------------------
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

//---------------------------------------
// display review text box
//---------------------------------------

                Text('Your review', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                SizedBox(height: 6.h),
                Container(
                  width: double.infinity,
                  height: 160.h,
                  padding: EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.grey.shade400, width: 1.w),
                  ),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: TextField(
                      controller: _reviewCtrl,
                      keyboardType: TextInputType.multiline,
                      maxLines: null,
                      expands: true,
                      textAlignVertical: TextAlignVertical.top,
                      style: TextStyle(fontSize: 14.sp, color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Write your review here...',
                        hintStyle: TextStyle(fontSize: 13.sp, color: Colors.black45),
                        contentPadding: EdgeInsets.all(12.w),     // keep hint top-left
                        border: InputBorder.none,                 // border drawn by Container
                      ),
                      onChanged: (v) {
                        if (_reviewError.isNotEmpty == true) {
                          if (v.trim().isNotEmpty == true) {
                            setState(() { _reviewError = ''; });
                          }
                        }
                      },
                    ),
                  ),
                ),

//---------------------------------------
// show error if empty
//---------------------------------------

                if (_reviewError.isNotEmpty == true)
                  Padding(
                    padding: EdgeInsets.only(top: 6.h, left: 4.w),
                    child: Text(
                      _reviewError,
                      style: TextStyle(fontSize: 12.sp, color: Colors.red),
                    ),
                  ),

                SizedBox(height: 22.h),

//---------------------------------------
// submit button
//---------------------------------------
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
