import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'web_login.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'web_top_bar.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';


class AdminWebHomepage extends StatefulWidget {
  @override
  _AdminWebHomepageState createState() => _AdminWebHomepageState();
}

class _AdminWebHomepageState extends State<AdminWebHomepage> {
  bool _use24HourFormat = true;


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: WebCustomTopBar(use24HourFormat: _use24HourFormat),

      ),
      body: Center(
        child: ElevatedButton(
          child: Text("Show Username"),
          onPressed: () async {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text("Error"),
                  content: Text("No user logged in"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: Text("OK"))
                  ],
                ),
              );
              return;
            }

            final doc = await FirebaseFirestore.instance
                .collection('UserInformation')
                .doc(user.uid)
                .get();

            String username;
            if (!doc.exists) {
              username = "User data not found";
            } else {
              username = doc.data()?['username'] ?? "Username not set";
            }

            showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text("Your Username"),
                content: Text(username),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text("OK"))
                ],
              ),
            );
          },

        ),
      ),
    );
  }
  }
