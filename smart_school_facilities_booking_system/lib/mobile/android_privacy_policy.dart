import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AndroidPrivacyPolicy extends StatelessWidget {
  const AndroidPrivacyPolicy({Key? key}) : super(key: key);

//---------------------------------------
// get Privacu policy from System Information
//---------------------------------------

  DocumentReference<Map<String, dynamic>> _docRef() {
    return FirebaseFirestore.instance
        .collection('SystemInformation')
        .doc('PrivacyPolicy');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: true,
          title: Text(
            "Privacy Policy",
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

      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _docRef().snapshots(),
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
//---------------------------------------
// get the content from database
//---------------------------------------

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
//---------------------------------------
// close button
//---------------------------------------

                  SizedBox(height: 12.h),
                  Row(
                    children: [
                      const Spacer(),
                      SizedBox(
                        height: 42.h,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
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
