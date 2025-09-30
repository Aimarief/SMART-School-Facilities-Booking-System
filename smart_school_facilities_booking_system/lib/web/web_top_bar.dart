import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'time_format_helper.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';


class WebCustomTopBar extends StatefulWidget implements PreferredSizeWidget {
  final bool use24HourFormat;

  const WebCustomTopBar({Key? key, required this.use24HourFormat}) : super(key: key);

  @override
  _WebCustomTopBarState createState() => _WebCustomTopBarState();

  @override
  Size get preferredSize => Size.fromHeight(70.h);
}

class _WebCustomTopBarState extends State<WebCustomTopBar> {
  late Timer _timer;
  String _formattedDateTime = '';
  bool _use24HourFormat = true; // Default until fetched
  String _role = ''; // ✅ Added: store Admin/Manager
  User? _user;
  final FirebaseAuth _auth = FirebaseAuth.instance;
//---------------------------------------
//do init state first
//---------------------------------------

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser; // make sure we have the user

    _updateTime();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      _updateTime();
    });

    _fetchUserRole();

  }
//---------------------------------------
// get the current time and date
//---------------------------------------

  void _updateTime() {
    final now = DateTime.now(); // get current date-time
    final formatted = DateFormat('dd/MM/yyyy  HH:mm:ss').format(now); // 24h with seconds

    setState(() {
      _formattedDateTime = formatted; // set the UI text
    });
  }

//---------------------------------------
// find the correct role of user
//---------------------------------------

  Future<void> _fetchUserRole() async {
    if (_user?.email == null) return;

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('UserInformation')
          .where('email', isEqualTo: _user!.email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final data = querySnapshot.docs.first.data();
        final String role = data['role'] ?? 'Manager';
        if (mounted) {
          setState(() {
            _role = role;
          });
        }
      }
    } catch (e) {
      print("Error fetching user role: $e");
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }


//---------------------------------------
// show menu using pop up
//---------------------------------------

  void _showMenuPopup(BuildContext context) {
    final screenHeight = MediaQuery
        .of(context)
        .size
        .height;
    final screenWidth = MediaQuery
        .of(context)
        .size
        .width;

    double menuWidth = 311.w;
    if (screenWidth < 350) {
      menuWidth = screenWidth * 0.8;
    }


    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54.withOpacity(0.3),
      builder: (context) {
        return Align(
          alignment: Alignment.topLeft,
          child: Container(
            margin: EdgeInsets.only(top: 70.h),
            width: menuWidth,
            height: screenHeight ,
            color: Colors.white,
            padding: EdgeInsets.only(left: 20.w, top: 20.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _buildMenuItems(context),
            ),
          ),
        );
      },
    );
  }
//---------------------------------------
// show all menu items
//---------------------------------------

  List<Widget> _buildMenuItems(BuildContext context) {
    List<Widget> items = [];

    if (_role == 'Admin') {
      items.addAll([
        _menuItem("Calendar", () {
          Navigator.of(context).pop();
          context.go('/homepage');
        }),
        SizedBox(height: 35.h),
        _menuItem("Booking List", () {
          Navigator.of(context).pop();
          context.go('/bookinglist');
        }),
        SizedBox(height: 35.h),
        _menuItem("Facilities", () {
          Navigator.of(context).pop();
          context.go('/facilitiespage');
        }),
        SizedBox(height: 35.h),
        _menuItem("Categories", () {
          Navigator.of(context).pop();
          context.go('/categoriespage');
        }),

        SizedBox(height: 35.h),
        _menuItem("Manager List", () {
          Navigator.of(context).pop();
          context.go('/listmanagerpage');
        }),
        SizedBox(height: 35.h),
        _menuItem("Lecturer List", () {
          Navigator.of(context).pop();
          context.go('/lecturerlist');
        }),
        SizedBox(height: 35.h),
        _menuItem("Booking", () {
          Navigator.of(context).pop();
          context.go('/webbooking');
        }),
        SizedBox(height: 35.h),
        _menuItem("Statistics", () {
          Navigator.of(context).pop();
          context.go('/webstatistic');
        }),
        SizedBox(height: 35.h),
        _menuItem("FAQ", () {
          Navigator.of(context).pop();
          context.go('/webfaq');
        }),
        SizedBox(height: 35.h),
        _menuItem("Terms & Condition", () {
          Navigator.of(context).pop();
          context.go('/webtnc');
        }),
      ]);
    } else if (_role == 'Manager') {
      items.addAll([
        _menuItem("Calendar", () {
          Navigator.of(context).pop();
          context.go('/homepage');
        }),
        SizedBox(height: 35.h),
        _menuItem("Booking List", () {
          Navigator.of(context).pop();
          context.go('/bookinglist');
        }),
        SizedBox(height: 35.h),
        _menuItem("Booking", () {
          Navigator.of(context).pop();
          context.go('/webbooking');
        }),
      ]);
    }

    return items;
  }
//---------------------------------------
// when tap it will navigate
//---------------------------------------

  Widget _menuItem(String title, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18.sp,
          color: Colors.black87,
        ),
        textAlign: TextAlign.left,
      ),
    );
  }

//---------------------------------------
// main build for top bar
//---------------------------------------

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery
        .of(context)
        .size
        .height;
    final screenWidth = MediaQuery
        .of(context)
        .size
        .width;

    double menuWidth = 311.w;
    if (screenWidth < 350) {
      menuWidth = screenWidth * 0.8;
    }

    return Container(
      width: double.infinity,
      height: 70.h,
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAFA),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: const Color(0xFFD9D9D9), width: 1.w),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
//---------------------------------------
// left side menu button
//---------------------------------------

          Row(
            children: [
              GestureDetector(
                onTap: () => _showMenuPopup(context),
                child: Icon(Icons.menu, size: 40.w),
              ),
              SizedBox(width: 12.w),
              Image.asset(
                'asset/image/fyp_logo.png',
                height: 70.h,
                width: 70.w,
                fit: BoxFit.contain,
              ),
            ],
          ),

//---------------------------------------
// show center time
//---------------------------------------

          Expanded(
            child: Center(
              child: Container(
                height: 51.h,
                width: 257.w,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2CCFF),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                alignment: Alignment.center,
                child: Text(
                  _formattedDateTime,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          ),

//---------------------------------------
// rihgt side notification page and account page
//---------------------------------------

          Row(
            children: [
              GestureDetector(
                onTap: () => context.go('/webnotification'),
                child: Icon(
                  Icons.mail,
                  size: 40.w,
                ),
              ),
              SizedBox(width: 20.w),
              GestureDetector(
                onTap: () => context.go('/webaccount'),
                child: Icon(
                  Icons.account_circle,
                  size: 40.w,
                ),
              ),

            ],
          ),
        ],
      ),
    );
  }

}