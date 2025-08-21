import 'package:flutter/material.dart';                       // UI widgets
import 'package:flutter_screenutil/flutter_screenutil.dart';  // .w .h .sp sizes
import 'package:firebase_auth/firebase_auth.dart';            // Firebase auth
import 'package:cloud_firestore/cloud_firestore.dart';        // Firestore
import 'android_login.dart';
import 'android_bottom_menu.dart';
import 'android_filter_category.dart';
import 'android_facility_details.dart';

// other pages
import 'android_calendar.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';

// ------------------------------
// List of Facilities (main page)
// ------------------------------
class AndroidListOfFacilities extends StatefulWidget {
  @override
  State<AndroidListOfFacilities> createState() => _AndroidListOfFacilitiesState();
}

class _AndroidListOfFacilitiesState extends State<AndroidListOfFacilities> {
  // bottom bar: this page index
  int _currentIndex = 2;

  // search bar controller
  final TextEditingController _searchCtrl = TextEditingController();

  // category picked from FilterCategory (null = no filter)
  String? _selectedCategory;

  // Firestore collections
  final CollectionReference<Map<String, dynamic>> _facCol =
  FirebaseFirestore.instance.collection('Facilities');

  final CollectionReference<Map<String, dynamic>> _catCol =
  FirebaseFirestore.instance.collection('FacilitiesCategory');

  // ---------------------------
  // Helpers for favourites path
  // ---------------------------

  // get user's favourites subcollection
  CollectionReference<Map<String, dynamic>>? _favColForCurrentUser() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null; // not logged in
    } else {
      return FirebaseFirestore.instance
          .collection('UserInformation')
          .doc(user.uid)
          .collection('favourite'); // doc id = facilityId
    }
  }

  // stream all favourite doc IDs for this user (each doc id == facilityId)
  Stream<Set<String>> _watchFavoriteIds() {
    final col = _favColForCurrentUser();
    if (col == null) {
      // no user -> empty set stream
      return Stream<Set<String>>.value(<String>{});
    } else {
      return col.snapshots().map((snap) {
        final ids = <String>{};
        for (final d in snap.docs) {
          ids.add(d.id);
        }
        return ids;
      });
    }
  }

  // toggle favourite (create/delete a doc)
  Future<void> _toggleFavorite(String facilityId) async {
    final col = _favColForCurrentUser();
    if (col == null) return;

    final ref = col.doc(facilityId);
    final snap = await ref.get();

    // if already fav -> remove
    if (snap.exists) {
      await ref.delete();
      return;
    }

    // else fetch facility name once, then save a tiny doc
    final facSnap = await _facCol.doc(facilityId).get();
    Map<String, dynamic>? m = facSnap.data();
    String name;
    if (m == null) {
      name = '';
    } else {
      if (m['name'] is String) {
        name = m['name'];
      } else {
        name = '';
      }
    }

    await ref.set({
      'facilityId': facilityId,
      'name': name,
    });
  }

  // batch remove a set of favourite docs (used when facility was deleted)
  Future<void> _removeFavorites(Iterable<String> ids) async {
    final col = _favColForCurrentUser();
    if (col == null) return;

    // nothing to delete
    bool hasAny = false;
    for (final _ in ids) {
      hasAny = true;
      break;
    }
    if (hasAny == false) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final id in ids) {
      batch.delete(col.doc(id));
    }
    await batch.commit();
  }

  // ----------------
  // Bottom bar nav
  // ----------------
  void _onTabSelected(int i) {
    if (i == 2) {
      setState(() {
        _currentIndex = 2; // stay here
      });
    } else if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidCalendar()));
    } else if (i == 1) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } else if (i == 3) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
    } else if (i == 4) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
    }
  }

  // -----------
  // Lifecycle
  // -----------
  @override
  void initState() {
    super.initState();
    // whenever the search text changes, rebuild to re-filter the list
    _searchCtrl.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // -----
  // UI
  // -----
  @override
  Widget build(BuildContext context) {
    // bottom bar height and screen width for responsive sizing
    final double barHeight = MediaQuery.of(context).size.height * 0.07;
    final double sw = MediaQuery.of(context).size.width;

    return Scaffold(
      // top app bar (purple) with rounded bottom corners
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: Text(
            "Facilities",
            style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600),
          ),
          actions: [
            // logout button
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => AndroidLoginPage()),
                      (route) => false,
                );
              },
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(40.r),
              bottomRight: Radius.circular(40.r),
            ),
          ),
        ),
      ),

      // page body
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // top row: search bar + filter button
            Row(
              children: [
                // search fills all remaining space
                Expanded(child: _buildSearchField()),
                SizedBox(width: 12.w),
                // filter is a fixed square so it never wiggles
                SizedBox(width: 44.h, height: 44.h, child: _buildFilterButton()),
              ],
            ),
            SizedBox(height: 20.h),

            // data section (categories -> facilities -> favourites)
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _catCol.snapshots(),
                builder: (context, catSnap) {
                  // show loader while categories load
                  if (catSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  // show error state
                  if (catSnap.hasError) {
                    return const Center(child: Text('Failed to load categories'));
                  }

                  // build simple helpers for categories
                  List<QueryDocumentSnapshot<Map<String, dynamic>>> catDocs;
                  if (catSnap.data == null) {
                    catDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  } else {
                    catDocs = catSnap.data!.docs;
                  }

                  // map: categoryId -> categoryName
                  final Map<String, String> catIdToName = <String, String>{};
                  // set of all lowercased category names
                  final Set<String> catNameLowerSet = <String>{};
                  // sorted list of categories for grouped layout
                  final List<String> orderedCategoryNames = <String>[];

                  for (final d in catDocs) {
                    final m = d.data();
                    bool isDeleted = false;
                    if (m.containsKey('deleted')) {
                      if (m['deleted'] is bool) {
                        if (m['deleted'] == true) isDeleted = true;
                      }
                    }
                    if (isDeleted) continue;

                    if (m.containsKey('name')) {
                      if (m['name'] is String) {
                        final name = m['name'] as String;
                        catIdToName[d.id] = name;
                        catNameLowerSet.add(name.toLowerCase());
                        orderedCategoryNames.add(name);
                      }
                    }
                  }

                  // sort categories alphabetically for display
                  orderedCategoryNames.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

                  // now stream facilities
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _facCol.snapshots(),
                    builder: (context, facSnap) {
                      if (facSnap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (facSnap.hasError) {
                        return const Center(child: Text('Failed to load facilities'));
                      }

                      List<QueryDocumentSnapshot<Map<String, dynamic>>> facDocs;
                      if (facSnap.data == null) {
                        facDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                      } else {
                        facDocs = facSnap.data!.docs;
                      }

                      // build a flat list of visible facilities (after filtering)
                      final List<Map<String, dynamic>> all = <Map<String, dynamic>>[];

                      // set of non-deleted facility ids (used to clean stale favourites)
                      final Set<String> activeFacilityIds = <String>{};

                      // current search text
                      final String q = _searchCtrl.text.trim().toLowerCase();

                      // walk every facility doc
                      for (final d in facDocs) {
                        final data = d.data();

                        // skip if deleted
                        bool deleted = false;
                        if (data.containsKey('deleted')) {
                          if (data['deleted'] is bool) {
                            if (data['deleted'] == true) deleted = true;
                          }
                        }
                        if (deleted == true) continue;

                        final String id = d.id;
                        activeFacilityIds.add(id);

                        // read name
                        String name;
                        if (data.containsKey('name') && data['name'] is String) {
                          name = data['name'];
                        } else {
                          name = '(Unnamed Facility)';
                        }

                        // resolve category name (prefer categoryId; fallback to stored categoryName)
                        String? categoryName;

                        if (data.containsKey('categoryId') && data['categoryId'] is String) {
                          final cid = data['categoryId'] as String;
                          if (catIdToName.containsKey(cid)) {
                            categoryName = catIdToName[cid];
                          }
                        }
                        if (categoryName == null) {
                          if (data.containsKey('categoryName') && data['categoryName'] is String) {
                            final low = (data['categoryName'] as String).toLowerCase();
                            if (catNameLowerSet.contains(low)) {
                              // find original case name from our list
                              for (final cname in orderedCategoryNames) {
                                if (cname.toLowerCase() == low) {
                                  categoryName = cname;
                                  break;
                                }
                              }
                            }
                          }
                        }

                        // if a category was picked, only keep items in that category
                        if (_selectedCategory != null) {
                          final sel = _selectedCategory!.toLowerCase();
                          String cat;
                          if (categoryName == null) {
                            cat = '';
                          } else {
                            cat = categoryName.toLowerCase();
                          }
                          if (sel != cat) continue;
                        }

                        // search by facility name (case-insensitive)
                        if (q.isNotEmpty) {
                          if (name.toLowerCase().contains(q) == false) continue;
                        }

                        // keep basic fields for UI
                        // image path
                        String imagePath = '';
                        if (data.containsKey('imagePath') && data['imagePath'] is String) {
                          imagePath = data['imagePath'];
                        } else {
                          // legacy imageName
                          if (data.containsKey('imageName') && data['imageName'] is String) {
                            String nv = (data['imageName'] as String).trim();
                            if (nv.isNotEmpty) {
                              imagePath = 'asset/image/$nv';
                            }
                          }
                        }

                        // active flag
                        bool active = false;
                        if (data.containsKey('active') && data['active'] is bool) {
                          active = data['active'];
                        }

                        // time (start/end)
                        String start24 = '';
                        String end24 = '';
                        if (data.containsKey('availableTime') && data['availableTime'] is Map<String, dynamic>) {
                          final at = data['availableTime'] as Map<String, dynamic>;
                          if (at.containsKey('start') && at['start'] is String) start24 = at['start'];
                          if (at.containsKey('end') && at['end'] is String) end24 = at['end'];
                        } else if (data.containsKey('availabletime') && data['availabletime'] is Map<String, dynamic>) {
                          final at = data['availabletime'] as Map<String, dynamic>;
                          if (at.containsKey('start') && at['start'] is String) start24 = at['start'];
                          if (at.containsKey('end') && at['end'] is String) end24 = at['end'];
                        }

                        // if NOT searching and NO category picked, skip facilities that don't match a valid category
                        if (q.isEmpty && _selectedCategory == null) {
                          if (categoryName == null) continue;
                        }

                        // collect one item
                        final item = <String, dynamic>{
                          'id': id,
                          'name': name,
                          'categoryName': categoryName, // may be null in search mode
                          'imagePath': imagePath,
                          'active': active,
                          'start24': start24,
                          'end24': end24,
                        };
                        all.add(item);
                      }

                      // now that we built the visible list, we still need favourite IDs
                      return StreamBuilder<Set<String>>(
                        stream: _watchFavoriteIds(),
                        builder: (context, favSnap) {
                          Set<String> favoriteIds;
                          if (favSnap.data == null) {
                            favoriteIds = <String>{};
                          } else {
                            favoriteIds = favSnap.data!;
                          }

                          // auto-remove favourites for deleted facilities
                          final Set<String> staleFavIds = favoriteIds.difference(activeFacilityIds);
                          if (staleFavIds.isNotEmpty) {
                            WidgetsBinding.instance.addPostFrameCallback((_) async {
                              await _removeFavorites(staleFavIds);
                            });
                          }

                          // if a category is selected, show a flat list for that category only (ignore favorites header)
                          if (_selectedCategory != null) {
                            // sort by name
                            all.sort((a, b) =>
                                (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));

                            if (all.isEmpty) {
                              return Center(
                                child: Text(
                                  'No facilities in "${_selectedCategory!}"',
                                  style: TextStyle(fontSize: 14.sp),
                                ),
                              );
                            }

                            return ListView.separated(
                              itemCount: all.length,
                              separatorBuilder: (_, __) => SizedBox(height: 8.h),
                              itemBuilder: (context, i) {
                                final item = all[i];
                                final isFav = favoriteIds.contains(item['id'] as String);
                                // A) In the "selected category" flat list section (inside itemBuilder)
                                return _facilityCard(
                                  sw: sw,
                                  data: item,
                                  isFavorite: favoriteIds.contains(item['id'] as String),
                                  onToggleFavorite: () async { await _toggleFavorite(item['id'] as String); },
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AndroidFacilityDetails(
                                          facilityId: item['id'] as String,
                                          facilityName: item['name'] as String,
                                        ),
                                      ),
                                    );
                                  },
                                );

                              },
                            );
                          }

                          // if searching, also show a flat list (ignore favorites header)
                          final String qNow = _searchCtrl.text.trim();
                          if (qNow.isNotEmpty) {
                            all.sort((a, b) =>
                                (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));

                            if (all.isEmpty) {
                              return const Center(child: Text('No facilities match your search'));
                            }

                            return ListView.separated(
                              itemCount: all.length,
                              separatorBuilder: (_, __) => SizedBox(height: 8.h),
                              itemBuilder: (context, i) {
                                final item = all[i];
                                final isFav = favoriteIds.contains(item['id'] as String);
                                return _facilityCard(
                                  sw: sw,
                                  data: item,
                                  isFavorite: favoriteIds.contains(item['id'] as String),
                                  onToggleFavorite: () async { await _toggleFavorite(item['id'] as String); },
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AndroidFacilityDetails(
                                          facilityId: item['id'] as String,
                                          facilityName: item['name'] as String,
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          }

                          // otherwise: group by category and show "Favorite" section
                          final List<Map<String, dynamic>> favList = <Map<String, dynamic>>[];
                          final Map<String, List<Map<String, dynamic>>> byCat =
                          <String, List<Map<String, dynamic>>>{};

                          for (final m in all) {
                            final id = m['id'] as String;
                            String catName;
                            if (m['categoryName'] is String) {
                              catName = m['categoryName'];
                            } else {
                              catName = '';
                            }

                            if (favoriteIds.contains(id)) {
                              favList.add(m);
                            } else {
                              if (byCat.containsKey(catName)) {
                                byCat[catName]!.add(m);
                              } else {
                                byCat[catName] = <Map<String, dynamic>>[m];
                              }
                            }
                          }

                          // sort everything by name for neatness
                          favList.sort((a, b) =>
                              (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
                          for (final entry in byCat.entries) {
                            entry.value.sort((a, b) =>
                                (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
                          }

                          // build the grouped list
                          final List<Widget> children = <Widget>[];

                          children.add(_sectionHeader(title: 'Favorite', count: favList.length));
                          for (final item in favList) {
                            children.add(
                                _facilityCard(
                                  sw: sw,
                                  data: item,
                                  isFavorite: true, // or computed for non-favorites
                                  onToggleFavorite: () async { await _toggleFavorite(item['id'] as String); },
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AndroidFacilityDetails(
                                          facilityId: item['id'] as String,
                                          facilityName: item['name'] as String,
                                        ),
                                      ),
                                    );
                                  },
                                )
                            );
                          }

                          children.add(SizedBox(height: 12.h));

                          // categories in the same order as read at top
                          for (final catName in orderedCategoryNames) {
                            List<Map<String, dynamic>>? listForCat = byCat[catName];
                            bool hasItems = false;
                            if (listForCat != null) {
                              if (listForCat.isNotEmpty) hasItems = true;
                            }
                            if (hasItems == false) continue;

                            children.add(_sectionHeader(title: catName, count: listForCat!.length));
                            for (final item in listForCat) {
                              final isFav = favoriteIds.contains(item['id'] as String);
                              children.add(
                                _facilityCard(
                                  sw: sw,
                                  data: item,
                                  isFavorite: isFav,
                                  onToggleFavorite: () async { await _toggleFavorite(item['id'] as String); },
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AndroidFacilityDetails(
                                          facilityId: item['id'] as String,
                                          facilityName: item['name'] as String,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              );
                            }


                            children.add(SizedBox(height: 12.h));
                          }

                          return ListView(children: children);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),

      // bottom menu
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }

  // ----------------------------------
  // Widgets: Search field and button
  // ----------------------------------

  // search input (name only). Uses clear (X) when not empty.
  // search input (name only). We keep the layout stable while typing.
// - Always reserve space for the clear (X) so text doesn't jump.
// - Use Expanded in the Row above so this grows/shrinks nicely.
  Widget _buildSearchField() {
    return Container(
      height: 44.h, // fixed height for stable layout
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
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

          // the text field fills remaining space minus the reserved X slot on the right
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              // keep text vertically centered, avoid height change on some devices
              textAlignVertical: TextAlignVertical.center,
              decoration: const InputDecoration(
                hintText: 'Search facility name',
                border: InputBorder.none,
                isCollapsed: true, // remove extra vertical padding
              ),
            ),
          ),

          // right: reserve a constant-width slot for the clear (X) button
          SizedBox(
            width: 36.w, // fixed, so layout never shifts
            child: Align(
              alignment: Alignment.centerRight,
              child: Visibility(
                visible: _searchCtrl.text.isNotEmpty,   // show only when there is text
                maintainSize: true,                     // still keep the space when hidden
                maintainAnimation: true,
                maintainState: true,
                child: InkWell(
                  onTap: () { _searchCtrl.clear(); },   // clear text and rebuild
                  child: Icon(Icons.clear, size: 20.sp, color: Colors.grey.shade700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  // filter button: opens FilterCategory page and stores the result
  Widget _buildFilterButton() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12.r),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: () async {
          // open category picker page
          final picked = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FilterCategory()),
          );

          // picked can be a String (category name) or null (None)
          if (picked is String) {
            if (picked.trim().isEmpty) {
              setState(() {
                _selectedCategory = null; // treat empty as None
              });
            } else {
              setState(() {
                _selectedCategory = picked;
              });
            }
          } else {
            // user chose "None" or backed out -> clear filter
            setState(() {
              _selectedCategory = null;
            });
          }
        },
        child: Center(child: Icon(Icons.filter_list, color: Colors.grey.shade800)),
      ),
    );
  }

  // ----------------------------------
  // Small reusable UI bits
  // ----------------------------------

  // section header like: "Favorite - 3"
  Widget _sectionHeader({required String title, required int count}) {
    return Padding(
      padding: EdgeInsets.only(left: 6.w, bottom: 8.h, top: 8.h),
      child: Text(
        '$title - $count',
        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
      ),
    );
  }

  // one facility card: image (left), details (right), star button
  // one facility card: image (left), details (right), star button
  Widget _facilityCard({
    required double sw,
    required Map<String, dynamic> data,
    required bool isFavorite,
    required Future<void> Function() onToggleFavorite,
    required VoidCallback onTap,
  }) {
    // read fields safely without ternary/?? (follow your style)
    String name;
    if (data['name'] is String) {
      name = data['name'];
    } else {
      name = '(Unnamed Facility)';
    }

    String imagePath;
    if (data['imagePath'] is String) {
      imagePath = data['imagePath'];
    } else {
      imagePath = '';
    }

    bool active;
    if (data['active'] is bool) {
      active = data['active'];
    } else {
      active = false;
    }

    String start24;
    if (data['start24'] is String) {
      start24 = data['start24'];
    } else {
      start24 = '';
    }

    String end24;
    if (data['end24'] is String) {
      end24 = data['end24'];
    } else {
      end24 = '';
    }

    // pick star icon + color (favorite)
    IconData starIcon;
    if (isFavorite) {
      starIcon = Icons.star;
    } else {
      starIcon = Icons.star_border;
    }
    Color starColor;
    if (isFavorite) {
      starColor = Colors.amber;
    } else {
      starColor = Colors.black45;
    }

    // availability chip text + color
    String availText;
    Color availColor;
    if (active) {
      availText = 'Available';
      availColor = Colors.green;
    } else {
      availText = 'Not Available';
      availColor = Colors.red;
    }

    // build the card
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Center(
        child: Material(
          color: Colors.transparent,                 // keep ripple nice
          child: InkWell(
            borderRadius: BorderRadius.circular(12.r), // touch feedback shape
            onTap: onTap,                               // go details
            child: Container(
              width: sw * 0.90,                        // 90% width
              // IMPORTANT: remove fixed height; allow content to grow
              // give a gentle minimum height so small items still look neat
              constraints: BoxConstraints(minHeight: 120.h),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12.r),
              ),
              padding: EdgeInsets.all(10.w),           // inner padding
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // left image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8.r),
                    child: _buildFacilityImage(imagePath),
                  ),
                  SizedBox(width: 10.w),

                  // right side texts (let this area flex and wrap)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,          // do not force extra height
                      children: [
                        // facility name (can wrap to 2 lines)
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                        ),

                        SizedBox(height: 10.h), // slightly smaller gap to save space

                        // availability chip
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                              decoration: BoxDecoration(
                                color: availColor.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20.r),
                                border: Border.all(color: availColor),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min, // only as wide as needed
                                children: [
                                  Icon(
                                    active ? Icons.check_circle : Icons.cancel,
                                    size: 16.sp,
                                    color: availColor,
                                  ),
                                  SizedBox(width: 6.w),
                                  Text(
                                    availText,
                                    style: TextStyle(fontSize: 12.sp, color: availColor, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: 6.h), // smaller gap again

                        // time range (allow wrap to avoid overflow on small screens)
                        Text(
                          _formatTimeRange24ToAmPm(start24, end24),
                          style: TextStyle(fontSize: 12.sp, color: Colors.black87),
                          maxLines: 2,                    // allow up to 2 lines
                          softWrap: true,                 // wrap words
                          overflow: TextOverflow.ellipsis, // fade if still too long
                        ),
                      ],
                    ),
                  ),

                  // favourite star button on the far right
                  IconButton(
                    onPressed: () async {
                      await onToggleFavorite();
                    },
                    icon: Icon(starIcon),
                    color: starColor,
                    iconSize: 26.sp,
                    tooltip: 'Favorite',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  // image loader with placeholder
  Widget _buildFacilityImage(String imagePath) {
    if (imagePath.isEmpty) {
      return Container(
        width: 110.w,
        height: 110.w,
        color: Colors.grey.shade400,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported, color: Colors.white),
      );
    } else {
      return Image.asset(
        imagePath,
        width: 110.w,
        height: 110.w,
        fit: BoxFit.cover,
      );
    }
  }

  // ---------------------------
  // Time formatting (simple)
  // ---------------------------

  // turn "HH:mm" + "HH:mm" into "From HH:mm am to HH:mm pm"
  String _formatTimeRange24ToAmPm(String start24, String end24) {
    if (start24.isEmpty && end24.isEmpty) {
      return 'Time not set';
    } else {
      final left = _toAmPm(start24);
      final right = _toAmPm(end24);
      String l;
      if (left.isEmpty) {
        l = start24;
      } else {
        l = left;
      }
      String r;
      if (right.isEmpty) {
        r = end24;
      } else {
        r = right;
      }
      return 'From $l to $r';
    }
  }

  // keep 24h digits and just add "am"/"pm" using simple hour checks
  String _toAmPm(String hhmm) {
    final t = hhmm.trim();
    if (t.isEmpty) return '';

    final parts = t.split(':');
    if (parts.isEmpty) return '';

    int hour = -1;
    int minute = 0;

    // parse hour
    final h = int.tryParse(parts[0]);
    if (h == null) {
      hour = -1;
    } else {
      hour = h;
    }

    // parse minute if present
    if (parts.length >= 2) {
      final m = int.tryParse(parts[1]);
      if (m == null) {
        minute = 0;
      } else {
        minute = m;
      }
    }

    // invalid hour -> return original string
    if (hour < 0 || hour > 23) return t;

    // am for 00:00..11:59, pm for 12:00..23:59
    String suffix;
    if (hour >= 12) {
      suffix = 'pm';
    } else {
      suffix = 'am';
    }

    // pad hour/minute to 2 digits
    String hh = hour.toString();
    if (hh.length == 1) hh = '0$hh';

    String mm = minute.toString();
    if (mm.length == 1) mm = '0$mm';

    return '$hh:$mm $suffix';
  }
}
