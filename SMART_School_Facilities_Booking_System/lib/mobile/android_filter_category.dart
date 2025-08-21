import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// bottom nav + pages
import 'android_bottom_menu.dart';
import 'android_calendar.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart'; // make sure this path matches your file

class FilterCategory extends StatefulWidget {
  const FilterCategory({super.key});

  @override
  State<FilterCategory> createState() => _FilterCategoryState();
}

class _FilterCategoryState extends State<FilterCategory> {
  // keep Facilities tab highlighted
  int _currentIndex = 2;

  final TextEditingController _searchCtrl = TextEditingController();
  final CollectionReference<Map<String, dynamic>> _catCol =
  FirebaseFirestore.instance.collection('FacilitiesCategory');

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Bottom bar navigation: simple if/else routing.
  void _onTabSelected(int i) {
    if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidCalendar()));
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
    final double sw = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: Text(
            "Filter Category",
            style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600),
          ),

        ),
      ),

      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Column(
          children: [
            // Search bar
            _buildSearchField(),

            SizedBox(height: 16.h),

            // "Choose a category" header (like your mock)
            Text(
              "Choose a category",
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
            ),

            SizedBox(height: 12.h),

            // Category list
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _catCol.snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return const Center(child: Text('Failed to load categories'));
                  }

                  final q = _searchCtrl.text.trim().toLowerCase();
                  final docs = (snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]);

                  // Build list, skip deleted==true, search by name
                  final List<String> names = [];
                  for (final d in docs) {
                    final data = d.data();
                    final isDeleted = (data['deleted'] is bool) ? (data['deleted'] as bool) : false;
                    if (isDeleted) continue;

                    if (data['name'] is String) {
                      final name = (data['name'] as String).trim();
                      if (name.isEmpty) continue;
                      if (q.isNotEmpty && !name.toLowerCase().contains(q)) continue;
                      names.add(name);
                    }
                  }

                  names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

                  // Add a "None" option to clear filter
                  final List<Widget> tiles = [
                    _categoryTile(
                      sw: sw,
                      title: 'None',
                      onTap: () => Navigator.pop(context, null), // clear filter
                    ),
                    SizedBox(height: 10.h),
                  ];

                  tiles.addAll(
                    names.map((n) => Padding(
                      padding: EdgeInsets.only(bottom: 10.h),
                      child: _categoryTile(
                        sw: sw,
                        title: n,
                        onTap: () => Navigator.pop(context, n), // return picked name
                      ),
                    )),
                  );

                  if (names.isEmpty) {
                    return ListView(
                      children: tiles +
                          [
                            SizedBox(height: 12.h),
                            Center(
                              child: Text(
                                'No categories match your search',
                                style: TextStyle(fontSize: 14.sp, color: Colors.black54),
                              ),
                            ),
                          ],
                    );
                  }

                  return ListView(children: tiles);
                },
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex, // keep Facilities tab highlighted
        onTabSelected: _onTabSelected,
      ),
    );
  }

  // ---- UI helpers ----

// search bar with stable layout (no jumping when the X appears)
  Widget _buildSearchField() {
    return Container(
      height: 44.h, // fixed height for consistency
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22.r), // pill style like your mock
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Row(
        children: [
          // left search icon
          const Icon(Icons.search, color: Colors.grey),

          SizedBox(width: 8.w),

          // text input fills the remaining space
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              // keep text vertically centered and remove extra padding
              textAlignVertical: TextAlignVertical.center,
              decoration: const InputDecoration(
                hintText: 'Search category',
                border: InputBorder.none,
                isCollapsed: true, // no default top/bottom padding
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),

          // right: reserve space for the clear (X) button so nothing shifts
          SizedBox(
            width: 36.w, // fixed width slot (always reserved)
            child: Align(
              alignment: Alignment.centerRight,
              child: Visibility(
                visible: _searchCtrl.text.isNotEmpty, // only show when there is text
                maintainSize: true,                   // but keep the space even when hidden
                maintainAnimation: true,
                maintainState: true,
                child: InkWell(
                  onTap: () { _searchCtrl.clear(); }, // clear and rebuild (listener in initState)
                  child: Icon(Icons.clear, size: 20.sp, color: Colors.grey.shade700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _categoryTile({
    required double sw,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.grey.shade300,
      borderRadius: BorderRadius.circular(10.r),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.r),
        onTap: onTap,
        child: Container(
          width: sw, // scales to screen width
          height: 52.h,
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
