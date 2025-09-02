import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// bottom nav + pages
import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart';

class FilterCategory extends StatefulWidget {
  const FilterCategory({super.key});

  @override
  State<FilterCategory> createState() => _FilterCategoryState();
}

class _FilterCategoryState extends State<FilterCategory> {
  // keep Facilities tab highlighted
  int _currentIndex = 2;

  // search controller
  final TextEditingController _searchCtrl = TextEditingController();

  // firestore collection reference
  final CollectionReference<Map<String, dynamic>> _catCol =
  FirebaseFirestore.instance.collection('FacilitiesCategory');

  // attach search listener to rebuild on change
  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
  }

  // dispose controller to avoid leaks
  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // bottom bar navigation: simple if/else routing
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

  // build main scaffold
  @override
  Widget build(BuildContext context) {
    final double barHeight = MediaQuery.of(context).size.height * 0.07;
    final double sw = MediaQuery.of(context).size.width;

    return Scaffold(
      // app bar with title
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

      // page body
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Column(
          children: [
            // search bar
            _buildSearchField(),

            SizedBox(height: 16.h),

            // header
            Text(
              "Choose a category",
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600),
            ),

            SizedBox(height: 12.h),

            // category list
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

                  // normalize query
                  final String q = _searchCtrl.text.trim().toLowerCase();

                  // take docs (or empty)
                  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
                      snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                  // filter visible names (skip deleted, match search)
                  final List<String> names = <String>[];
                  for (final d in docs) {
                    final Map<String, dynamic> data = d.data();
                    final bool isDeleted = (data['deleted'] is bool) ? (data['deleted'] as bool) : false;
                    if (isDeleted == true) {
                      continue;
                    }

                    if (data['name'] is String) {
                      final String name = (data['name'] as String).trim();
                      if (name.isEmpty == true) {
                        continue;
                      }
                      if (q.isNotEmpty == true && name.toLowerCase().contains(q) == false) {
                        continue;
                      }
                      names.add(name);
                    }
                  }

                  // sort by name
                  names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

                  // leading "None" to clear filter
                  final List<Widget> tiles = <Widget>[
                    _categoryTile(
                      sw: sw,
                      title: 'None',
                      onTap: () => Navigator.pop(context, null),
                    ),
                    SizedBox(height: 10.h),
                  ];

                  // add items
                  tiles.addAll(
                    names.map(
                          (n) => Padding(
                        padding: EdgeInsets.only(bottom: 10.h),
                        child: _categoryTile(
                          sw: sw,
                          title: n,
                          onTap: () => Navigator.pop(context, n),
                        ),
                      ),
                    ),
                  );

                  // show "no match" when empty
                  if (names.isEmpty == true) {
                    return ListView(
                      children: <Widget>[
                        ...tiles,
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

      // bottom navigation bar
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }

  // build the search field with stable width for clear button
  Widget _buildSearchField() {
    return Container(
      height: 44.h,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22.r),
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
          // search icon
          const Icon(Icons.search, color: Colors.grey),

          SizedBox(width: 8.w),

          // input
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              textAlignVertical: TextAlignVertical.center,
              decoration: const InputDecoration(
                hintText: 'Search category',
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),

          // reserved area for clear button (no layout jump)
          SizedBox(
            width: 36.w,
            child: Align(
              alignment: Alignment.centerRight,
              child: Visibility(
                visible: _searchCtrl.text.isNotEmpty,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: InkWell(
                  onTap: () {
                    _searchCtrl.clear();
                  },
                  child: Icon(Icons.clear, size: 20.sp, color: Colors.grey.shade700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // build a single category tile row
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
          width: sw,
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
