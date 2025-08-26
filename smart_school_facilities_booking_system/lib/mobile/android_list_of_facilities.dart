import 'package:flutter/material.dart';                       // UI widgets
import 'package:flutter/services.dart';                       // input formatters for digits
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

  // capacity controller (default 1) – only allow digits
  final TextEditingController _capCtrl = TextEditingController(text: '1');

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

    // whenever capacity text changes, rebuild to resort the list
    _capCtrl.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _capCtrl.dispose();
    super.dispose();
  }

  // --------------------
  // Capacity helpers
  // --------------------

  // read current capacity from the input (only int, min = 1)
  int _currentCapacity() {
    final raw = _capCtrl.text.trim();
    int v = int.tryParse(raw) ?? 1;
    if (v <= 0) {
      v = 1;
    }
    return v;
  }

  // parse any number-ish value from Firestore into int
  int _parseCapInt(dynamic v, int fallback) {
    if (v == null) {
      return fallback;
    } else {
      if (v is int) {
        return v;
      } else {
        if (v is double) {
          return v.floor();
        } else {
          if (v is String) {
            final t = v.trim();
            final n = int.tryParse(t);
            if (n == null) {
              return fallback;
            } else {
              return n;
            }
          } else {
            return fallback;
          }
        }
      }
    }
  }

  // check if userCap fits required and max (max<=0 means unlimited)
  bool _fitsCapacity(int userCap, int reqCap, int maxCap) {
    // treat maxCap <= 0 as unlimited
    bool withinMax;
    if (maxCap <= 0) {
      withinMax = true;
    } else {
      if (userCap <= maxCap) {
        withinMax = true;
      } else {
        withinMax = false;
      }
    }

    if (userCap >= reqCap && withinMax == true) {
      return true;
    } else {
      return false;
    }
  }

  // sort list: matching facilities first, then by ascending requiredCapacity
  void _sortByCapacityRule(List<Map<String, dynamic>> list, int userCap) {
    list.sort((a, b) {
      // read req/max for A
      int reqA;
      if (a['reqCap'] is int) {
        reqA = a['reqCap'];
      } else {
        reqA = 1;
      }
      int maxA;
      if (a['maxCap'] is int) {
        maxA = a['maxCap'];
      } else {
        maxA = 0; // 0 = unlimited
      }
      // read req/max for B
      int reqB;
      if (b['reqCap'] is int) {
        reqB = b['reqCap'];
      } else {
        reqB = 1;
      }
      int maxB;
      if (b['maxCap'] is int) {
        maxB = b['maxCap'];
      } else {
        maxB = 0;
      }

      // compute group rank: 0 for fits, 1 for not fits
      int rankA;
      if (_fitsCapacity(userCap, reqA, maxA)) {
        rankA = 0;
      } else {
        rankA = 1;
      }
      int rankB;
      if (_fitsCapacity(userCap, reqB, maxB)) {
        rankB = 0;
      } else {
        rankB = 1;
      }

      // first compare by rank (fits first)
      if (rankA != rankB) {
        return rankA.compareTo(rankB);
      }

      // then compare by requiredCapacity ascending
      if (reqA != reqB) {
        return reqA.compareTo(reqB);
      }

      // finally small tie-breaker by name so order is stable
      String nameA;
      if (a['name'] is String) {
        nameA = a['name'];
      } else {
        nameA = '';
      }
      String nameB;
      if (b['name'] is String) {
        nameB = b['name'];
      } else {
        nameB = '';
      }
      return nameA.toLowerCase().compareTo(nameB.toLowerCase());
    });
  }
  // format capacity text like "3 - 10" or "3 - Unlimited"
  String _formatCapacityText(int reqCap, int maxCap) {
    String right;
    if (maxCap <= 0) {
      right = 'Unlimited';
    } else {
      right = maxCap.toString();
    }
    return '$reqCap - $right';
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
            // top row: capacity input + search bar + filter button
            // top row: [ icon | capacity box | search | filter ]
            Row(
              crossAxisAlignment: CrossAxisAlignment.center, // keep items aligned nicely
              children: [
                // capacity icon on the LEFT of the input
                Icon(
                  Icons.people_alt_outlined,          // people icon
                  size: 20.sp,
                  // scale with screen
                  color: Colors.black87,
                ),

                SizedBox(width: 6.w),                 // small gap between icon and input

                // capacity input (you can keep your 110.w x 44.h if you prefer bigger)
                SizedBox(
                  width: 90.w,                        // smaller width so search gets more space
                  height: 44.h,                       // smaller height (clean look)
                  child: _buildCapacityField(),       // our +/- number box (min = 1)
                ),

                SizedBox(width: 8.w),                 // gap before search

                // search fills remaining space
                Expanded(child: _buildSearchField()),

                SizedBox(width: 12.w),                // gap before filter

                // filter is a fixed square so it never wiggles
                SizedBox(
                  width: 44.h,
                  height: 44.h,
                  child: _buildFilterButton(),
                ),
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

                  // sort categories alphabetically for display (keep same behavior)
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
                        bool active;
                        if (data.containsKey('active') && data['active'] is bool) {
                          active = data['active'];
                        } else {
                          active = false;
                        }


                        // capacity fields (robust to different names)
                        int reqCap = 1; // default minimum = 1
                        int maxCap = 0; // 0 means unlimited

                        if (data.containsKey('requiredCapacity')) {
                          reqCap = _parseCapInt(data['requiredCapacity'], 1);
                        } else {
                          if (data.containsKey('requireCapacity')) {
                            reqCap = _parseCapInt(data['requireCapacity'], 1);
                          } else {
                            if (data.containsKey('minCapacity')) {
                              reqCap = _parseCapInt(data['minCapacity'], 1);
                            } else {
                              if (data.containsKey('minimumCapacity')) {
                                reqCap = _parseCapInt(data['minimumCapacity'], 1);
                              }
                            }
                          }
                        }

                        if (data.containsKey('maximumCapacity')) {
                          maxCap = _parseCapInt(data['maximumCapacity'], 0);
                        } else {
                          if (data.containsKey('maxCapacity')) {
                            maxCap = _parseCapInt(data['maxCapacity'], 0);
                          }
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
                          'reqCap': reqCap,
                          'maxCap': maxCap,
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

                          // grab user capacity once for sort
                          final int userCap = _currentCapacity();

                          // if a category is selected, show a flat list for that category only (ignore favorites header)
                          if (_selectedCategory != null) {
                            // capacity-first sort for flat list
                            _sortByCapacityRule(all, userCap);

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
                                return _facilityCard(
                                  sw: sw,
                                  data: item,
                                  isFavorite: favoriteIds.contains(item['id'] as String),
                                  onToggleFavorite: () async {
                                    await _toggleFavorite(item['id'] as String);
                                  },
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AndroidFacilityDetails(
                                          facilityId: item['id'] as String,
                                          facilityName: item['name'] as String,
                                          userCapacity: _currentCapacity(),
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
                            // capacity-first sort for search results
                            _sortByCapacityRule(all, userCap);

                            if (all.isEmpty) {
                              return const Center(child: Text('No facilities match your search'));
                            }

                            return ListView.separated(
                              itemCount: all.length,
                              separatorBuilder: (_, __) => SizedBox(height: 8.h),
                              itemBuilder: (context, i) {
                                final item = all[i];
                                return _facilityCard(
                                  sw: sw,
                                  data: item,
                                  isFavorite: favoriteIds.contains(item['id'] as String),
                                  onToggleFavorite: () async {
                                    await _toggleFavorite(item['id'] as String);
                                  },
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AndroidFacilityDetails(
                                          facilityId: item['id'] as String,
                                          facilityName: item['name'] as String,
                                          userCapacity: _currentCapacity(),
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

                          // capacity-first sort for favorites
                          // capacity-first sort for favorites
                          _sortByCapacityRule(favList, userCap);

// flatten all non-favorite facilities into one list (no category grouping)
                          final List<Map<String, dynamic>> others = <Map<String, dynamic>>[];
                          for (final entry in byCat.entries) {
                            final listForCat = entry.value;
                            if (listForCat.isNotEmpty) {
                              for (final m in listForCat) {
                                others.add(m);
                              }
                            }
                          }

// capacity-first sort for ALL non-favorites
                          _sortByCapacityRule(others, userCap);

// build the final list: Favorite first, then All Facilities
                          final List<Widget> children = <Widget>[];

                          children.add(_sectionHeader(title: 'Favorite', count: favList.length));
                          for (final item in favList) {
                            children.add(
                              _facilityCard(
                                sw: sw,
                                data: item,
                                isFavorite: true,
                                onToggleFavorite: () async {
                                  await _toggleFavorite(item['id'] as String);
                                },
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AndroidFacilityDetails(
                                        facilityId: item['id'] as String,
                                        facilityName: item['name'] as String,
                                        userCapacity: _currentCapacity(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          }

                          children.add(SizedBox(height: 12.h));

                          // “All Facilities” (no category headers)
                          children.add(_sectionHeader(title: 'All Facilities', count: others.length));
                          for (final item in others) {
                            final isFav = favoriteIds.contains(item['id'] as String); // usually false, but safe
                            children.add(
                              _facilityCard(
                                sw: sw,
                                data: item,
                                isFavorite: isFav,
                                onToggleFavorite: () async {
                                  await _toggleFavorite(item['id'] as String);
                                },
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AndroidFacilityDetails(
                                        facilityId: item['id'] as String,
                                        facilityName: item['name'] as String,
                                        userCapacity: _currentCapacity(),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
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
  // Widgets: Capacity, Search, Filter
  // ----------------------------------

  // capacity input with - and + (min = 1). This will sort lists by capacity rule.
  Widget _buildCapacityField() {
    return Container(
      height: 44.h,
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
      padding: EdgeInsets.symmetric(horizontal: 6.w),
      child: Row(
        children: [
          // minus button
          InkWell(
            onTap: () {
              int v = _currentCapacity();
              v = v - 1;
              if (v < 1) {
                v = 1;
              }
              _capCtrl.text = v.toString();
              _capCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _capCtrl.text.length));
            },
            borderRadius: BorderRadius.circular(8.r),
            child: SizedBox(
              width: 28.w,
              height: 28.h,
              child: const Icon(Icons.remove),
            ),
          ),
          SizedBox(width: 4.w),

          // number field
          Expanded(
            child: TextField(
              controller: _capCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                hintText: '1',
                border: InputBorder.none,
                isCollapsed: true,
              ),
              // onChanged handled via listener in initState()
            ),
          ),
          SizedBox(width: 4.w),

          // plus button
          InkWell(
            onTap: () {
              int v = _currentCapacity();
              v = v + 1;
              _capCtrl.text = v.toString();
              _capCtrl.selection = TextSelection.fromPosition(TextPosition(offset: _capCtrl.text.length));
            },
            borderRadius: BorderRadius.circular(8.r),
            child: SizedBox(
              width: 28.w,
              height: 28.h,
              child: const Icon(Icons.add),
            ),
          ),
        ],
      ),
    );
  }

  // search input (name only). Uses clear (X) when not empty.
  // We keep the layout stable while typing.
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
              textAlignVertical: TextAlignVertical.center,
              decoration: const InputDecoration(
                hintText: 'Search facility name',
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),

          // right: reserve a constant-width slot for the clear (X) button
          SizedBox(
            width: 36.w, // fixed, so layout never shifts
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

    // capacity fields
    int reqCap;
    if (data['reqCap'] is int) {
      reqCap = data['reqCap'];
    } else {
      reqCap = 1;
    }
    int maxCap;
    if (data['maxCap'] is int) {
      maxCap = data['maxCap'];
    } else {
      maxCap = 0; // 0 = unlimited
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
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12.r),
            onTap: onTap,
            child: Container(
              width: sw * 0.90,
              constraints: BoxConstraints(minHeight: 120.h),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(12.r),
              ),
              padding: EdgeInsets.all(10.w),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // left image
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8.r),
                    child: _buildFacilityImage(imagePath),
                  ),
                  SizedBox(width: 10.w),

                  // right side
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // name
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                        ),

                        SizedBox(height: 10.h),

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
                                mainAxisSize: MainAxisSize.min,
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

                        SizedBox(height: 6.h),

                        // capacity row (replaces time)
                        // capacity chip (bordered box)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h), // inner space
                              decoration: BoxDecoration(
                                color: Colors.white,                              // light bg
                                borderRadius: BorderRadius.circular(12.r),        // round corners
                                border: Border.all(color: Colors.grey.shade400),  // thin border
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person, size: 16.sp, color: Colors.black87),  // human icon
                                  SizedBox(width: 6.w),
                                  Text(
                                    _formatCapacityText(reqCap, maxCap), // "3 - 10" or "3 - Unlimited"
                                    style: TextStyle(fontSize: 13.sp, color: Colors.black87, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                      ],
                    ),
                  ),

                  // favourite star
                  IconButton(
                    onPressed: () async { await onToggleFavorite(); },
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

}
