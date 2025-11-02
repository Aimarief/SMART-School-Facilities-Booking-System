import 'package:flutter/material.dart';                       // UI widgets
import 'package:flutter/services.dart';                       // input formatters for digits
import 'package:flutter_screenutil/flutter_screenutil.dart';  // .w .h .sp sizes
import 'package:firebase_auth/firebase_auth.dart';            // Firebase auth
import 'package:cloud_firestore/cloud_firestore.dart';        // Firestore


import 'android_bottom_menu.dart';

// filters  details page
import 'android_filter_category.dart';
import 'android_facility_details.dart';

// pages for bottom nav
import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';

class AndroidListOfFacilities extends StatefulWidget {

  @override
  State<AndroidListOfFacilities> createState() => _AndroidListOfFacilitiesState();
}

class _AndroidListOfFacilitiesState extends State<AndroidListOfFacilities> {
//---------------------------------------
// index in 2
//---------------------------------------

  int _currentIndex = 2;

  final TextEditingController _searchCtrl = TextEditingController();

  final TextEditingController _capCtrl = TextEditingController(text: '1');

  String? _selectedCategory;

//---------------------------------------
// get facilites database collection
//---------------------------------------

  final CollectionReference<Map<String, dynamic>> _facCol =
  FirebaseFirestore.instance.collection('Facilities');

//---------------------------------------
// facilities category colelction
//---------------------------------------

  final CollectionReference<Map<String, dynamic>> _catCol =
  FirebaseFirestore.instance.collection('FacilitiesCategory');

//---------------------------------------
// get user favourite facility sub collection
//---------------------------------------
  CollectionReference<Map<String, dynamic>>? _favColForCurrentUser() {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return null;
    } else {
      return FirebaseFirestore.instance
          .collection('UserInformation')
          .doc(user.uid)
          .collection('favourite');
    }
  }

//---------------------------------------
// get the favourite facility id
//---------------------------------------
  Stream<Set<String>> _watchFavoriteIds() {
    final col = _favColForCurrentUser();
    if (col == null) {
      return Stream<Set<String>>.value(<String>{});
    } else {
      return col.snapshots().map((snap) {
        final Set<String> ids = <String>{};
        for (final d in snap.docs) {
          ids.add(d.id);
        }
        return ids;
      });
    }
  }

//---------------------------------------
// press favourite will toggle yes and no
//---------------------------------------
  Future<void> _toggleFavorite(String facilityId) async {
    final col = _favColForCurrentUser();
    if (col == null) return;

    final ref = col.doc(facilityId);
    final snap = await ref.get();
//---------------------------------------
// if the facility exist in the favourite list then remove it
//---------------------------------------
    if (snap.exists) {
      await ref.delete();
      return;
    }

//---------------------------------------
// get the facility id and name then
//---------------------------------------

    final facSnap = await _facCol.doc(facilityId).get();
    final Map<String, dynamic>? m = facSnap.data();
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
//---------------------------------------
// set it in database
//---------------------------------------
    await ref.set({
      'facilityId': facilityId,
      'name': name,
    });
  }

//---------------------------------------
// remove from favourite
//---------------------------------------

  Future<void> _removeFavorites(Iterable<String> ids) async {
    final col = _favColForCurrentUser();
    if (col == null) return;

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

//---------------------------------------
// bottom menu navigation page
//---------------------------------------

  void _onTabSelected(int i) {
    if (i == 2) {
      setState(() {
        _currentIndex = 2;
      });
    } else if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAgenda()));
    } else if (i == 1) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } else if (i == 3) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
    } else if (i == 4) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
    }
  }

//---------------------------------------
// run init state first
//---------------------------------------
  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _capCtrl.addListener(() => setState(() {}));
  }

  // dispose controllers
  @override
  void dispose() {
    _searchCtrl.dispose();
    _capCtrl.dispose();
    super.dispose();
  }

//---------------------------------------
// read current capacity
//---------------------------------------
  int _currentCapacity() {
    final String raw = _capCtrl.text.trim();
    int v = int.tryParse(raw) ?? 1;
    if (v <= 0) {
      v = 1;
    }
    return v;
  }

//---------------------------------------
// parse int
//---------------------------------------
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
            final String t = v.trim();
            final int? n = int.tryParse(t);
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

//---------------------------------------
// check capacity if it is fit
//---------------------------------------
  bool _fitsCapacity(int userCap, int reqCap, int maxCap) {
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

//---------------------------------------
// sort facility by capacity rules
//---------------------------------------
  void _sortByCapacityRule(List<Map<String, dynamic>> list, int userCap) {
    list.sort((a, b) {
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
        maxA = 0;
      }

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
//compute rank: 0 if fits, 1 if does NOT fit (lower rank = better or above)
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
//Rule 1: items that fit come first
      if (rankA != rankB) {
        return rankA.compareTo(rankB);
      }
// Rule 2: among same "fit" status, smaller reqCap first
      if (reqA != reqB) {
        return reqA.compareTo(reqB);
      }
//Rule 3: if still tied, sort by name A→Z
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

//---------------------------------------
// for mat capacity text
//---------------------------------------
  String _formatCapacityText(int reqCap, int maxCap) {
    String right;
    if (maxCap <= 0) {
      right = 'Unlimited';
    } else {
      right = maxCap.toString();
    }
    return '$reqCap - $right';
  }

//---------------------------------------
// main build
//---------------------------------------
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
            "Facilities",
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
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
//---------------------------------------
// top part
//---------------------------------------
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
//---------------------------------------
// input capacity
//---------------------------------------
                Icon(Icons.people_alt_outlined, size: 20.sp, color: Colors.black87),
                SizedBox(width: 6.w),
                SizedBox(width: 90.w, height: 44.h, child: _buildCapacityField()),
                SizedBox(width: 8.w),
//---------------------------------------
// search field
//---------------------------------------
                Expanded(child: _buildSearchField()),
                SizedBox(width: 12.w),
//---------------------------------------
// filter category button
//---------------------------------------
                SizedBox(width: 44.h, height: 44.h, child: _buildFilterButton()),
              ],
            ),

            SizedBox(height: 20.h),

//---------------------------------------
// start to get all the facility that align with the choice
//---------------------------------------
            Expanded(
//---------------------------------------
// get category database
//---------------------------------------
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _catCol.snapshots(),
                builder: (context, catSnap) {
                  if (catSnap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (catSnap.hasError) {
                    return const Center(child: Text('Failed to load categories'));
                  }

                  List<QueryDocumentSnapshot<Map<String, dynamic>>> catDocs;
                  if (catSnap.data == null) {
                    catDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  } else {
                    catDocs = catSnap.data!.docs;
                  }

                  final Map<String, String> catIdToName = <String, String>{};
                  final Set<String> catNameLowerSet = <String>{};
                  final List<String> orderedCategoryNames = <String>[];

                  for (final d in catDocs) {
                    final Map<String, dynamic> m = d.data();
                    bool isDeleted = false;
                    if (m.containsKey('deleted')) {
                      if (m['deleted'] is bool) {
                        if (m['deleted'] == true)
                          isDeleted = true;
                      }
                    }
                    if (isDeleted == true) continue;

                    if (m.containsKey('name')) {
                      if (m['name'] is String) {
                        final String name = m['name'];
                        catIdToName[d.id] = name;
                        catNameLowerSet.add(name.toLowerCase());
                        orderedCategoryNames.add(name);
                      }
                    }
                  }
//---------------------------------------
// sort category name
//---------------------------------------
                  orderedCategoryNames.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
//---------------------------------------
// get all facilities from database
//---------------------------------------
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

                      final List<Map<String, dynamic>> all = <Map<String, dynamic>>[];
                      final Set<String> activeFacilityIds = <String>{};
                      final String q = _searchCtrl.text.trim().toLowerCase();

                      for (final d in facDocs) {
                        final Map<String, dynamic> data = d.data();
//---------------------------------------
// ignore deleted facility
//---------------------------------------
                        bool deleted = false;
                        if (data.containsKey('deleted')) {
                          if (data['deleted'] is bool) {
                            if (data['deleted'] == true) deleted = true;
                          }
                        }
                        if (deleted == true) continue;

                        final String id = d.id;
                        activeFacilityIds.add(id);

                        String name;
                        if (data.containsKey('name') && data['name'] is String) {
                          name = data['name'];
                        } else {
                          name = '(Unnamed Facility)';
                        }

                        String? categoryName;
//---------------------------------------
// get the category name for that facility is
//---------------------------------------
                        if (data.containsKey('categoryId') && data['categoryId'] is String) {
                          final String cid = data['categoryId'];
                          if (catIdToName.containsKey(cid)) {
                            categoryName = catIdToName[cid];
                          }
                        }
                        if (categoryName == null) {
                          if (data.containsKey('categoryName') && data['categoryName'] is String) {
                            final String low = (data['categoryName'] as String).toLowerCase();
                            if (catNameLowerSet.contains(low)) {
                              for (final String cname in orderedCategoryNames) {
                                if (cname.toLowerCase() == low) {
                                  categoryName = cname;
                                  break;
                                }
                              }
                            }
                          }
                        }

                        if (_selectedCategory != null) {
                          final String sel = _selectedCategory!.toLowerCase();
                          String cat;
                          if (categoryName == null) {
                            cat = '';
                          } else {
                            cat = categoryName.toLowerCase();
                          }
                          if (sel != cat) continue;
                        }
//---------------------------------------
// if teh search is not empty but also does not have the seach key word
//---------------------------------------
                        if (q.isNotEmpty == true) {
                          if (name.toLowerCase().contains(q) == false)
                            continue;
                        }
//---------------------------------------
// get the image
//---------------------------------------
                        String imagePath = '';
                        if (data.containsKey('imagePath') && data['imagePath'] is String) {
                          imagePath = data['imagePath'];
                        } else {
                          if (data.containsKey('imageName') && data['imageName'] is String) {
                            final String nv = (data['imageName'] as String).trim();
                            if (nv.isNotEmpty == true) {
                              imagePath = 'asset/image/$nv';
                            }
                          }
                        }

//---------------------------------------
// check the active is true or false
//---------------------------------------
                        bool active;
                        if (data.containsKey('active') && data['active'] is bool) {
                          active = data['active'];
                        } else {
                          active = false;
                        }
//---------------------------------------
// get capacity of that facility
//---------------------------------------
                        int reqCap = 1;
                        int maxCap = 0;

                        if (data.containsKey('requiredCapacity')) {
                          reqCap = _parseCapInt(data['requiredCapacity'], 1);
                        }

                          if (data.containsKey('maxCapacity')) {
                            maxCap = _parseCapInt(data['maxCapacity'], 0);
                          }

                        if (q.isEmpty == true && _selectedCategory == null) {
                          if (categoryName == null) continue;
                        }

//---------------------------------------
// all this will add into all list
//---------------------------------------
                        final Map<String, dynamic> item = <String, dynamic>{
                          'id': id,
                          'name': name,
                          'categoryName': categoryName,
                          'imagePath': imagePath,
                          'active': active,
                          'reqCap': reqCap,
                          'maxCap': maxCap,
                        };
                        all.add(item);
                      }


                      return StreamBuilder<Set<String>>(
//---------------------------------------
// get the favourite id from user first
//---------------------------------------
                        stream: _watchFavoriteIds(),
                        builder: (context, favSnap) {
                          Set<String> favoriteIds;
                          if (favSnap.data == null) {
                            favoriteIds = <String>{};
                          } else {
                            favoriteIds = favSnap.data!;
                          }

                          final Set<String> staleFavIds = favoriteIds.difference(activeFacilityIds);
                          if (staleFavIds.isNotEmpty == true) {
//---------------------------------------
// remove the facility id that not exist
//---------------------------------------
                            WidgetsBinding.instance.addPostFrameCallback((_) async {
                              await _removeFavorites(staleFavIds);
                            });
                          }

                          final int userCap = _currentCapacity();

//---------------------------------------
// if there is category choosen sort by category and display
//---------------------------------------
                          if (_selectedCategory != null) {
                            _sortByCapacityRule(all, userCap);

                            if (all.isEmpty == true) {
                              return Center(
                                child: Text(
                                  'No facilities in "${_selectedCategory!}"',
                                  style: TextStyle(fontSize: 14.sp),
                                ),
                              );
                            }
//---------------------------------------
// display each of the facility
//---------------------------------------
                            return ListView.separated(
                              itemCount: all.length,
                              separatorBuilder: (_, __) => SizedBox(height: 8.h),
                              itemBuilder: (context, i) {
                                final Map<String, dynamic> item = all[i];
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
//---------------------------------------
// if there is search sort by search and display
//---------------------------------------
                          final String qNow = _searchCtrl.text.trim();
                          if (qNow.isNotEmpty == true) {
                            _sortByCapacityRule(all, userCap);

                            if (all.isEmpty == true) {
                              return const Center(child: Text('No facilities match your search'));
                            }

                            return ListView.separated(
                              itemCount: all.length,
                              separatorBuilder: (_, __) => SizedBox(height: 8.h),
                              itemBuilder: (context, i) {
                                final Map<String, dynamic> item = all[i];
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
//---------------------------------------
// if none of above condition meet, display favourite facility first
//---------------------------------------
                          final List<Map<String, dynamic>> favList = <Map<String, dynamic>>[];
                          final Map<String, List<Map<String, dynamic>>> byCat = <String, List<Map<String, dynamic>>>{};

                          for (final Map<String, dynamic> m in all) {
                            final String id = m['id'] as String;
                            String catName;
                            if (m['categoryName'] is String) {
                              catName = m['categoryName'];
                            } else {
                              catName = '';
                            }

                            if (favoriteIds.contains(id) == true) {
                              favList.add(m);
                            } else {
                              if (byCat.containsKey(catName) == true) {
                                byCat[catName]!.add(m);
                              } else {
                                byCat[catName] = <Map<String, dynamic>>[m];
                              }
                            }
                          }
//---------------------------------------
// sort by capacity for favourite list
//---------------------------------------
                          _sortByCapacityRule(favList, userCap);

                          final List<Map<String, dynamic>> others = <Map<String, dynamic>>[];
                          for (final MapEntry<String, List<Map<String, dynamic>>> entry in byCat.entries) {
                            final List<Map<String, dynamic>> listForCat = entry.value;
                            if (listForCat.isNotEmpty == true) {
                              for (final Map<String, dynamic> m in listForCat) {
                                others.add(m);
                              }
                            }
                          }
//---------------------------------------
// sort by capacity for all other facility
//---------------------------------------
                          _sortByCapacityRule(others, userCap);

                          final List<Widget> children = <Widget>[];
//---------------------------------------
// list all the favourite capacity
//---------------------------------------
                          children.add(_sectionHeader(title: 'Favorite', count: favList.length));
                          for (final Map<String, dynamic> item in favList) {
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
//---------------------------------------
// list all facility which isFav is false
//---------------------------------------
                          children.add(_sectionHeader(title: 'All Facilities', count: others.length));
                          for (final Map<String, dynamic> item in others) {
                            final bool isFav = favoriteIds.contains(item['id'] as String);
                            children.add(
                              _facilityCard(
                                sw: sw,
                                data: item,
                                isFavorite: isFav,
                                onToggleFavorite: () async {
                                  await _toggleFavorite(item['id'] as String);
                                },
                                onTap: () {
//---------------------------------------
// ontap will bring item id and name to next page
//---------------------------------------
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

//---------------------------------------
// bottom navigation
//---------------------------------------

      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }

//---------------------------------------
// build capacity field
//---------------------------------------
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
//---------------------------------------
// minus button
//---------------------------------------
          InkWell(
            onTap: () {
              int v = _currentCapacity();
              v = v - 1;
              if (v < 1) {
                v = 1;
              }
              _capCtrl.text = v.toString();
              _capCtrl.selection = TextSelection.fromPosition(
                TextPosition(offset: _capCtrl.text.length),
              );
            },
            borderRadius: BorderRadius.circular(8.r),
            child: SizedBox(
              width: 26.w,
              height: 26.h,
              child: Icon(Icons.remove, size: 18.sp),
            ),
          ),

          SizedBox(width: 2.w),

//---------------------------------------
// allow to place number field
//---------------------------------------
          Expanded(
            child: TextField(
              controller: _capCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3), // cap to 3 digits
              ],
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.sp, height: 1.1),
              decoration: const InputDecoration(
                hintText: '1',
                border: InputBorder.none,
                isCollapsed: true,
                counterText: '',        // hide max-length counter
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),

          SizedBox(width: 2.w),
//---------------------------------------
// plus button
//---------------------------------------
          InkWell(
            onTap: () {
              int v = _currentCapacity();
              v = v + 1;
              _capCtrl.text = v.toString();
              _capCtrl.selection = TextSelection.fromPosition(
                TextPosition(offset: _capCtrl.text.length),
              );
            },
            borderRadius: BorderRadius.circular(8.r),
            child: SizedBox(
              width: 26.w,
              height: 26.h,
              child: Icon(Icons.add, size: 18.sp),
            ),
          ),
        ],
      ),
    );
  }


//---------------------------------------
// build search field
//---------------------------------------
  Widget _buildSearchField() {
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
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.grey),
          SizedBox(width: 8.w),
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
//---------------------------------------
// clear button
//---------------------------------------
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

//---------------------------------------
// build filter category navigate button
//---------------------------------------
  Widget _buildFilterButton() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12.r),
      elevation: 2,
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: () async {
          final picked = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FilterCategory()),
          );
//---------------------------------------
// get the picked category
//---------------------------------------
          if (picked is String) {
            if (picked.trim().isEmpty == true) {
              setState(() {
                _selectedCategory = null;
              });
            } else {
              setState(() {
                _selectedCategory = picked;
              });
            }
          } else {
            setState(() {
              _selectedCategory = null;
            });
          }
        },
        child: Center(child: Icon(Icons.filter_list, color: Colors.grey.shade800)),
      ),
    );
  }

  // build small section header text
  Widget _sectionHeader({required String title, required int count}) {
    return Padding(
      padding: EdgeInsets.only(left: 6.w, bottom: 8.h, top: 8.h),
      child: Text(
        '$title - $count',
        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
      ),
    );
  }

//---------------------------------------
// each of the facility display
//---------------------------------------
  Widget _facilityCard({
    required double sw,
    required Map<String, dynamic> data,
    required bool isFavorite,
    required Future<void> Function() onToggleFavorite,
    required VoidCallback onTap,
  }) {
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
      maxCap = 0;
    }

    IconData starIcon;
    if (isFavorite == true) {
      starIcon = Icons.star;
    } else {
      starIcon = Icons.star_border;
    }

    Color starColor;
    if (isFavorite == true) {
      starColor = Colors.amber;
    } else {
      starColor = Colors.black45;
    }

    String availText;
    Color availColor;
    if (active == true) {
      availText = 'Available';
      availColor = Colors.green;
    } else {
      availText = 'Not Available';
      availColor = Colors.red;
    }
//---------------------------------------
// the design here
//---------------------------------------
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8.r),
                    child: _buildFacilityImage(imagePath),
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 10.h),
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
                                  Icon(active ? Icons.check_circle : Icons.cancel, size: 16.sp, color: availColor),
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
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12.r),
                                border: Border.all(color: Colors.grey.shade400),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person, size: 16.sp, color: Colors.black87),
                                  SizedBox(width: 6.w),
                                  Text(
                                    _formatCapacityText(reqCap, maxCap),
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

//---------------------------------------
//facility image
//---------------------------------------
  Widget _buildFacilityImage(String imagePath) {
    if (imagePath.isEmpty == true) {
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
