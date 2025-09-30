import 'dart:convert';                         // base64Encode for image text
import 'dart:typed_data';                      // Uint8List for raw bytes
import 'package:flutter/material.dart';        // Flutter UI toolkit
import 'package:flutter/services.dart';        // Text input formatters
import 'package:flutter_screenutil/flutter_screenutil.dart'; // .w .h .sp scaling
import 'package:firebase_auth/firebase_auth.dart';            // current signed-in user
import 'package:cloud_firestore/cloud_firestore.dart';        // Firestore database

import 'package:file_picker/file_picker.dart'; // select files/images
import 'package:image/image.dart' as img;      // decode/resize/compress images

import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_list_of_facilities.dart';
import 'android_notifications.dart';
import 'android_account.dart';

import 'android_bottom_menu.dart';

class AndroidReportIssue extends StatefulWidget {
  const AndroidReportIssue({Key? key}) : super(key: key);

  @override
  State<AndroidReportIssue> createState() => _AndroidReportIssueState();
}

class _AndroidReportIssueState extends State<AndroidReportIssue> {

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  int _titleLen = 0;
  int _descLen = 0;

  String? _titleError;
  String? _descError;

  bool _submitting = false;

  String _displayUsername = "-";
  String _displayEmail = "-";

  Uint8List? _pendingImageBytes;
  String? _pendingBase64;

  static const int _maxBase64Len = 900000; // keep doc < ~1MB
  static const int _targetMaxWidth = 600; // resize large images

//---------------------------------------
// will run this first
//---------------------------------------
  @override
  void initState() {
    super.initState();
    _loadUserHeader(); // load username/email when page opens
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

//---------------------------------------
// load user first
//---------------------------------------
  Future<void> _loadUserHeader() async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        return;
      }

      String name = "";
      String mail = "";

      final doc = await FirebaseFirestore.instance
          .collection("UserInformation")
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          if (data["username"] != null) {
            final s = data["username"].toString().trim();
            if (s.isNotEmpty) {
              name = s;
            }
          }
          if (data["email"] != null) {
            final e = data["email"].toString().trim();
            if (e.isNotEmpty) {
              mail = e;
            }
          }
        }
      }

      if (mail.isEmpty && user.email != null && user.email!.isNotEmpty) {
        mail = user.email!.trim();
      }

      if (name.isEmpty) {
        name = "-";
      }
      if (mail.isEmpty) {
        mail = "-";
      }

//---------------------------------------
// set state to display username and email
//---------------------------------------

      setState(() {
        _displayUsername = name;
        _displayEmail = mail;
      });
    } catch (_) {}
  }

//---------------------------------------
// when back button press
//---------------------------------------


  // back arrow: go to Account page (replace current)
  void _handleBack() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => AndroidAccount()),
    );
  }

//---------------------------------------
// when close button press
//---------------------------------------

  void _handleCloseToAccount() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => AndroidAccount()),
          (route) => false,
    );
  }

//---------------------------------------
// navigation page
//---------------------------------------

  void _onTabSelected(int i) {
    if (i == 0) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => AndroidAgenda()));
    } else if (i == 1) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } else if (i == 2) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
    } else if (i == 3) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
    } else if (i == 4) {
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => AndroidAccount()));
    }
  }

//---------------------------------------
// when image pick
//---------------------------------------

  Future<void> _pickResizePreviewImage() async {
    try {
      final FilePickerResult? res = await FilePicker.platform.pickFiles(
        type: FileType.custom, // custom filter
        allowedExtensions: ['jpg', 'jpeg', 'png'], // only images
        allowMultiple: false, // single file
        withData: true, // we want bytes
      );

      if (res == null || res.files.isEmpty) {
        return;
      } // user cancelled

      final PlatformFile file = res.files.single;
      final Uint8List? raw = file.bytes;

      if (raw == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              "This image cannot be read. Please pick a different one.",
              style: TextStyle(fontSize: 12.sp))),
        );
        return;
      }

      final img.Image? decoded = img.decodeImage(raw);
      if (decoded == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              "Unsupported image", style: TextStyle(fontSize: 12.sp))),
        );
        return;
      }

      img.Image toEncode;
      if (decoded.width > _targetMaxWidth) {
        toEncode = img.copyResize(
          decoded,
          width: _targetMaxWidth,
          interpolation: img.Interpolation.average,
        );
      } else {
        toEncode = decoded;
      }

//---------------------------------------
// compress
//---------------------------------------
      int quality = 80;
      Uint8List? finalBytes;
      String? finalB64;
      bool ok = false;

      while (ok == false) {
        final Uint8List bytes = Uint8List.fromList(
          img.encodeJpg(toEncode, quality: quality),
        );
        final String b64 = base64Encode(bytes);

        if (b64.length <= _maxBase64Len) {
          finalBytes = bytes;
          finalB64 = b64;
          ok = true;
        } else {
          quality = quality - 10; // step down quality
          if (quality < 40) {
            await _showTooLargeDialog(); // still too big
            return;
          }
        }
      }
//---------------------------------------
// setstate to rebuild  the image box
//---------------------------------------
      setState(() {
        _pendingImageBytes = finalBytes;
        _pendingBase64 = finalB64;
      });
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            "Picking/compressing failed", style: TextStyle(fontSize: 12.sp))),
      );
    }
  }

//---------------------------------------
// remove image
//---------------------------------------
  void _clearPendingImage() {
    setState(() {
      _pendingImageBytes = null;
      _pendingBase64 = null;
    });
  }

//---------------------------------------
// when image too large pop up
//---------------------------------------
  Future<void> _showTooLargeDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return AlertDialog(
          title: Text("Image Too Large",
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600)),
          content: Text(
            "Please choose a smaller image.",
            style: TextStyle(fontSize: 14.sp),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              }, // close
              child: Text("OK", style: TextStyle(fontSize: 14.sp)),
            ),
          ],
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        );
      },
    );
  }

//---------------------------------------
// submit button loading
//---------------------------------------

  Widget _submitButton() {
    if (_submitting == true) {
      return SizedBox(
        width: 18.w,
        height: 18.w,
        child: const CircularProgressIndicator(
            strokeWidth: 2, color: Colors.white),
      );
    } else {
      return Text("Submit",
          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600));
    }
  }

//---------------------------------------
// submit proccess
//---------------------------------------
  Future<void> _trySubmit() async {
    if (_submitting == true) {
      return;
    }

    final String t = _titleCtrl.text.trim();
    final String d = _descCtrl.text.trim();

    //---------------------------------------
// validate
//---------------------------------------
    bool hasErr = false;
    if (t.isEmpty) {
      _titleError = "Title cannot be empty";
      hasErr = true;
    } else {
      _titleError = null;
    }
    if (d.isEmpty) {
      _descError = "Description cannot be empty";
      hasErr = true;
    } else {
      _descError = null;
    }
    setState(() {}); // refresh error UI
    if (hasErr == true) {
      return;
    }
//---------------------------------------
// double check maksrue user log in
//---------------------------------------

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            "Please sign in first.", style: TextStyle(fontSize: 12.sp))),
      );
      return;
    }
//---------------------------------------
// confirm pop up
//---------------------------------------
    final bool? ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: Text("Submit issue?",
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600)),
          content: Text("Are you sure you want to submit this issue?",
              style: TextStyle(fontSize: 14.sp)),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              }, // cancel
              child: Text("Cancel", style: TextStyle(fontSize: 14.sp)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, true);
              }, // confirm
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8620E5),
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero),
              ),
              child: Text("Submit", style: TextStyle(
                  fontSize: 14.sp, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );

    if (ok != true) {
      return;
    } // user canceled

    setState(() {
      _submitting = true;
    });

    try {
      // prepare display values
      String name = _displayUsername.isNotEmpty ? _displayUsername : "-";
      String mail = _displayEmail.isNotEmpty ? _displayEmail : "-";

      //---------------------------------------
// get all admin
//---------------------------------------

      final admins = await FirebaseFirestore.instance
          .collection("UserInformation")
          .where("role", isEqualTo: "Admin")
          .get();

      //---------------------------------------
// prepare to write batch into firestore
//---------------------------------------

      final WriteBatch batch = FirebaseFirestore.instance.batch();

      final DocumentReference sysRef =
      FirebaseFirestore.instance.collection("SystemIssues").doc();
      final String sysId = sysRef.id;

      batch.set(sysRef, {
        "issueTitle": t, // issue title
        "description": d, // description
        "username": name, // reporter display name
        "email": mail, // reporter email
        "submittedAt": FieldValue.serverTimestamp(), // for sorting
        "imageBase64": _pendingBase64 ?? "", // optional image
      });

//---------------------------------------
// count admin
//---------------------------------------

      int i = 0;
      while (i < admins.docs.length) {
        final admin = admins.docs[i];

        final DocumentReference inboxRef = FirebaseFirestore.instance
            .collection("UserInformation")
            .doc(admin.id)
            .collection("Inbox")
            .doc();

        batch.set(inboxRef, {
          "type": "system_issue", // same type
          "title": t, // same title
          "message": d, // same description
          "username": name, // reporter display name
          "email": mail, // reporter email
          "createdBy": user.uid, // reporter uid
          "recipientId": admin.id, // admin uid (for _canSee)
          "createdAt": FieldValue.serverTimestamp(), // for sorting
          "submittedAt": FieldValue.serverTimestamp(), // if you still use it
          "imageBase64": _pendingBase64 ?? "", // optional image
          "isRead": false, // mark unread
          "systemIssueId": sysId, // link to central record
        });

        i = i + 1;
      }

//---------------------------------------
// after it done
//---------------------------------------
      await batch.commit();

//---------------------------------------
// clear the controller
//---------------------------------------
      _titleCtrl.clear();
      _descCtrl.clear();
      setState(() {
        _titleLen = 0;
        _descLen = 0;
        _pendingImageBytes = null;
        _pendingBase64 = null;
      });

//---------------------------------------
// when success
//---------------------------------------
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            "Issue submitted", style: TextStyle(fontSize: 12.sp))),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
            "Failed to submit issue", style: TextStyle(fontSize: 12.sp))),
      );
    } finally {
      setState(() {
        _submitting = false;
      });
    }
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
          title: Text(
            "Reporting Issue",
            style: TextStyle(color: Colors.white,
                fontSize: 20.sp,
                fontWeight: FontWeight.w600),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              // simple pop is enough when you used Navigator.push to open this page
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            },
            tooltip: "Back",
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: _handleCloseToAccount,
              // keep your "go Account & clear stack"
              tooltip: "Close",
            ),
          ],
        ),
      ),

//---------------------------------------
// body
//---------------------------------------

      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 12.h),
            child: Column(
              children: [
                Container(
                  width: 0.9.sw,
                  padding: EdgeInsets.symmetric(
                      horizontal: 14.w, vertical: 14.h),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black, width: 1.5.w),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
//---------------------------------------
// display username
//---------------------------------------

                      Text("Username:", style: TextStyle(
                          fontSize: 14.sp, fontWeight: FontWeight.w500)),
                      SizedBox(height: 4.h),
                      Text(_displayUsername, style: TextStyle(
                          fontSize: 16.sp, fontWeight: FontWeight.w600)),
                      SizedBox(height: 10.h),

//---------------------------------------
// display email
//---------------------------------------
                      Text("Email:", style: TextStyle(
                          fontSize: 14.sp, fontWeight: FontWeight.w500)),
                      SizedBox(height: 4.h),
                      Text(_displayEmail, style: TextStyle(
                          fontSize: 16.sp, fontWeight: FontWeight.w600)),
                      SizedBox(height: 14.h),

//---------------------------------------
// display issue title
//---------------------------------------

                      Text("Issue Title", style: TextStyle(
                          fontSize: 14.sp, fontWeight: FontWeight.w500)),
                      SizedBox(height: 6.h),

                      Container(
                          width: 0.95.sw,
                          height: 48.h,
                          padding: EdgeInsets.symmetric(horizontal: 10.w),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.black, width: 1.w),
                          ),
                          child: Row(
                            children: [
//---------------------------------------
// text field for issue titel
//---------------------------------------
                              Expanded(
                                child: TextField(
                                  controller: _titleCtrl,
                                  maxLines: 1,
                                  textAlignVertical: TextAlignVertical.center,
//---------------------------------------
// limit the allowed text
//---------------------------------------
                                  inputFormatters: [
                                    LengthLimitingTextInputFormatter(99)
                                  ],
                                  decoration: const InputDecoration(
                                    hintText: 'Enter issue title',
                                    border: InputBorder.none,
                                    isCollapsed: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onChanged: (v) {
                                    setState(() {
                                      _titleLen = v.length;
                                      if (v.trim().isNotEmpty) {
                                        _titleError = null;
                                      }
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),


//---------------------------------------
// title error
//---------------------------------------
                      if (_titleError != null)
                        Padding(
                          padding: EdgeInsets.only(top: 4.h, left: 4.w),
                          child: Text(_titleError!, style: TextStyle(
                              fontSize: 12.sp, color: Colors.red)),
                        ),

//---------------------------------------
// title word counter
//---------------------------------------
                      SizedBox(height: 4.h),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text("${_titleLen}/99", style: TextStyle(
                            fontSize: 11.sp, color: Colors.grey)),
                      ),

                      SizedBox(height: 14.h),

//---------------------------------------
// desciption display
//---------------------------------------
                      Text("Description", style: TextStyle(
                          fontSize: 14.sp, fontWeight: FontWeight.w500)),
                      SizedBox(height: 6.h),

                      Container(
                          width: 95.sw,
                          height: 300.h,
                          child: TextField(
                            controller: _descCtrl,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            maxLines: null,
                            // allow many lines
                            expands: true,
                            // fill height box
                            textAlignVertical: TextAlignVertical.top,
//---------------------------------------
// limit the allowed text
//---------------------------------------

                            inputFormatters: [
                              LengthLimitingTextInputFormatter(499)
                            ],
                            onChanged: (v) {
                              setState(() {
                                _descLen = v.length;
                                if (v.trim().isNotEmpty) {
                                  _descError = null;
                                }
                              });
                            },
                            decoration: InputDecoration(
                              isDense: true,
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10.w, vertical: 10.h),
                              border: OutlineInputBorder(
                                borderSide: BorderSide(
                                    color: Colors.black, width: 1.w),
                              ),
                            ),
                          ),
                      ),

//---------------------------------------
// error space for deciption
//---------------------------------------
                      if (_descError != null)
                        Padding(
                          padding: EdgeInsets.only(top: 4.h, left: 4.w),
                          child: Text(_descError!, style: TextStyle(
                              fontSize: 12.sp, color: Colors.red)),
                        ),

//---------------------------------------
// decription counter
//---------------------------------------
                      SizedBox(height: 4.h),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text("${_descLen}/499", style: TextStyle(
                            fontSize: 11.sp, color: Colors.grey)),
                      ),

                      SizedBox(height: 14.h),

                      // ---- Image section header ----
                      Row(
                        children: [
                          IconButton(
                            onPressed: null, // disabled (use box below to pick)
                            icon: const Icon(Icons.image),
                            tooltip: "Add Image (tap the box below)",
                          ),
                          Text("Add Image", style: TextStyle(fontSize: 13.sp)),
                          const Spacer(),
                          if (_pendingImageBytes != null)
                            TextButton(
                              onPressed: _clearPendingImage,
                              child: Text(
                                  "Remove", style: TextStyle(fontSize: 12.sp)),
                            ),
                        ],
                      ),
                      SizedBox(height: 8.h),

//---------------------------------------
// image picker
//---------------------------------------
                      Center(
                        child: GestureDetector(
                          onTap: _pickResizePreviewImage, // open picker
                          child: Container(
                            width: 0.5.sw,
                            height: 170.h,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              border: Border.all(
                                  color: Colors.black, width: 1.w),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Builder(
                              builder: (_) {
                                if (_pendingImageBytes != null) {
                                  return Image.memory(
                                      _pendingImageBytes!, fit: BoxFit.cover);
                                } else {
//---------------------------------------
// if no image show place holder
//---------------------------------------
                                  return Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment
                                          .center,
                                      children: [
                                        const Icon(Icons.touch_app, size: 28),
                                        SizedBox(height: 6.h),
                                        Text("Pick image", style: TextStyle(
                                            fontSize: 12.sp,
                                            color: Colors.black54)),
                                      ],
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

//---------------------------------------
// submit button
//---------------------------------------

                SizedBox(height: 14.h),
                SizedBox(
                  width: 0.9.sw,
                  height: 48.h,
                  child: ElevatedButton(
                    onPressed: _submitting == true ? null : _trySubmit,
                    // disable when submitting
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8620E5),
                      foregroundColor: Colors.white,
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.zero),
                    ),
                    child: _submitButton(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

//---------------------------------------
// bottom navigation
//---------------------------------------
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: 4, // visually under Account tab
        onTabSelected: _onTabSelected,
      ),
    );
  }
}
