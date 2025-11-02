import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'web_top_bar.dart';

class LecturerList extends StatefulWidget {
  const LecturerList({Key? key}) : super(key: key);

  @override
  State<LecturerList> createState() => _LecturerListState();
}

class _LecturerListState extends State<LecturerList> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final bool _use24HourFormat = true;

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _rejectCtrl = TextEditingController();
  String _searchKeyword = '';
//---------------------------------------
// get the user information in database
//---------------------------------------

  CollectionReference<Map<String, dynamic>> _usersCol() =>
      _firestore.collection('UserInformation');

//---------------------------------------
// show still pending
//---------------------------------------
  Widget _pendingDot() {
    return Container(
      width: 10.w,
      height: 10.w,
      decoration: const BoxDecoration(
        color: Color(0xFFFF0707),
        shape: BoxShape.circle,
      ),
    );
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
    final double contentMaxWidth = 0.7.sw;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: WebCustomTopBar(use24HourFormat: _use24HourFormat),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: 16.h),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: _buildMainCard(),
            ),
          ),
        ),
      ),
    );
  }

//---------------------------------------
// build the main outer box
//---------------------------------------

  Widget _buildMainCard() {
    return Card(
      color: const Color(0xFFEDDFFF),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: Padding(
        padding: EdgeInsets.all(12.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
//---------------------------------------
// show searchbar
//---------------------------------------
            Row(
              children: [
                Expanded(child: _buildSearchField()),
                SizedBox(width: 8.w),
                SizedBox(
                  height: 40.h,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() {
                        _searchKeyword = _searchCtrl.text.trim().toLowerCase();
                      });
                    },
                    icon: Icon(Icons.search, size: 18.sp),
                    label: Text('Search', style: TextStyle(fontSize: 14.sp)),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),

//---------------------------------------
// part where display each lecturer
//---------------------------------------

            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _usersCol()
                  .where('role', isEqualTo: 'Lecturer')
                  .where('deleted', isEqualTo: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Center(
                      child: SizedBox(
                        width: 24.w,
                        height: 24.w,
                        child: const CircularProgressIndicator(),
                      ),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Text(
                      'Failed to load lecturers. Please try again.',
                      style: TextStyle(fontSize: 14.sp, color: Colors.red),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];

//---------------------------------------
// prepare all the lecturer data first
//---------------------------------------

                final items = <Map<String, dynamic>>[];
                for (final d in docs) {
                  final raw = d.data();
                  final m = <String, dynamic>{};

                  m['id'] = d.id; // document id (User ID)
//---------------------------------------
// lower case for search purpose
//---------------------------------------
                  String email = '';
                  if (raw.containsKey('email') && raw['email'] != null) {
                    email = raw['email'].toString();
                  }
                  m['email'] = email;
                  m['emailLower'] = email.toLowerCase();

                  String username = '';
                  if (raw.containsKey('username') && raw['username'] != null) {
                    username = raw['username'].toString();
                  }
                  m['username'] = username;
                  m['usernameLower'] = username.toLowerCase();

                  String contact = '';
                  if (raw.containsKey('contact') && raw['contact'] != null) {
                    contact = raw['contact'].toString();
                  }
                  m['contact'] = contact;

                  String role = '';
                  if (raw.containsKey('role') && raw['role'] != null) {
                    role = raw['role'].toString();
                  }
                  m['role'] = role;

                  String proofB64 = '';
                  if (raw.containsKey('proofImageBase64') &&
                      raw['proofImageBase64'] != null) {
                    proofB64 = raw['proofImageBase64'].toString();
                  }
                  m['proofImageBase64'] = proofB64;

                  bool approval = false;
                  if (raw.containsKey('approval') && raw['approval'] is bool) {
                    approval = raw['approval'] as bool;
                  }
                  m['approval'] = approval;

                  bool active = false;
                  if (raw.containsKey('active') && raw['active'] is bool) {
                    active = raw['active'] as bool;
                  }
                  m['active'] = active;

                  // capture createdAt for client-side sort
                  int createdAtMs = 0;
                  if (raw.containsKey('createdAt') && raw['createdAt'] != null) {
                    final v = raw['createdAt'];
                    if (v is Timestamp) {
                      createdAtMs = v.millisecondsSinceEpoch;
                    } else if (v is String) {
                      createdAtMs = DateTime.tryParse(v)?.millisecondsSinceEpoch ?? 0;
                    }
                  }
                  m['createdAtMs'] = createdAtMs;

                  items.add(m);
                }

//---------------------------------------
// sort by created date
//---------------------------------------

                items.sort((a, b) =>
                    (b['createdAtMs'] as int).compareTo(a['createdAtMs'] as int));
//---------------------------------------
// filter the name by keyword
//---------------------------------------

                final k = _searchKeyword;
                final filtered = k.isEmpty
                    ? items
                    : items.where((user) {
                  final u = (user['usernameLower'] ?? '') as String;
                  final e = (user['emailLower'] ?? '') as String;
                  return u.contains(k) || e.contains(k);
                }).toList();

                if (filtered.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Text('No lecturers found.',
                        style: TextStyle(fontSize: 14.sp)),
                  );
                }

                return Column(
                  children: [
                    Divider(height: 1.h, thickness: 1),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) => SizedBox(height: 8.h),
                      itemBuilder: (context, index) {
                        final it = filtered[index];
                        final email = (it['email'] ?? '') as String;
                        final username = (it['username'] ?? '') as String;
                        final approval = it['approval'] == true;

                        return Container(
                          padding: EdgeInsets.symmetric(vertical: 10.h),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                  color: Colors.grey.shade300, width: 1),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
//---------------------------------------
// display email and username
//---------------------------------------

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      email,
                                      style: TextStyle(
                                          fontSize: 14.sp,
                                          fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    SizedBox(height: 4.h),
                                    Text(
                                      username.isEmpty
                                          ? '(No username)'
                                          : username,
                                      style: TextStyle(
                                          fontSize: 13.sp,
                                          color: Colors.black87),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 12.w),

//---------------------------------------
// view pop up for lecturer information
//---------------------------------------
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  SizedBox(
                                    height: 36.h,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _openViewDialog(it),
                                      icon: Icon(Icons.visibility, size: 16.sp),
                                      label: Text('View',
                                          style: TextStyle(fontSize: 13.sp)),
                                    ),
                                  ),
//---------------------------------------
// if not yet approve
//---------------------------------------
                                  if (!approval)
                                    Positioned(
                                      right: -3.w,
                                      top: -3.h,
                                      child: _pendingDot(),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
//---------------------------------------
// search field design
//---------------------------------------
  Widget _buildSearchField() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (value) {
        setState(() {
          _searchKeyword = value.trim().toLowerCase();
        });
      },
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
        EdgeInsets.symmetric(vertical: 12.h, horizontal: 12.w),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
        labelText: 'Search username / email',
        labelStyle: TextStyle(fontSize: 14.sp),
        prefixIcon: Icon(Icons.search, size: 20.sp),
      ),
      style: TextStyle(fontSize: 14.sp),
    );
  }

//---------------------------------------
// pop up design
//---------------------------------------

  Future<void> _openViewDialog(Map<String, dynamic> user) async {
    final String docId = user['id'] ?? '';

    final String email = user['email'] ?? '';
    final String username = user['username'] ?? '';
    final String contact = user['contact'] ?? '';
    final String role = user['role'] ?? '';
    final String proofB64 = user['proofImageBase64'] ?? '';
    final bool approval = user['approval'] == true;
    final bool active = user['active'] == true;

 //---------------------------------------
// decode the image first
//---------------------------------------

    Uint8List? proofImage;
    if (proofB64.isNotEmpty) {
      try {
        proofImage = base64Decode(proofB64);
      } catch (_) {
        proofImage = null;
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
          title: Text('Lecturer Details',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 600.w,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _kv('Email', email),
                  SizedBox(height: 8.h),
                  _kv('Username', username),
                  SizedBox(height: 8.h),
                  _kv('Contact', contact),
                  SizedBox(height: 8.h),
                  _kv('Role', role),
                  SizedBox(height: 8.h),
                  _kv('User ID', docId), // document id
                  SizedBox(height: 12.h),

//---------------------------------------
// show proof image
//---------------------------------------

                  Text('Proof', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                SizedBox(height: 6.h),

                SizedBox(
                  width: 360.w,
                  height: 310.h,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6.r),
                    child: ColoredBox(
                      color: Colors.grey.shade200,
                      child: proofImage != null
                          ? InkWell(
                        onTap: () => _openImageViewer(proofImage!),
                        child: Image.memory(
                          proofImage!,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                        ),
                      )
                          : Center(
                        child: Text(
                          '(No proof image)',
                          style: TextStyle(fontSize: 13.sp, color: Colors.black54),

                    ),
                  ),
                    ),
                  ),
                ),
                ],
              ),
            ),
          ),
//---------------------------------------
// if not approve show button approval
//---------------------------------------
          actions: _buildDialogActions(
            approval: approval,
            active: active,
            docId: docId,
          ),
        );
      },
    );
  }
//---------------------------------------
// seperate them in the view pop up like name:   lecturer name, use width to seperate them
//---------------------------------------
  Widget _kv(String key, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130.w,
          child: Text('$key :',
              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: Text(value.isEmpty ? '-' : value,
              style: TextStyle(fontSize: 14.sp)),
        ),
      ],
    );
  }

  //---------------------------------------
// the button design and action
//---------------------------------------


  List<Widget> _buildDialogActions({
    required bool approval,
    required bool active,
    required String docId,
  }) {
    final left = [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text('Close', style: TextStyle(fontSize: 14.sp)),
      ),
    ];

    final right = <Widget>[];

//---------------------------------------
// when still not approve will show reject and approve
//---------------------------------------

    if (!approval) {
      right.add(
        TextButton(
          onPressed: () async {
            final bool? ok = await _confirmReject();
            if (ok == true) {
              await _rejectLecturer(docId);
              if (mounted) Navigator.of(context).pop();
            }
          },
          style:
          ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF0707)),
          child: Text('Reject', style: TextStyle(fontSize: 14.sp, color: Colors.white) ),
        ),

      );
      right.add(
        SizedBox(width:5.w)
      );
//---------------------------------------
// when approve is press
//---------------------------------------
      right.add(
        ElevatedButton(
          onPressed: () async {
            await _approveLecturer(docId);
            if (mounted) Navigator.of(context).pop();
          },
          child: Text('Approve', style: TextStyle(fontSize: 14.sp, color: Colors.black)),
        ),
      );
//---------------------------------------
// when approve or reject can choose delete
//---------------------------------------
    } else {
      right.add(
        ElevatedButton(
          onPressed: () async {
            final bool? ok = await _confirmDelete();
            if (ok == true) {
              await _softDeleteLecturer(docId);
              if (mounted) Navigator.of(context).pop();
            }
          },
          style:
          ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF0707)),
          child: Text('Delete',
              style: TextStyle(fontSize: 14.sp, color: Colors.white)),
        ),
      );
    }
//---------------------------------------
// return the design
//---------------------------------------
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: left),
          Row(children: right),
        ],
      ),
    ];
  }
//---------------------------------------
// show the big image when tap
//---------------------------------------

  Future<void> _openImageViewer(Uint8List bytes) async {
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.black,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
            ),
          ),
        );
      },
    );
  }
//---------------------------------------
// approve proccess
//---------------------------------------
  Future<void> _approveLecturer(String docId) async {
    try {
      await _usersCol().doc(docId).update(<String, dynamic>{
        'active': true,
        'approval': true,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Approved.', style: TextStyle(fontSize: 13.sp))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
            Text('Failed to approve.', style: TextStyle(fontSize: 13.sp))),
      );
    }
  }
//---------------------------------------
// reject proccess
//---------------------------------------
  Future<void> _rejectLecturer(String docId) async {
    final String reason = _rejectCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Please enter your reason', style: TextStyle(fontSize: 13.sp))));
      return;
    }

    try {
      await _usersCol().doc(docId).set(<String, dynamic>{
        'approval': true,
        'rejectDetails': reason,
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rejected.', style: TextStyle(fontSize: 13.sp))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
            Text('Failed to reject.', style: TextStyle(fontSize: 13.sp))),
      );
    }
  }
//---------------------------------------
// soft delete proccess
//---------------------------------------
  Future<void> _softDeleteLecturer(String docId) async {
    try {
      await _usersCol().doc(docId).update(<String, dynamic>{
        'deleted': true,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted.', style: TextStyle(fontSize: 13.sp))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
            Text('Failed to delete.', style: TextStyle(fontSize: 13.sp))),
      );
    }
  }
//---------------------------------------
// delete pop up confirmation
//---------------------------------------
  Future<bool?> _confirmDelete() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(0)),
          ),
          title: Text('Delete Lecturer?',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),
          content: Text(
            'Are you sure you want to delete this lecturer? This cannot be undone.',
            style: TextStyle(fontSize: 14.sp),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF0707)),
              child: Text('Delete',
                  style: TextStyle(fontSize: 14.sp, color: Colors.white)),
            ),
          ],
        );
      },
    );
  }
//---------------------------------------
// reject pop up
//---------------------------------------
  Future<bool?> _confirmReject() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          title: Text('Rejection Details',
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold)),

          content: Container(
            width:400.w,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10.r),
            ),
          child:TextField(
            controller: _rejectCtrl,
            keyboardType: TextInputType.text,
              style: TextStyle(fontSize: 14.sp),
              maxLines: 5,
              decoration: InputDecoration(
                hintText: 'Enter details',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12.w, vertical: 10.h,
                ),
                border: OutlineInputBorder(),
          ),
          ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF0707)),
              child: Text('Confirm',
                  style: TextStyle(fontSize: 14.sp, color: Colors.white)),
            ),

          ],
        );
      },
    );
  }


}
