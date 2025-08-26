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

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser; // ✅ make sure we have the user early

    _updateTime();
    _timer = Timer.periodic(Duration(seconds: 1), (timer) {
      _updateTime();
    });

    _fetchUserRole();
    _fetchUserTimeFormatSetting();
  }

  void _updateTime() {
    final now = DateTime.now();
    String formattedTime;

    if (widget.use24HourFormat) {
      formattedTime =
      "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(
          2, '0')}:${now.second.toString().padLeft(2, '0')}";
    } else {
      int hour = now.hour % 12;
      if (hour == 0) hour = 12;
      String amPm = now.hour >= 12 ? 'PM' : 'AM';
      formattedTime =
      "$hour:${now.minute.toString().padLeft(2, '0')}:${now.second
          .toString()
          .padLeft(2, '0')} $amPm";
    }

    String formattedDate =
        "${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(
        2, '0')}/${now.year}";

    setState(() {
      _formattedDateTime = "$formattedDate  $formattedTime";
    });
  }

  Future<void> _fetchUserTimeFormatSetting() async {
    if (_user?.email == null) return;

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('UserInformation')
          .where('email', isEqualTo: _user!.email)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final data = querySnapshot.docs.first.data();
        final bool timeFormat24 = data['timeFormat24'] ?? true;
        if (mounted) {
          setState(() {
            _use24HourFormat = timeFormat24;
          });
        }
      }
    } catch (e) {
      print("Error fetching time format: $e");
    }
  }

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
            height: screenHeight - 70.h,
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

  List<Widget> _buildMenuItems(BuildContext context) {
    List<Widget> items = [];

    if (_role == 'Admin') {
      items.addAll([
        _menuItem("Calendar", () {
          Navigator.of(context).pop();
          context.go('/calendar');
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
        _menuItem("Booking", () {
          Navigator.of(context).pop();
          context.go('/booking');
        }),
        SizedBox(height: 35.h),
        _menuItem("Statistic", () {
          Navigator.of(context).pop();
          context.go('/statistic');
        }),
      ]);
    } else if (_role == 'Manager') {
      items.addAll([
        _menuItem("Calendar", () {
          Navigator.of(context).pop();
          context.go('/calendar');
        }),
        SizedBox(height: 35.h),
        _menuItem("Booking List", () {
          Navigator.of(context).pop();
          context.go('/bookinglist');
        }),
        SizedBox(height: 35.h),
        _menuItem("Booking", () {
          Navigator.of(context).pop();
          context.go('/booking');
        }),
      ]);
    }

    return items;
  }

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
          // Left side: Hamburger + Logo
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

          // Center date/time box
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

          // Right side: Notification + Account icons
          Row(
            children: [
              GestureDetector(
                onTap: () => context.go('/notifications'),
                child: Icon(
                  Icons.notifications,
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