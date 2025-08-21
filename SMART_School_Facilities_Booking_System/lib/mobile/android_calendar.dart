import 'package:flutter/material.dart';
import 'android_bottom_menu.dart';
import 'android_list_of_facilities.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';

class AndroidCalendar extends StatefulWidget {
  @override
  State<AndroidCalendar> createState() => _AndroidCalendarState();
}

class _AndroidCalendarState extends State<AndroidCalendar> {
  int _currentIndex = 0; // this page = left-most tab

  void _onTabSelected(int i) {
    if (i == 0) {
      setState(() { _currentIndex = 0; });
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

  @override
  Widget build(BuildContext context) {
    final double barHeight = MediaQuery.of(context).size.height * 0.07;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Calendar", style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: const Center(child: Text("Calendar content here")),
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}
