import 'package:flutter/material.dart';
import 'android_bottom_menu.dart';
import 'android_calendar.dart';
import 'android_list_of_facilities.dart';
import 'android_notifications.dart';
import 'android_account.dart';

class AndroidViewBooking extends StatefulWidget {
  @override
  State<AndroidViewBooking> createState() => _AndroidViewBookingState();
}

class _AndroidViewBookingState extends State<AndroidViewBooking> {
  int _currentIndex = 1; // this page = second tab

  void _onTabSelected(int i) {
    if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidCalendar()));
    } else if (i == 1) {
      setState(() { _currentIndex = 1; });
    } else if (i == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
    } else if (i == 3) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
    } else if (i == 4) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final double barHeight = MediaQuery.of(context).size.height * 0.07;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("View Booking", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: const Center(child: Text("View Booking content here")),
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}
