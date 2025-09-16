// lib/mobile/android_faq.dart
// -----------------------------------------------------------------------------
// ANDROID FAQ PAGE (Student/Manager/Admin view)
// - AppBar and BottomMenuBar look the SAME as other Android pages (purple top bar,
//   rounded bottom corners). Title shows "FAQ".
// - Body: search field to filter FAQ titles, then a list of titles.
// - Tapping a title opens a dialog with Title + Description and a Close button.
// - Very simple code style (no complex patterns), comments on functions and actions.
// - ScreenUtil for all sizes (.w .h .sp .sw .sh) so it scales well (Samsung A32).
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// bottom bar + pages (same as other Android pages)
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
  // ---------------- simple page state ----------------
  int _currentIndex = 4; // keep Account tab highlighted since FAQ is opened from Account

  // ---------------- search controller + keyword ----------------
  final TextEditingController _searchCtrl = TextEditingController();
  String _keyword = '';

  // ---------------- bottom nav routing (same pattern) ---------------
  void _onTabSelected(int i) {
    if (i == 4) {
      // stay here or back to account? We'll route according to your main app behavior.
      // For consistency we keep the same destinations as Account page.
      // Here, we simply do nothing when Account is tapped, so the user can back using system back.
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

  // ---------------- Firestore helper (FAQ collection) ----------------
  CollectionReference<Map<String, dynamic>> _faqCol() {
    return FirebaseFirestore.instance.collection('FAQ');
  }

  // ---------------- build ----------------
  @override
  Widget build(BuildContext context) {
    final double barHeight = 60.h; // bottom bar height

    return Scaffold(
      // -------- AppBar same look as your Account page --------
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

      // -------- Body: search + list --------
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // search box
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

            // list of titles (stream + in-memory filter)
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
                  separatorBuilder: (_, __) => SizedBox(height: 8.h),
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

      // -------- Bottom bar (same as other pages) --------
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }

  // ---------------- dialog to show title + description ----------------
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

  // ---------------- dispose controller ----------------
  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}
