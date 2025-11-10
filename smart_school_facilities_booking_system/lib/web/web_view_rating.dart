import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'web_top_bar.dart';

class WebViewRating extends StatefulWidget {
  const WebViewRating({Key? key}) : super(key: key);

  @override
  State<WebViewRating> createState() => _WebViewRatingState();
}

class _WebViewRatingState extends State<WebViewRating> {

  final bool _use24HourFormat = true;

  final TextEditingController _searchCtrl = TextEditingController();

  String? _selectedFacilityId;
  String _selectedFacilityName = '';

  // ---------- helpers ----------
  String _clean(String s) {
    return s.trim();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

//---------------------------------------
// main build
//---------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: WebCustomTopBar(use24HourFormat: _use24HourFormat),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Padding(
                padding: EdgeInsets.all(16.w),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 1684.w,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
//---------------------------------------
// show left box
//---------------------------------------
                          _Box(
                            width: 460.w,
                            height: 965.h,
                            title: 'Facilities',
                            header: _SearchHeader(
                              controller: _searchCtrl,
                              hint: 'Search facility',
                              onChanged: (t) {
                                setState(() {}); // refresh filter
                              },
                            ),
                            child: _buildFacilitiesList(),
                          ),
                          SizedBox(width: 24.w),
//---------------------------------------
// show right box
//---------------------------------------
                          _Box(
                            width: 1200.w,
                            height: 965.h,
                            title: 'Rating & Reviews',
                            child: Padding(
                              padding: EdgeInsets.only(right: 8.w, bottom: 8.h),
                              child: _buildRightPanel(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

//---------------------------------------
// build left list design
//---------------------------------------
  Widget _buildFacilitiesList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('Facilities')
          .orderBy('name')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs = snapshot.data!.docs;
//---------------------------------------
// get what is search  and compare
//---------------------------------------
        final String q = _clean(_searchCtrl.text).toLowerCase();
        final List<QueryDocumentSnapshot<Map<String, dynamic>>> filtered =
        <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        int i = 0;
        while (i < docs.length) {
          final d = docs[i];
          final m = d.data();
//---------------------------------------
// filter deleted = true
//---------------------------------------
          bool del;
            if (m['deleted'] == true) {
              del = true;
            } else {
              del = false;
            }
          String nm;
          if (m.containsKey('name') && m['name'] != null) {
            nm = m['name'].toString();
          } else {
            nm = '';
          }
//---------------------------------------
// if search bar is empty, pick all, if not empty get name that contain the key word
//---------------------------------------
          bool matches;
          if (q.isEmpty) {
            matches = true;
          } else {
            final String cmp = nm.toLowerCase();
            if (cmp.contains(q)) {
              matches = true;
            } else {
              matches = false;
            }
          }

          if (!del) {
            if (matches) {
              filtered.add(d);
            }
          }

          i = i + 1;
        }

        if (filtered.isEmpty) {
          return const _EmptyCenter(text: 'No facilities found');
        }

        return ListView.separated(
          itemCount: filtered.length,
          physics: const AlwaysScrollableScrollPhysics(),
          separatorBuilder: (_, __) => SizedBox(height: 8.h),
          itemBuilder: (context, index) {
            final d = filtered[index];
            final m = d.data();

            String nm;
            if (m.containsKey('name') && m['name'] != null) {
              nm = m['name'].toString();
            } else {
              nm = '';
            }
//---------------------------------------
// facility on tap set id and name
//---------------------------------------
            return _ListTileCard(
              label: nm,
              onTap: () {
                setState(() {
                  _selectedFacilityId = d.id;
                  _selectedFacilityName = nm;
                });
              },
            );
          },
        );
      },
    );
  }

//---------------------------------------
// build right panel design
//---------------------------------------
  Widget _buildRightPanel() {
    if (_selectedFacilityId == null) {
      return SizedBox(
        height: 820.h,
        child: Center(
          child: Text(
            'Please select a facility',
            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }
//---------------------------------------
// get the rating from the facility id
//---------------------------------------

    final String fid = _selectedFacilityId!;
    final Stream<QuerySnapshot<Map<String, dynamic>>> ratingStream = FirebaseFirestore.instance
        .collection('Facilities')
        .doc(fid)
        .collection('Rating')
        .snapshots();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
//---------------------------------------
// display facility name
//---------------------------------------
          Text(
            _selectedFacilityName,
            style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 10.h),

          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: ratingStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Center(
                  child: SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator()),
                );
              }

              int count = 0;
              double total = 0.0;
//---------------------------------------
// count the total of rating for all doc
//---------------------------------------
              if (snap.hasData) {
                final rd = snap.data!.docs;
                count = rd.length;
                int k = 0;
                while (k < rd.length) {
                  final mm = rd[k].data();
                  if (mm.containsKey('rating')) {
                    final v = mm['rating'];
                    if (v is int) {
                      total = total + v.toDouble();
                    }
                  }
                  k = k + 1;
                }
              }
//---------------------------------------
// count the average rating
//---------------------------------------
              double avg;
              if (count > 0) {
                avg = total / count;
              } else {
                avg = 0.0;
              }
              final String avgText = avg.toStringAsFixed(1);

              String countLabel;
//---------------------------------------
// how many person rated
//---------------------------------------
                countLabel = '$count ratings';

              return Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 12.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('Review', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 4.h),
                    Text('Overall rating', style: TextStyle(fontSize: 13.sp, color: Colors.black54)),
                    SizedBox(height: 8.h),
                    Text(avgText, style: TextStyle(fontSize: 28.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 6.h),
                    _buildStars(avg, centered: true),
                    SizedBox(height: 6.h),
                    Text(
                      countLabel,
                      style: TextStyle(fontSize: 12.5.sp, color: Colors.black87, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            },
          ),

          SizedBox(height: 14.h),

//---------------------------------------
// show review list
//---------------------------------------
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: ratingStream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Center(
                  child: SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator()),
                );
              }

              final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
              (snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[]).toList();
 //---------------------------------------
// sort by date
//---------------------------------------
              docs.sort((a, b) {
                final ma = a.data();
                final mb = b.data();
                int ta;
                if (ma.containsKey('createdAt') && ma['createdAt'] is Timestamp) {
                  ta = (ma['createdAt'] as Timestamp).millisecondsSinceEpoch;
                } else {
                  ta = 0;
                }
                int tb;
                if (mb.containsKey('createdAt') && mb['createdAt'] is Timestamp) {
                  tb = (mb['createdAt'] as Timestamp).millisecondsSinceEpoch;
                } else {
                  tb = 0;
                }
                return tb.compareTo(ta);
              });
//---------------------------------------
// if empty means no review yet
//---------------------------------------
              if (docs.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: 20.h),
                  alignment: Alignment.center,
                  child: Text('No reviews yet', style: TextStyle(fontSize: 14.sp, color: Colors.black54)),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (context, index) => SizedBox(height: 10.h),
                itemBuilder: (context, i) {
                  final m = docs[i].data();

                  String userId;
                  if (m.containsKey('userId') && m['userId'] is String) {
                    userId = m['userId'];
                  } else {
                    userId = '';
                  }
                  String review;
                  if (m.containsKey('review') && m['review'] is String) {
                    review = m['review'];
                  } else {
                    review = '';
                  }
                  double rating = 0.0;
                  if (m.containsKey('rating')) {
                    final v = m['rating'];
                    if (v is int) {
                      rating = v.toDouble();
                    } else {
                      if (v is double) {
                        rating = v;
                      }
                    }
                  }
                  if (rating < 0) {
                    rating = 0;
                  } else {
                    if (rating > 5) {
                      rating = 5;
                    }
                  }

                  DateTime? createdAt;
                  if (m.containsKey('createdAt')) {
                    final ca = m['createdAt'];
                    if (ca is Timestamp) {
                      createdAt = ca.toDate().toLocal();
                    } else {
                      if (ca is int) {
                        createdAt = DateTime.fromMillisecondsSinceEpoch(ca).toLocal();
                      } else {
                        if (ca is String) {
                          try {
                            createdAt = DateTime.parse(ca).toLocal();
                          } catch (_) {}
                        }
                      }
                    }
                  }

                  return _reviewTile(
                    userId: userId,
                    rating: rating,
                    review: review,
                    createdAt: createdAt,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

//---------------------------------------
// display each review for each person
//---------------------------------------

  Widget _reviewTile({
    required String userId,
    required double rating,
    required String review,
    DateTime? createdAt,
  }) {
    String dateText = '-';
    if (createdAt != null) {
      dateText = _fmtDate(createdAt);
    }

    Stream<DocumentSnapshot<Map<String, dynamic>>>? userStream;
    if (userId.isNotEmpty) {
      userStream = FirebaseFirestore.instance
          .collection('UserInformation')
          .doc(userId)
          .snapshots();
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userStream,
        builder: (context, snap) {
          String displayName = 'Anonymous';
          if (userStream == null) {
            displayName = 'Anonymous';
          } else {
            if (snap.connectionState == ConnectionState.waiting) {
              displayName = 'Anonymous';
            } else {
              if (snap.hasData && snap.data != null && snap.data!.exists) {
                final um = snap.data!.data();
                if (um != null) {
                  if (um.containsKey('username')) {
                    if (um['username'] != null) {
                      final String v = um['username'].toString();
                      if (v.isNotEmpty) {
                        displayName = v;
                      }
                    }
                  }
                }
              }
            }
          }
//---------------------------------------
// design for displaying each review and person
//---------------------------------------
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  //---------------------------------------
// design image
//---------------------------------------
                  ClipRRect(
                    borderRadius: BorderRadius.circular(40.r),
                    child: _userAvatar(userId),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    //---------------------------------------
// display name and rating
//---------------------------------------
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4.h),
                        _buildStars(rating),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              //---------------------------------------
// design for review and date
//---------------------------------------
              Text(
                review,
                style: TextStyle(fontSize: 13.sp, color: Colors.black87),
                softWrap: true,
              ),
              SizedBox(height: 6.h),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  dateText,
                  style: TextStyle(fontSize: 12.sp, color: Colors.black54),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  //---------------------------------------
// get teh user image and display
//---------------------------------------

  Widget _userAvatar(String userId) {
    if (userId.isEmpty) {
      return _placeholderAvatar();
    }

    final userDocStream = FirebaseFirestore.instance
        .collection('UserInformation')
        .doc(userId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userDocStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting || !snap.hasData || !snap.data!.exists) {
          return _placeholderAvatar();
        }

        final Map<String, dynamic> m = snap.data!.data() ?? <String, dynamic>{};

//---------------------------------------
// decode the base64 iamge
//---------------------------------------

        if (m.containsKey('profileImageBase64')) {
          if (m['profileImageBase64'] is String) {
            final String b64 = m['profileImageBase64'];
            if (b64.isNotEmpty) {
              try {
                final Uint8List bytes = base64Decode(b64);
                return Image.memory(bytes, width: 48.w, height: 48.w, fit: BoxFit.cover);
              } catch (_) {}
            }
          }
        }

        if (m.containsKey('profileImageName')) {
          if (m['profileImageName'] is String) {
            final String name = (m['profileImageName'] as String).trim();
            if (name.isNotEmpty) {
              return Image.asset('asset/image/$name', width: 48.w, height: 48.w, fit: BoxFit.cover);
            }
          }
        }

        return _placeholderAvatar();
      },
    );
  }
//---------------------------------------
// the width of the image display if no image
//---------------------------------------

  Widget _placeholderAvatar() {
    return Container(
      width: 48.w,
      height: 48.w,
      color: Colors.grey.shade400,
      alignment: Alignment.center,
      child: const Icon(Icons.person, color: Colors.white),
    );
  }
}

//---------------------------------------
// box to design the both left and right box
//---------------------------------------
class _Box extends StatelessWidget {
  const _Box({
    Key? key,
    required this.width,
    required this.height,
    required this.title,
    required this.child,
    this.header,
  }) : super(key: key);

  final double width;
  final double height;
  final String title;
  final Widget child;
  final Widget? header;

  static const Color _fill = Color(0xFFEDDFFF);    // light purple
  static const Color _outline = Color(0xFF8620E2); // purple border

  @override
  Widget build(BuildContext context) {
    final List<Widget> head = <Widget>[];
    if (header != null) {
      head.add(header!);
      head.add(SizedBox(height: 8.h));
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _fill,
        border: Border.all(color: _outline, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
          SizedBox(height: 8.h),
          ...head,
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Scrollbar(
                thumbVisibility: true,
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

//---------------------------------------
// search header design
//---------------------------------------

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    Key? key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  }) : super(key: key);

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
              ),
              contentPadding: EdgeInsets.symmetric(vertical: 12.h),
            ),
          ),
        ),
      ],
    );
  }
}

//---------------------------------------
// list each facility at left list
//---------------------------------------
class _ListTileCard extends StatelessWidget {
  const _ListTileCard({Key? key,
    required this.label,
    required this.onTap
  }) : super(key: key);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(.9),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCenter extends StatelessWidget {
  const _EmptyCenter({Key? key, required this.text}) : super(key: key);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: TextStyle(fontSize: 14.sp, color: Colors.black54)),
    );
  }
}

//---------------------------------------
// build the star base on average
//---------------------------------------

Widget _buildStars(double avg, {bool centered = false}) {
  final List<Widget> list = <Widget>[];

  for (int i = 1; i <= 5; i++) {
    IconData icon;
    if (avg >= i) {
      icon = Icons.star;
    } else {
//---------------------------------------
// if is less than 0.5 zero star, if more than 0.5 take half star
//---------------------------------------

      final double diff = i - avg;
      icon = (diff <= 0.5) ? Icons.star_half : Icons.star_border;
    }
    list.add(Icon(icon, size: 20.sp, color: const Color(0xFFFFC107)));
    if (i < 5) list.add(SizedBox(width: 2.w));
  }
//---------------------------------------
// display the star
//---------------------------------------
  final row = Row(mainAxisSize: MainAxisSize.min, children: list);
  return centered ? Align(alignment: Alignment.center, child: row) : row;
}

//---------------------------------------
// change the format to day month year
//---------------------------------------

String _fmtDate(DateTime d) {
  const List<String> months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  final String day = d.day.toString();
  final String mon = months[d.month - 1];
  final String yr  = d.year.toString();
  return '$day $mon $yr';
}
