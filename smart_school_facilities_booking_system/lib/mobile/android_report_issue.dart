import 'dart:convert';                         // base64Encode / base64Decode helpers
import 'dart:typed_data';                      // Uint8List for raw bytes
import 'package:flutter/material.dart';        // core Flutter UI
import 'package:flutter/services.dart';        // input formatters (length limit, digits)
import 'package:flutter_screenutil/flutter_screenutil.dart'; // responsive sizing
import 'package:firebase_auth/firebase_auth.dart';            // Firebase Auth
import 'package:cloud_firestore/cloud_firestore.dart';        // Firestore client

import 'package:file_picker/file_picker.dart'; // file picker for picking image bytes
import 'package:image/image.dart' as img;      // image decode/resize/encode

// bottom bar destination pages
import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_list_of_facilities.dart';
import 'android_notifications.dart';
import 'android_account.dart';

// shared bottom menu bar
import 'android_bottom_menu.dart';

// ---------------------------
// Stateful page: Report Issue
// ---------------------------
class AndroidReportIssue extends StatefulWidget {
  // keep highlighted tab index in bottom bar (defaults to Account)
  final int currentIndex;
  // optional prefilled username (used before Firestore/Auth)
  final String? username;
  // optional prefilled email (used before Firestore/Auth)
  final String? email;

  // ctor stores incoming params only
  const AndroidReportIssue({
    Key? key,
    this.currentIndex = 4,
    this.username,
    this.email,
  }) : super(key: key);

  @override
  State<AndroidReportIssue> createState() => _AndroidReportIssueState();
}

// ---------------------------
// State: controllers + flows
// ---------------------------
class _AndroidReportIssueState extends State<AndroidReportIssue> {
  // title input controller
  final TextEditingController _titleCtrl = TextEditingController();
  // description input controller
  final TextEditingController _descCtrl  = TextEditingController();

  // live title char count for small counter
  int _titleLen = 0;
  // live description char count for small counter
  int _descLen  = 0;

  // title inline error string
  String? _titleError;
  // description inline error string
  String? _descError;

  // cache username/email future for single fetch
  late Future<Map<String, String>> _headerFuture;

  // prevent double submits during Firestore write
  bool _submitting = false;

  // preview image bytes (not yet saved)
  Uint8List? _pendingImageBytes;
  // preview image base64 (not yet saved)
  String? _pendingBase64;

  // base64 length limit to keep doc < 1MB (safe margin)
  static const int _maxBase64Len = 900000;
  // target max width for resizing large images
  static const int _targetMaxWidth = 600;

  // init: compute header future once
  @override
  void initState() {
    super.initState();
    _headerFuture = _loadUserHeader();
  }

  // back button: replace with Account page
  void _handleBack() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => AndroidAccount()),
    );
  }

  // close button: go to Account and clear stack
  void _handleCloseToAccount() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => AndroidAccount()),
          (route) => false,
    );
  }

  // bottom bar tab navigation with simple routing
  void _onTabSelected(int i) {
    if (i == widget.currentIndex) {
      // same tab, nothing to do
    } else if (i == 0) {
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

  // dispose input controllers to avoid memory leaks
  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // load username/email once (props → Firestore → Auth fallback)
  Future<Map<String, String>> _loadUserHeader() async {
    String name = "";
    String mail = "";

    // prefer passed-in username
    if (widget.username != null) {
      if (widget.username!.isNotEmpty) {
        name = widget.username!.trim();
      }
    }

    // prefer passed-in email
    if (widget.email != null) {
      if (widget.email!.isNotEmpty) {
        mail = widget.email!.trim();
      }
    }

    // if still empty, get from Firestore/Auth
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection("UserInformation")
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          if (name.isEmpty) {
            if (data["username"] != null) {
              final s = data["username"].toString().trim();
              if (s.isNotEmpty) name = s;
            }
          }
          if (mail.isEmpty) {
            if (data["email"] != null) {
              final e = data["email"].toString().trim();
              if (e.isNotEmpty) mail = e;
            } else {
              if (user.email != null) {
                if (user.email!.isNotEmpty) {
                  mail = user.email!.trim();
                }
              }
            }
          }
        }
      } else {
        if (mail.isEmpty) {
          if (user.email != null) {
            if (user.email!.isNotEmpty) mail = user.email!.trim();
          }
        }
      }
    }

    if (name.isEmpty) name = "-";
    if (mail.isEmpty) mail = "-";

    return {"username": name, "email": mail};
  }

  // pick image file → decode/resize/compress → keep preview only
  Future<void> _pickResizePreviewImage() async {
    try {
      final FilePickerResult? res = await FilePicker.platform.pickFiles(
        type: FileType.custom,                 // restrict to images
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        allowMultiple: false,                  // single image
        withData: true,                        // need raw bytes
      );

      // no selection or canceled
      if (res == null) return;
      if (res.files.isEmpty) return;

      // get file bytes directly
      final PlatformFile file = res.files.single;
      Uint8List? raw = file.bytes;

      // guard: bytes missing
      if (raw == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("This image cannot be read. Please pick a different one.", style: TextStyle(fontSize: 12.sp))),
        );
        return;
      }

      // decode image bytes (png/jpg supported)
      final img.Image? decoded = img.decodeImage(raw);
      if (decoded == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Unsupported image", style: TextStyle(fontSize: 12.sp))),
        );
        return;
      }

      // resize only if width exceeds target
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

      // iterative compression to respect base64 length limit
      int quality = 80;
      Uint8List? finalBytes;
      String? finalB64;

      while (true) {
        finalBytes = Uint8List.fromList(img.encodeJpg(toEncode, quality: quality));
        finalB64 = base64Encode(finalBytes);

        if (finalB64.length <= _maxBase64Len) {
          break; // size fits
        } else {
          quality = quality - 10; // reduce quality step
          if (quality < 40) {
            await _showTooLargeDialog(); // still too big
            return;
          }
        }
      }

      // save preview (not persisted yet)
      setState(() {
        _pendingImageBytes = finalBytes;
        _pendingBase64 = finalB64;
      });

      // notify image ready
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Image ready. It will be saved when you submit.", style: TextStyle(fontSize: 12.sp))),
      );
    } catch (_) {
      // show generic failure
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Picking/compressing failed", style: TextStyle(fontSize: 12.sp))),
      );
    }
  }

  // remove local image preview (keeps DB untouched)
  void _clearPendingImage() {
    setState(() {
      _pendingImageBytes = null;
      _pendingBase64 = null;
    });
  }

  // tell user to choose a smaller image when compression not enough
  Future<void> _showTooLargeDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return AlertDialog(
          title: Text("Image Too Large", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600)),
          content: Text(
            "Please choose a smaller image.\nTip: width around 400–600px is good.",
            style: TextStyle(fontSize: 14.sp),
          ),
          actions: [
            TextButton(
              onPressed: () { Navigator.pop(context); },
              child: Text("OK", style: TextStyle(fontSize: 14.sp)),
            ),
          ],
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        );
      },
    );
  }

  // render submit button child (spinner vs text) without ternary
  Widget _submitChild() {
    if (_submitting == true) {
      return SizedBox(
        width: 18.w,
        height: 18.w,
        child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    } else {
      return Text("Submit", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600));
    }
  }

  // validate → confirm → write Firestore → reset form
  Future<void> _trySubmit() async {
    if (_submitting == true) return;

    final String t = _titleCtrl.text.trim();
    final String d = _descCtrl.text.trim();

    // inline validation and error label updates
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
    setState(() {}); // refresh UI errors
    if (hasErr == true) return;

    // extra guard with snackbars
    if (t.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter an issue title", style: TextStyle(fontSize: 12.sp))),
      );
      return;
    }
    if (d.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Please enter a description", style: TextStyle(fontSize: 12.sp))),
      );
      return;
    }

    // user confirmation dialog
    final bool? ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: Text("Submit issue?", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600)),
          content: Text("Are you sure you want to submit this issue?", style: TextStyle(fontSize: 14.sp)),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          actions: [
            TextButton(
              onPressed: () { Navigator.pop(context, false); },
              child: Text("Cancel", style: TextStyle(fontSize: 14.sp)),
            ),
            ElevatedButton(
              onPressed: () { Navigator.pop(context, true); },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              child: Text("Submit", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );

    // abort if canceled
    if (ok != true) return;

    // set submitting flag for button state
    setState(() { _submitting = true; });

    try {
      // read name/mail from cached header
      final Map<String, String> header = await _headerFuture;

      String name = "-";
      if (header.containsKey("username")) {
        final String? maybeName = header["username"];
        if (maybeName != null && maybeName.isNotEmpty) {
          name = maybeName;
        }
      }

      String mail = "-";
      if (header.containsKey("email")) {
        final String? maybeMail = header["email"];
        if (maybeMail != null && maybeMail.isNotEmpty) {
          mail = maybeMail;
        }
      }

      // send to all Admin users' inbox
      final admins = await FirebaseFirestore.instance
          .collection("UserInformation")
          .where("role", isEqualTo: "Admin")
          .get();

      final batch = FirebaseFirestore.instance.batch();

      for (final admin in admins.docs) {
        final inboxRef = FirebaseFirestore.instance
            .collection("UserInformation")
            .doc(admin.id)
            .collection("Inbox")
            .doc();

        batch.set(inboxRef, {
          "type": "system_issue",                       // use lower-case consistently
          "title": t,                                   // issue title
          "message": d,                                 // description
          "username": name,
          "email": mail,
          "createdBy": FirebaseAuth.instance.currentUser?.uid ?? "",
          "recipientId": admin.id,                      // <-- REQUIRED so _canSee() passes
          "createdAt": FieldValue.serverTimestamp(),    // <-- REQUIRED so your list/query can sort & group
          "submittedAt": FieldValue.serverTimestamp(),  // optional: keep if you still want this
          "imageBase64": _pendingBase64 ?? "",
          "isRead": false,
        });

      }

      await batch.commit();

      // clear inputs + counters + image preview
      _titleCtrl.clear();
      _descCtrl.clear();
      setState(() {
        _titleLen = 0;
        _descLen = 0;
        _pendingImageBytes = null;
        _pendingBase64 = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Issue submitted", style: TextStyle(fontSize: 12.sp))),
      );

    } catch (_) {
      // failure toast
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to submit issue", style: TextStyle(fontSize: 12.sp))),
      );
    } finally {
      // clear submitting flag regardless
      setState(() { _submitting = false; });
    }
  }

  // build full page with WillPopScope to control back
  @override
  Widget build(BuildContext context) {
    final double barHeight = 60.h;

    // intercept system back to go Account (replace)
    return WillPopScope(
      onWillPop: () async {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
        return false; // consume default pop
      },

      // scaffold with purple app bar
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(60.h),
          child: AppBar(
            backgroundColor: const Color(0xFF9747FF),
            elevation: 0,
            centerTitle: true,
            title: Text(
              "Reporting Issue",
              style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: _handleBack,              // back to Account (replace)
              tooltip: "Back",
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _handleCloseToAccount,   // close to Account (clear stack)
                tooltip: "Close",
              ),
            ],
          ),
        ),

        // body: resolve username/email once via FutureBuilder
        body: FutureBuilder<Map<String, String>>(
          future: _headerFuture,
          builder: (context, snap) {
            // center spinner during header load
            if (snap.connectionState == ConnectionState.waiting) {
              return Center(
                child: SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator()),
              );
            }

            // default header labels
            String displayUsername = "-";
            String displayEmail = "-";

            // fill header labels when data exists
            if (snap.hasData) {
              final Map<String, String> map = snap.data!;
              if (map.containsKey("username")) {
                final String? v = map["username"];
                if (v != null) {
                  if (v.isNotEmpty) {
                    displayUsername = v;
                  }
                }
              }
              if (map.containsKey("email")) {
                final String? e = map["email"];
                if (e != null) {
                  if (e.isNotEmpty) {
                    displayEmail = e;
                  }
                }
              }
            }

            // layout builder ensures min height to center the card
            return LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        child: Column(
                          children: [
                            // form card container
                            Container(
                              width: 0.9.sw,
                              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: Colors.black, width: 1.5.w),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // static username line
                                  Text("Username:", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                                  SizedBox(height: 4.h),
                                  Text(displayUsername, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                                  SizedBox(height: 10.h),

                                  // static email line
                                  Text("Email:", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                                  SizedBox(height: 4.h),
                                  Text(displayEmail, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600)),
                                  SizedBox(height: 14.h),

                                  // title label
                                  Text("Issue Title", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                                  SizedBox(height: 6.h),

                                  // title input with clear button slot
                                  FractionallySizedBox(
                                    widthFactor: 0.95,
                                    child: Container(
                                      height: 48.h,
                                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        border: Border.all(color: Colors.black, width: 1.w),
                                      ),
                                      child: Row(
                                        children: [
                                          // expand text field horizontally
                                          Expanded(
                                            child: TextField(
                                              controller: _titleCtrl,
                                              maxLines: 1,
                                              textAlignVertical: TextAlignVertical.center,
                                              inputFormatters: [LengthLimitingTextInputFormatter(99)],
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
                                                    _titleError = null; // clear error when user types valid
                                                  }
                                                });
                                              },
                                            ),
                                          ),

                                          // fixed clear-slot to avoid layout shift
                                          SizedBox(
                                            width: 36.w,
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: Visibility(
                                                visible: _titleCtrl.text.isNotEmpty,
                                                maintainSize: true,
                                                maintainAnimation: true,
                                                maintainState: true,
                                                child: InkWell(
                                                  onTap: () { _titleCtrl.clear(); },
                                                  child: Icon(Icons.clear, size: 20.sp, color: Colors.grey.shade700),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // title inline error text when present
                                  if (_titleError != null)
                                    Padding(
                                      padding: EdgeInsets.only(top: 4.h, left: 4.w),
                                      child: Text(_titleError!, style: TextStyle(fontSize: 12.sp, color: Colors.red)),
                                    ),

                                  // title char counter right aligned
                                  SizedBox(height: 4.h),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text("${_titleLen}/99", style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
                                  ),

                                  SizedBox(height: 14.h),

                                  // description label
                                  Text("Description", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                                  SizedBox(height: 6.h),

                                  // description multiline expanding field
                                  FractionallySizedBox(
                                    widthFactor: 0.95,
                                    child: SizedBox(
                                      height: 300.h,
                                      child: TextField(
                                        controller: _descCtrl,
                                        keyboardType: TextInputType.multiline,
                                        textInputAction: TextInputAction.newline,
                                        maxLines: null,
                                        expands: true,
                                        textAlignVertical: TextAlignVertical.top,
                                        inputFormatters: [LengthLimitingTextInputFormatter(499)],
                                        onChanged: (v) {
                                          setState(() {
                                            _descLen = v.length;
                                            if (v.trim().isNotEmpty) {
                                              _descError = null; // clear error when user types valid
                                            }
                                          });
                                        },
                                        decoration: InputDecoration(
                                          isDense: true,
                                          filled: true,
                                          fillColor: Colors.white,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
                                          border: OutlineInputBorder(
                                            borderSide: BorderSide(color: Colors.black, width: 1.w),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // description inline error when present
                                  if (_descError != null)
                                    Padding(
                                      padding: EdgeInsets.only(top: 4.h, left: 4.w),
                                      child: Text(_descError!, style: TextStyle(fontSize: 12.sp, color: Colors.red)),
                                    ),

                                  // description char counter right aligned
                                  SizedBox(height: 4.h),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text("${_descLen}/499", style: TextStyle(fontSize: 11.sp, color: Colors.grey)),
                                  ),

                                  SizedBox(height: 14.h),

                                  // image section header row with disabled icon and optional remove
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: null, // intentionally disabled (use the box below to pick)
                                        icon: const Icon(Icons.image),
                                        tooltip: "Add Image (tap the box below)",
                                      ),
                                      Text("Add Image", style: TextStyle(fontSize: 13.sp)),
                                      const Spacer(),
                                      if (_pendingImageBytes != null)
                                        TextButton(
                                          onPressed: _clearPendingImage,
                                          child: Text("Remove", style: TextStyle(fontSize: 12.sp)),
                                        ),
                                    ],
                                  ),
                                  SizedBox(height: 8.h),

                                  // image preview box (tap to pick)
                                  Center(
                                    child: GestureDetector(
                                      onTap: _pickResizePreviewImage, // picker entry point
                                      child: Container(
                                        width: 0.5.sw,
                                        height: 170.h,
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          border: Border.all(color: Colors.black, width: 1.w),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: Builder(
                                          builder: (_) {
                                            if (_pendingImageBytes != null) {
                                              return Image.memory(_pendingImageBytes!, fit: BoxFit.cover);
                                            } else {
                                              return Center(
                                                child: Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    const Icon(Icons.touch_app, size: 28),
                                                    SizedBox(height: 6.h),
                                                    Text("Pick image", style: TextStyle(fontSize: 12.sp, color: Colors.black54)),
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

                            // submit button under the form card
                            SizedBox(height: 14.h),
                            SizedBox(
                              width: 0.9.sw,
                              height: 48.h,
                              child: Builder(
                                builder: (_) {
                                  // choose enabled/disabled handler without ternary
                                  VoidCallback? submitHandler;
                                  if (_submitting == true) {
                                    submitHandler = null;
                                  } else {
                                    submitHandler = _trySubmit;
                                  }

                                  // render elevated button with spinner or label
                                  return ElevatedButton(
                                    onPressed: submitHandler,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF8620E5),
                                      foregroundColor: Colors.white,
                                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                                    ),
                                    child: _submitChild(),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),

        // bottom bar persistent navigation
        bottomNavigationBar: BottomMenuBar(
          height: barHeight,
          currentIndex: widget.currentIndex,
          onTabSelected: _onTabSelected,
        ),
      ),
    );
  }
}
