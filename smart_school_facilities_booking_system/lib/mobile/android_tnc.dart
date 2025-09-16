// lib/mobile/android_tnc.dart
// -----------------------------------------------------------------------------
// ANDROID TERMS & CONDITIONS (read-only for anyone)
// - AppBar same style as other Android pages (purple + rounded bottom).
// - Back arrow (system) + a "Close" button at bottom-right.
// - Content is streamed from Firestore: SystemInformation/TNC { content: <text> }.
// - Uses simple code and ScreenUtil sizes.
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AndroidTNC extends StatelessWidget {
  const AndroidTNC({Key? key}) : super(key: key);

  // helper: reference to the TNC document
  DocumentReference<Map<String, dynamic>> _docRef() {
    return FirebaseFirestore.instance
        .collection('SystemInformation')
        .doc('TNC'); // document name exactly "TNC"
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // App bar same style as your other Android pages
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: true, // show back arrow
          title: Text(
            "Terms & Conditions",
            style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(40.r),
              bottomRight: Radius.circular(40.r),
            ),
          ),
        ),
      ),

      // Body: stream the content and show it
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _docRef().snapshots(), // listen to changes live
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Text("Failed to load content", style: TextStyle(fontSize: 14.sp)),
              );
            }

            String content = "(No content yet)";
            if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
              final data = snapshot.data!.data();
              if (data != null && data['content'] != null) {
                content = data['content'].toString();
              }
            }

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // content box
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Text(
                      content,
                      style: TextStyle(fontSize: 14.sp, color: Colors.black87),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  // Close button bottom-right
                  Row(
                    children: [
                      const Spacer(),
                      SizedBox(
                        height: 42.h,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context); // go back
                          },
                          child: Text("Close", style: TextStyle(fontSize: 14.sp)),
                        ),
                      ),

                    ],
                  ),
                  SizedBox(height: 12.h),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
