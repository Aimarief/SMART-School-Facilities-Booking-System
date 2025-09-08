import 'package:flutter/material.dart';                      // for UI
import 'package:flutter_screenutil/flutter_screenutil.dart'; // for scaling sizes
import 'package:cloud_firestore/cloud_firestore.dart';       // for Firestore
import 'package:firebase_auth/firebase_auth.dart';           // for current user


import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_list_of_facilities.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_view_booking.dart';

class NotificationSetting extends StatefulWidget {
  const NotificationSetting({Key? key}) : super(key: key);

  @override
  State<NotificationSetting> createState() => _NotificationSettingState();
}

class _NotificationSettingState extends State<NotificationSetting> {

  int _currentIndex = 3;

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


  // ------------------ States for switches ------------------
  bool _notifAll = true;             // control all
  bool _notifApprovalBook = true;    // approval notification
  bool _notifNewBook = true;         // new booking notification
  bool _notifReminder = true;        // reminder notification
  bool _notifUpdatedBook = true;     // update notification

  bool _loading = true; // show while fetching Firestore

  // ------------------ Read from Firestore ------------------
  Future<void> _loadSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('UserInformation')
        .doc(uid)
        .get();

    if (doc.exists) {
      final data = doc.data()!;
      setState(() {
        // read values, default true if missing
        _notifAll = data['notifAll'] ?? true;
        _notifApprovalBook = data['notifApprovalBook'] ?? true;
        _notifNewBook = data['notifNewBook'] ?? true;
        _notifReminder = data['notifReminder'] ?? true;
        _notifUpdatedBook = data['notifUpdatedBook'] ?? true;
        _loading = false;
      });
    } else {
      // if doc not exist yet, set default values
      setState(() {
        _notifAll = true;
        _notifApprovalBook = true;
        _notifNewBook = true;
        _notifReminder = true;
        _notifUpdatedBook = true;
        _loading = false;
      });
    }
  }

  // ------------------ Save to Firestore ------------------
  Future<void> _saveSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance
        .collection('UserInformation')
        .doc(uid)
        .set({
      'notifAll': _notifAll,
      'notifApprovalBook': _notifApprovalBook,
      'notifNewBook': _notifNewBook,
      'notifReminder': _notifReminder,
      'notifUpdatedBook': _notifUpdatedBook,
    }, SetOptions(merge: true)); // merge so other fields not deleted
  }

  // ------------------ Lifecycle ------------------
  @override
  void initState() {
    super.initState();
    _loadSettings(); // load settings when page opens
  }

  // ------------------ Build UI ------------------
  @override
  Widget build(BuildContext context) {
    final double barHeight = 0.07.sh;
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
            icon: Icon(Icons.arrow_back, color: Colors.white, size: 22.sp),
            onPressed: () { if (Navigator.canPop(context)) Navigator.pop(context); },
            tooltip: 'Back',
          ),
          title: Text('Notification Setting', style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600)),
          actions: [
            IconButton(
              icon: Icon(Icons.close, color: Colors.white, size: 22.sp),
              onPressed: () { if (Navigator.canPop(context)) Navigator.pop(context); },
              tooltip: 'Close',
            ),
          ],
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.w), // responsive padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -------- All Notifications --------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("All Notifications", style: TextStyle(fontSize: 16.sp)),
                Switch(
                  value: _notifAll,
                  onChanged: (val) {
                    setState(() {
                      _notifAll = val;

                      // if master switch is off, turn all off
                      if (val == false) {
                        _notifApprovalBook = false;
                        _notifNewBook = false;
                        _notifReminder = false;
                        _notifUpdatedBook = false;
                      }
                    });
                    _saveSettings();
                  },
                ),
              ],
            ),
            SizedBox(height: 10.h),

            // -------- New Booking --------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("New Booking Notification",
                    style: TextStyle(fontSize: 15.sp)),
                Switch(
                  value: _notifNewBook,
                  onChanged: _notifAll == false
                      ? null // disable if all is off
                      : (val) {
                    setState(() {
                      _notifNewBook = val;
                    });
                    _saveSettings();
                  },
                ),
              ],
            ),
            SizedBox(height: 10.h),

            // -------- Update --------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("New Update Notification",
                    style: TextStyle(fontSize: 15.sp)),
                Switch(
                  value: _notifUpdatedBook,
                  onChanged: _notifAll == false
                      ? null
                      : (val) {
                    setState(() {
                      _notifUpdatedBook = val;
                    });
                    _saveSettings();
                  },
                ),
              ],
            ),
            SizedBox(height: 10.h),

            // -------- Approval --------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Approval Notification",
                    style: TextStyle(fontSize: 15.sp)),
                Switch(
                  value: _notifApprovalBook,
                  onChanged: _notifAll == false
                      ? null
                      : (val) {
                    setState(() {
                      _notifApprovalBook = val;
                    });
                    _saveSettings();
                  },
                ),
              ],
            ),
            SizedBox(height: 10.h),

            // -------- Reminder --------
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Reminder", style: TextStyle(fontSize: 15.sp)),
                Switch(
                  value: _notifReminder,
                  onChanged: _notifAll == false
                      ? null
                      : (val) {
                    setState(() {
                      _notifReminder = val;
                    });
                    _saveSettings();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      // Bottom bar
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}
