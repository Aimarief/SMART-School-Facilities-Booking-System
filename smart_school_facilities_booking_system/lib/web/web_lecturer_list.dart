// lib/web/web_lecturer_list.dart
// -----------------------------------------------------------------------------
// WEB LECTURER LIST (no suggestions dropdown)
// - Top bar + single centered card layout.
// - Search by username OR email (filters the list below).
// - Lists lecturers from UserInformation where role=Lecturer AND deleted=false,
//   newest first (client-side sort by createdAt desc).
// - Row: Email (top), Username (below), View button (+ red dot if approval=false).
// - View dialog shows: Email, Username, Contact, Role, User ID (doc id), Proof.
//   * Proof image clickable → fullscreen viewer.
//   * approval=false → Approve (active=true, approval=true) / Reject (approval=true)
//   * approval=true  → Delete (deleted=true)
// -----------------------------------------------------------------------------

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
  String _searchKeyword = '';

  CollectionReference<Map<String, dynamic>> _usersCol() =>
      _firestore.collection('UserInformation');

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
            // Header row: search field + search button
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

            // List area
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _usersCol()
                  .where('role', isEqualTo: 'Lecturer')
                  .where('deleted', isEqualTo: false)
              // no orderBy here to avoid composite index requirements;
              // we'll sort on the client below.
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

                // Normalize fields
                final items = <Map<String, dynamic>>[];
                for (final d in docs) {
                  final raw = d.data();
                  final m = <String, dynamic>{};

                  m['id'] = d.id; // document id (User ID)

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

                // Sort newest first (client-side)
                items.sort((a, b) =>
                    (b['createdAtMs'] as int).compareTo(a['createdAtMs'] as int));

                // Filter by username OR email keyword (client-side)
                final k = _searchKeyword;
                final filtered = k.isEmpty
                    ? items
                    : items.where((it) {
                  final u = (it['usernameLower'] ?? '') as String;
                  final e = (it['emailLower'] ?? '') as String;
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
                      separatorBuilder: (_, __) => SizedBox(height: 8.h),
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
                              // Left: email + username
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

                              // Right: View (with red dot if approval=false)
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

  // ------------------------------ VIEW DIALOG -------------------------------
  Future<void> _openViewDialog(Map<String, dynamic> it) async {
    final String docId = it['id'] ?? '';

    final String email = it['email'] ?? '';
    final String username = it['username'] ?? '';
    final String contact = it['contact'] ?? '';
    final String role = it['role'] ?? '';
    final String proofB64 = it['proofImageBase64'] ?? '';
    final bool approval = it['approval'] == true;
    final bool active = it['active'] == true;

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

                // --- Proof (fixed-size preview with BoxFit) ---
                Text('Proof', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                SizedBox(height: 6.h),

// Fixed preview size — adjust once here and it won’t jump around.
                SizedBox(
                  width: 360.w,      // <- set your fixed width
                  height: 310.h,     // <- set your fixed height
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
                          fit: BoxFit.contain, // <- change to BoxFit.cover if you prefer fill/crop
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
          actions: _buildDialogActions(
            approval: approval,
            active: active,
            docId: docId,
          ),
        );
      },
    );
  }

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

    if (!approval) {
      right.add(
        TextButton(
          onPressed: () async {
            await _rejectLecturer(docId);
            if (mounted) Navigator.of(context).pop();
          },
          child: Text('Reject', style: TextStyle(fontSize: 14.sp)),
        ),
      );
      right.add(
        ElevatedButton(
          onPressed: () async {
            await _approveLecturer(docId);
            if (mounted) Navigator.of(context).pop();
          },
          child: Text('Approve', style: TextStyle(fontSize: 14.sp)),
        ),
      );
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

  Future<void> _rejectLecturer(String docId) async {
    try {
      await _usersCol().doc(docId).update(<String, dynamic>{
        'approval': true, // mark reviewed; active remains as-is
      });
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
}
