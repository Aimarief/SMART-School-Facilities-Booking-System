import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_list_of_facilities.dart';
import 'android_notifications.dart';

class AndroidFAQ extends StatefulWidget {
  const AndroidFAQ({Key? key}) : super(key: key);

  @override
  State<AndroidFAQ> createState() => _AndroidFAQState();
}

class _AndroidFAQState extends State<AndroidFAQ> {

  int _currentIndex = 4;

  final TextEditingController _searchCtrl = TextEditingController();
  String _keyword = '';

//---------------------------------------
// bottom navigation
//---------------------------------------

  void _onTabSelected(int i) {
    if (i == 4) {

      setState(() { _currentIndex = 4; });
    } else if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAgenda()));
    } else if (i == 1) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } else if (i == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
    } else if (i == 3) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
    }
  }

//---------------------------------------
// get FAQ in database
//---------------------------------------

  CollectionReference<Map<String, dynamic>> _faqCol() {
    return FirebaseFirestore.instance.collection('FAQ');
  }

//---------------------------------------
// main build
//---------------------------------------
  @override
  Widget build(BuildContext context) {
    final double barHeight = 60.h;

    return Scaffold(

      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: true, // back arrow appears
          title: Text(
            'FAQ',
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


      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
//---------------------------------------
// search box
//---------------------------------------

            TextField(
              controller: _searchCtrl,
              onChanged: (t) {
                setState(() { _keyword = t.trim().toLowerCase(); }); // update filter
              },
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search FAQ title',
                prefixIcon: const Icon(Icons.search, color: Colors.black87),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
              ),
            ),

            SizedBox(height: 12.h),

//---------------------------------------
// sort by updated date  for every faq
//---------------------------------------
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _faqCol().orderBy('updatedAt', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Failed to load FAQ', style: TextStyle(fontSize: 14.sp)),
                  );
                }

                final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                final List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                int i = 0;
                while (i < docs.length) {
                  final d = docs[i];
                  final Map<String, dynamic> m = d.data();

                  String title;
                  if (m.containsKey('title') && m['title'] != null) {
                    title = m['title'].toString();
                  } else {
                    title = '';
                  }
//---------------------------------------
// filter if search is empty all or it contain key word then add to filtered list
//---------------------------------------

                  bool matches;
                  if (_keyword.isEmpty) {
                    matches = true;
                  } else {
                    final String cmp = title.toLowerCase();
                    if (cmp.contains(_keyword)) {
                      matches = true;
                    } else {
                      matches = false;
                    }
                  }

                  if (matches) {
                    filtered.add(d);
                  }

                  i = i + 1;
                }

//---------------------------------------
// if no FAQ
//---------------------------------------

                if (filtered.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.only(top: 12.h),
                    child: Center(
                      child: Text('No FAQ found', style: TextStyle(fontSize: 14.sp, color: Colors.black54)),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => SizedBox(height: 8.h),
                  itemBuilder: (context, idx) {
                    final d = filtered[idx];
                    final Map<String, dynamic> m = d.data();

                    String title = '';
                    if (m.containsKey('title') && m['title'] != null) {
                      title = m['title'].toString();
                    }

                    String description = '';
                    if (m.containsKey('description') && m['description'] != null) {
                      description = m['description'].toString();
                    }

                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8.r),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8.r),
//---------------------------------------
// when press will pop up show details
//---------------------------------------
                        onTap: () {
                          _openViewDialog(title: title, description: description); // open popup
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title.isEmpty ? '(No title)' : title,
                                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.chevron_right),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),

//---------------------------------------
// bottom bar
//---------------------------------------

      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }

//---------------------------------------
// show pop up
//---------------------------------------

  Future<void> _openViewDialog({required String title, required String description}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true, // allow tapping outside to close
      builder: (_) {
        return AlertDialog(
          title: Text(title.isEmpty ? '(No title)' : title, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 0.9.sw,
            child: SingleChildScrollView(
              child: Text(
                description.isEmpty ? '(No description)' : description,
                style: TextStyle(fontSize: 14.sp),
              ),
            ),
          ),
//---------------------------------------
// close button
//---------------------------------------
          actions: [
            Row(
              children: [
                const Spacer(),
                ElevatedButton(
                  onPressed: () { Navigator.pop(context); },
                  child: Text('Close', style: TextStyle(fontSize: 14.sp)),
                ),
              ],
            ),
          ],
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
