import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'android_notification_setting.dart';

import 'android_bottom_menu.dart';
import 'android_faq.dart';

import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_list_of_facilities.dart';
import 'android_notifications.dart';
import 'android_report_issue.dart';

import 'android_login.dart';

class AndroidAccount extends StatefulWidget {
  AndroidAccount({Key? key}) : super(key: key);

  @override
  State<AndroidAccount> createState() => _AndroidAccountState();
}

class _AndroidAccountState extends State<AndroidAccount> {
//---------------------------------------
// current index
//---------------------------------------
  int _currentIndex = 4;
  bool _isEditing = false;


  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _contactCtrl  = TextEditingController();

  String? _usernameError;
  String? _contactError;

  String _username = "";
  String _email    = "";
  String _contact  = "";
  String _role     = "";

  Uint8List? _savedImageBytes;   // image already saved in Firestore
  Uint8List? _pendingImageBytes; // image picked this session (preview only)
  String? _pendingBase64;        // base64 for saving on Confirm

  bool _loadedOnce = false;

  static const int _maxBase64Len = 900000; // keep < ~0.86MB text (Firestore doc limit 1MB)
  static const int _targetMaxWidth = 400;  // resize target width (keep aspect ratio)

//---------------------------------------
// bottom bar navigation
//---------------------------------------
  void _onTabSelected(int i) {
    if (i == 4) {
      setState(() { _currentIndex = 4; });
    } else if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAgenda()));
    } else if (i == 1) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } else if (i == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
    } else if (i == 3) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
    }
  }

//---------------------------------------
// view mode
//---------------------------------------
  Widget _labelAndValue(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 14.sp, color: Colors.black87, fontWeight: FontWeight.w500)),
          SizedBox(height: 4.h),
          Text(value,  style: TextStyle(fontSize: 16.sp, color: Colors.black, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

//---------------------------------------
// while in ediing mode, text field
//---------------------------------------
  Widget _editableField({
    required String label,
    required TextEditingController controller,
    String? errorText,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 14.sp, color: Colors.black87, fontWeight: FontWeight.w500)),
          SizedBox(height: 4.h),
          TextField(
            controller: controller,
            inputFormatters: inputFormatters,
            decoration: InputDecoration(
              isDense: true,
              border: OutlineInputBorder(borderSide: BorderSide(color: Colors.black, width: 1.w)),
              errorText: errorText,
            ),
          ),
        ],
      ),
    );
  }

//---------------------------------------
// navigate button
//---------------------------------------
  Widget _actionBox({
    required String title,
    required VoidCallback onTap,
    Color fillColor = const Color(0xFFF2F2F2),
    Color borderColor = const Color(0xFF000000),
    Color textColor = const Color(0xFF000000),
  }) {
    final double h = math.max(48.h, 0.065.sh);
    final double w = math.min(0.9.sw, 520.w);
    return InkWell(
      onTap: onTap,
      child: Container(
        width: w,
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fillColor,
          border: Border.all(color: borderColor, width: 1.5.w),
          borderRadius: BorderRadius.zero,
          shape: BoxShape.rectangle,
        ),
        child: Text(title, style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: textColor)),
      ),
    );
  }
//---------------------------------------
// strong password
//---------------------------------------
  bool _isPasswordStrong(String password) {
    // RegExp = pattern checker for strength
    final RegExp regex = RegExp(r'^(?=.*[A-Z])(?=.*[!@#\$%^&*(),.?":{}|<>]).{8,}$');
    if (regex.hasMatch(password)) {
      return true;
    } else {
      return false;
    }
  }
//---------------------------------------
// open change password pop up
//---------------------------------------
  Future<void> _openChangePasswordDialog() async {

    final TextEditingController _oldCtrl = TextEditingController();      // old password input
    final TextEditingController _newCtrl = TextEditingController();      // new password input
    final TextEditingController _confirmCtrl = TextEditingController();  // confirm new password

    bool _hideOld = true;       // obscure old password
    bool _hideNew = true;       // obscure new password
    bool _hideConfirm = true;   // obscure confirm password

    String? _oldErr;
    String? _newErr;
    String? _confirmErr;

//---------------------------------------
// show  pop up function
//---------------------------------------
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
//---------------------------------------
// when change button press
//---------------------------------------
            Future<void> _attemptChange() async {
              setStateDialog(() {
                _oldErr = null;
                _newErr = null;
                _confirmErr = null;
              });
              // assume ok first
              bool ok = true;

//---------------------------------------
// check passowrd make sure cannot empty
//---------------------------------------
              if (_oldCtrl.text.isEmpty) {
                setStateDialog(() { _oldErr = "Old password cannot be empty"; });
                ok = false;
              }
              // check new strong
              if (_isPasswordStrong(_newCtrl.text)) {
              } else {
                setStateDialog(() { _newErr = "Min 8 chars, 1 uppercase, 1 special"; });
                ok = false;
              }
              // check confirm
              if (_confirmCtrl.text.isEmpty) {
                setStateDialog(() { _confirmErr = "Confirm password cannot be empty"; });
                ok = false;
              } else {
                if (_confirmCtrl.text == _newCtrl.text) {
                  // ok
                } else {
                  setStateDialog(() { _confirmErr = "Passwords do not match"; });
                  ok = false;
                }
              }
              // stop if invalid
              if (ok == false) {
                return;
              }

//---------------------------------------
// if evrything check pass, then check old password is right or wrong
//---------------------------------------
              final User? user = FirebaseAuth.instance.currentUser;

              if (user == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("No user logged in", style: TextStyle(fontSize: 12.sp))),
                );
                return;
              }

              if (user.email == null) {
                // without email (e.g., Google sign-in), this flow is not applicable
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("This account does not use email/password", style: TextStyle(fontSize: 12.sp))),
                );
                return;
              }

              try {
//---------------------------------------
// get the old password form fireauth
//---------------------------------------
                final AuthCredential cred = EmailAuthProvider.credential(
                  email: user.email!,
                  password: _oldCtrl.text,
                );

                await user.reauthenticateWithCredential(cred); // important security step

                await user.updatePassword(_newCtrl.text);
//---------------------------------------
// when success close pop up
//---------------------------------------
                Navigator.pop(context);

//---------------------------------------
// when success
//---------------------------------------
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Password updated successfully", style: TextStyle(fontSize: 12.sp))),
                );
//---------------------------------------
// when have error
//---------------------------------------
              } on FirebaseAuthException catch (e) {
                // map common errors to friendly messages
                if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
                  setStateDialog(() { _oldErr = "Old password is incorrect"; });
                } else if (e.code == 'weak-password') {
                  setStateDialog(() { _newErr = "New password too weak"; });
                } else if (e.code == 'too-many-requests') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Too many attempts. Try again later.", style: TextStyle(fontSize: 12.sp))),
                  );
                } else if (e.code == 'requires-recent-login') {
                  // reauth should handle this; if appears, ask to log in again
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Please log in again and retry.", style: TextStyle(fontSize: 12.sp))),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Failed to change password", style: TextStyle(fontSize: 12.sp))),
                  );
                }
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Unexpected error", style: TextStyle(fontSize: 12.sp))),
                );
              }
            }

//---------------------------------------
// desgin of the pop up
//---------------------------------------
            return AlertDialog(
              title: Text("Change Password", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600)),
              content: SizedBox(
                width: math.min(520.w, 0.9.sw),  // keep dialog responsive
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
//---------------------------------------
// old password field
//---------------------------------------
                      Text("Old Password", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                      TextField(
                        controller: _oldCtrl,
                        obscureText: _hideOld,
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(borderSide: BorderSide(width: 1.w)),
                          errorText: _oldErr,
                          suffixIcon: IconButton(
                            icon: Icon(_hideOld ? Icons.visibility_off : Icons.visibility),
                            onPressed: () {
                              // toggle hide/show
                              if (_hideOld == true) {
                                setStateDialog(() { _hideOld = false; });
                              } else {
                                setStateDialog(() { _hideOld = true; });
                              }
                            },
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
//---------------------------------------
// new password field
//---------------------------------------
                      Text("New Password", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                      TextField(
                        controller: _newCtrl,
                        obscureText: _hideNew,
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(borderSide: BorderSide(width: 1.w)),
                          errorText: _newErr,
                          suffixIcon: IconButton(
                            icon: Icon(_hideNew ? Icons.visibility_off : Icons.visibility),
                            onPressed: () {
                              if (_hideNew == true) {
                                setStateDialog(() { _hideNew = false; });
                              } else {
                                setStateDialog(() { _hideNew = true; });
                              }
                            },
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
//---------------------------------------
// confirm password field
//---------------------------------------
                      Text("Confirm New Password", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500)),
                      TextField(
                        controller: _confirmCtrl,
                        obscureText: _hideConfirm,
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(borderSide: BorderSide(width: 1.w)),
                          errorText: _confirmErr,
                          suffixIcon: IconButton(
                            icon: Icon(_hideConfirm ? Icons.visibility_off : Icons.visibility),
                            onPressed: () {
                              if (_hideConfirm == true) {
                                setStateDialog(() { _hideConfirm = false; });
                              } else {
                                setStateDialog(() { _hideConfirm = true; });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
//---------------------------------------
// cancel button
//---------------------------------------
                TextButton(
                  onPressed: () { Navigator.pop(context); }, // close dialog
                  child: Text("Cancel", style: TextStyle(fontSize: 14.sp)),
                ),
//---------------------------------------
// change button
//---------------------------------------
                ElevatedButton(
                  onPressed: _attemptChange,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8620E5),
                    foregroundColor: Colors.white,
                  ),
                  child: Text("Change", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                ),
              ],
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            );
          },
        );
      },
    );
  }

//---------------------------------------
// validate username and contact
//---------------------------------------
  bool _validateInputs() {
    bool ok = true;

    _usernameError = null;
    _contactError = null;

    if (_usernameCtrl.text.trim().isEmpty) {
      _usernameError = "Username cannot be empty";
      ok = false;
    }

    String c = _contactCtrl.text.trim();
    if (c.isEmpty) {
      _contactError = "Contact cannot be empty";
      ok = false;
    } else {
      final RegExp onlyDigits = RegExp(r'^\d+$');
      if (!onlyDigits.hasMatch(c)) {
        _contactError = "Contact must be numbers only";
        ok = false;
      }
    }

    setState(() {}); // refresh error UI
    return ok;
  }

//---------------------------------------
// image picker
//---------------------------------------
  Future<void> _pickResizePreview() async {
    try {
//---------------------------------------
// allow extension
//---------------------------------------
      final FilePickerResult? res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        allowMultiple: false,
        withData: true,
      );

      if (res == null) {
        return;
      }
      if (res.files.isEmpty) {
        return;
      }

      final PlatformFile file = res.files.single;

      Uint8List? raw = file.bytes;
      if (raw == null) {

        if (file.path != null) {
          final File f = File(file.path!);
          if (f.existsSync()) {
            raw = await f.readAsBytes();
          }
        }
      }

      if (raw == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No file bytes found", style: TextStyle(fontSize: 12.sp))),
        );
        return;
      }

      final img.Image? decoded = img.decodeImage(raw);
      if (decoded == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Unsupported image", style: TextStyle(fontSize: 12.sp))),
        );
        return;
      }

  //---------------------------------------
// allow not too big size image
//---------------------------------------
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


      int quality = 80;
      Uint8List? finalBytes;
      String? finalB64;

      while (true) {
        finalBytes = Uint8List.fromList(img.encodeJpg(toEncode, quality: quality));
        finalB64 = base64Encode(finalBytes);

        if (finalB64.length <= _maxBase64Len) {
          break;
        } else {
          quality = quality - 10;
//---------------------------------------
// if resize still big then show error
//---------------------------------------
          if (quality < 40) {
            await _showTooLargeDialog();
            return;
          }
        }
      }

//---------------------------------------
// set the image
//---------------------------------------
      setState(() {
        _pendingImageBytes = finalBytes;
        _pendingBase64 = finalB64;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Preview ready. Press Confirm to save.", style: TextStyle(fontSize: 12.sp))),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Picking/compressing failed", style: TextStyle(fontSize: 12.sp))),
      );
    }
  }

//---------------------------------------
// when image too large
//---------------------------------------
  Future<void> _showTooLargeDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return AlertDialog(
          title: Text("Image Too Large", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600)),
          content: Text("Please choose a smaller image.\nTip: width around 300-400px is good.", style: TextStyle(fontSize: 14.sp)),
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

//---------------------------------------
// remove image
//---------------------------------------
  Future<void> _onRemoveImage(String uid) async {
    //---------------------------------------
// if image still pending then will normal remove
//---------------------------------------
    if (_pendingImageBytes != null) {
      // Clear only the preview
      setState(() {
        _pendingImageBytes = null;
        _pendingBase64 = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Preview image cleared", style: TextStyle(fontSize: 12.sp))),
      );
    } else {
      //---------------------------------------
// if the image is from database , will update directly
//---------------------------------------
      try {
        await FirebaseFirestore.instance
            .collection("UserInformation")
            .doc(uid)
            .update({"profileImageBase64": null});

        setState(() {
          _savedImageBytes = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Profile image removed", style: TextStyle(fontSize: 12.sp))),
        );
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to remove image", style: TextStyle(fontSize: 12.sp))),
        );
      }
    }
  }

//---------------------------------------
// confirm log out pop up
//---------------------------------------
  Future<void> _confirmLogout() async {
    final bool? yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: Text("Log out?", style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600)),
          content: Text("Are you sure you want to log out?", style: TextStyle(fontSize: 14.sp)),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          actions: [
            TextButton(
              onPressed: () { Navigator.pop(context, false); },
              child: Text("Cancel", style: TextStyle(fontSize: 14.sp)),
            ),
            ElevatedButton(
              onPressed: () { Navigator.pop(context, true); },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF0707),
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              ),
              child: Text("Log Out", style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );

    if (yes == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => AndroidLoginPage()),
              (route) => false,
        );
      }
    }
  }

//---------------------------------------
// main build
//---------------------------------------
  @override
  Widget build(BuildContext context) {
    final double barHeight = 60.h;

//---------------------------------------
// make sure there is user
//---------------------------------------
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        body: Center(child: Text("No user logged in", style: TextStyle(fontSize: 16.sp))),
      );
    }

//---------------------------------------
// get current user information from database
//---------------------------------------
    final Future<DocumentSnapshot<Map<String, dynamic>>> userFuture =
    FirebaseFirestore.instance.collection("UserInformation").doc(uid).get();

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          title: Text("Account", style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(bottomLeft: Radius.circular(40.r), bottomRight: Radius.circular(40.r)),
          ),
        ),
      ),

      body: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: userFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: SizedBox(width: 24.w, height: 24.w, child: const CircularProgressIndicator()),
            );
          }

          if (snapshot.hasError) {
            return Center(child: Text("Failed to load profile", style: TextStyle(fontSize: 14.sp)));
          }

          final Map<String, dynamic>? data = snapshot.data?.data();
          if (data == null) {
            return Center(child: Text("Profile not found", style: TextStyle(fontSize: 14.sp)));
          }
//---------------------------------------
// set all the importat data first
//---------------------------------------
          String username = "";
          if (data["username"] != null) {
            username = data["username"].toString().trim();
          }

          String contact = "";
          if (data["contact"] != null) {
            contact = data["contact"].toString().trim();
          }

          String role = "";
          if (data["role"] != null) {
            role = data["role"].toString().trim();
          }

          String email = "";
          if (data["email"] != null) {
            email = data["email"].toString().trim();
          } else {
            if (FirebaseAuth.instance.currentUser?.email != null) {
              email = FirebaseAuth.instance.currentUser!.email!.trim();
            } else {
              email = "";
            }
          }

//---------------------------------------
// decode image from 64 byte
//---------------------------------------
          if (_loadedOnce == false) {
            if (data["profileImageBase64"] != null) {
              final String b64 = data["profileImageBase64"].toString();
              if (b64.isNotEmpty) {
                try {
                  _savedImageBytes = base64Decode(b64);// DECODE Base64 to image
                } catch (_) {
                  _savedImageBytes = null;
                }
              }
            }
          }

//---------------------------------------
// after the load is success , set all the info to controller
//---------------------------------------
          if (_loadedOnce == false) {
            _usernameCtrl.text = username;
            _contactCtrl.text  = contact;

            _username = username;
            _email    = email;
            _contact  = contact;
            _role     = role;

            _loadedOnce = true;
          }

//---------------------------------------
// set the button
//---------------------------------------
          String mainButtonLabel = "";
          if (_isEditing == true) {
            mainButtonLabel = "Confirm";
          } else {
            mainButtonLabel = "Edit";
          }

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
//---------------------------------------
// profile picture
//---------------------------------------
                GestureDetector(
                  onTap: () {
                    if (_isEditing == true) {
                      if (_pendingImageBytes == null && _savedImageBytes == null) {
                        _pickResizePreview();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("To change photo, tap 'Remove Image' first.", style: TextStyle(fontSize: 12.sp))),
                        );
                      }
                    }
                  },

                  child: Container(
                    width: 150.w,
                    height: 150.w,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey[300]),
                    clipBehavior: Clip.antiAlias,
                    child: Builder(
                      builder: (ctx) {
                        // Show pending preview first
                        if (_pendingImageBytes != null) {
                          return Image.memory(_pendingImageBytes!, fit: BoxFit.cover);
                        } else {
                          // Else show saved image
                          if (_savedImageBytes != null) {
                            return Image.memory(_savedImageBytes!, fit: BoxFit.cover);
                          } else {
                            // Else show label (tap-to-add in edit mode)
                            String hint = "";
                            if (_isEditing == true) {
                              hint = "Tap to add";
                            } else {
                              hint = "Empty";
                            }
                            return Center(
                              child: Text(
                                hint,
                                style: TextStyle(fontSize: 14.sp, color: Colors.black54, fontWeight: FontWeight.w600),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                ),

//---------------------------------------
// while is editing the image below
//---------------------------------------
                if (_isEditing) ...[
                  SizedBox(height: 10.h),
                  if (_pendingImageBytes != null || _savedImageBytes != null)
                    SizedBox(
                      width: math.min(0.9.sw, 520.w),
                      height: math.max(40.h, 0.055.sh),
                      child: ElevatedButton(
                        onPressed: () {
                          _onRemoveImage(uid);
                          },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[700],
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        ),
                        child: Text("Remove Image", style: TextStyle(fontSize: 12.sp)),
                      ),
                    ),
                ],

                SizedBox(height: 16.h),

//---------------------------------------
// profile part
//---------------------------------------
                Align(
                  alignment: Alignment.centerLeft,
                  child: _isEditing
                      ? _editableField(label: "Username:", controller: _usernameCtrl, errorText: _usernameError)
                      : _labelAndValue("Username:", _username),
                ),
                Align(alignment: Alignment.centerLeft, child: _labelAndValue("Email:", _email)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _isEditing
                      ? _editableField(
                    label: "Contact:",
                    controller: _contactCtrl,
                    errorText: _contactError,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  )
                      : _labelAndValue("Contact:", _contact),
                ),
                Align(alignment: Alignment.centerLeft, child: _labelAndValue("Role:", _role)),

                SizedBox(height: 12.h),

//---------------------------------------
// edit and confirm button
//---------------------------------------
                Row(
                  children: [
                    const Spacer(),
                    SizedBox(
                      height: math.max(36.h, 0.05.sh),
                      child: ElevatedButton(
                        onPressed: () async {
//---------------------------------------
// if not editing mode
//---------------------------------------
                          if (_isEditing == false) {
                            setState(() {
                              _isEditing = true;
                              _usernameError = null;
                              _contactError = null;
                            });
                          } else {
//---------------------------------------
// if in editing mode when confirm button press
//---------------------------------------
                            bool ok = _validateInputs();
                            if (ok == true) {
                              final Map<String, dynamic> updates = {
                                "username": _usernameCtrl.text.trim(),
                                "contact": _contactCtrl.text.trim(),
                              };

//---------------------------------------
// save image
//---------------------------------------
                              if (_pendingBase64 != null) {
                                updates["profileImageBase64"] = _pendingBase64;
                              }
//---------------------------------------
// save ipdate item into database
//---------------------------------------
                              await FirebaseFirestore.instance
                                  .collection("UserInformation")
                                  .doc(uid)
                                  .update(updates);

//---------------------------------------
// set the controller holding the name and contact
//---------------------------------------
                              setState(() {
                                _isEditing = false;
                                _username = _usernameCtrl.text.trim();
                                _contact  = _contactCtrl.text.trim();

//---------------------------------------
// move pending image to saveimage
//---------------------------------------
                                if (_pendingImageBytes != null) {
                                  _savedImageBytes = _pendingImageBytes;
                                }
                                _pendingImageBytes = null;
                                _pendingBase64 = null;
                              });

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Profile updated", style: TextStyle(fontSize: 12.sp))),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isEditing ? const Color(0xFF4CAF50) : const Color(0xFF2196F3),
                          foregroundColor: Colors.white,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        ),
                        child: Text(
//---------------------------------------
// button already set above
//---------------------------------------
                          mainButtonLabel,
                          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),

//---------------------------------------
// devider
//---------------------------------------
                SizedBox(height: 12.h),
                Container(width: 0.8.sw, height: 1.5.h, color: Colors.black),
                SizedBox(height: 16.h),

//---------------------------------------
// change password button
//---------------------------------------
                _actionBox(title: "Change Password", onTap: () { _openChangePasswordDialog(); }),

                SizedBox(height: 14.h),
//---------------------------------------
// notification setting
//---------------------------------------
                _actionBox(
                  title: "Notification Settings",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationSetting()),
                    );
                  },
                ),
                SizedBox(height: 14.h),
//---------------------------------------
// report issue page
//---------------------------------------
                _actionBox(
                  title: "Report an Issue",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AndroidReportIssue()),
                    );
                  },
                ),
                SizedBox(height: 14.h),
//---------------------------------------
// FAQ page
//---------------------------------------
                _actionBox(
                  title: "FAQ",
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AndroidFAQ()),
                    );
                  },
                ),
                SizedBox(height: 16.h),
//---------------------------------------
// log out with showing pop up
//---------------------------------------
                _actionBox(
                  title: "Log Out",
                  onTap: _confirmLogout,
                  fillColor: const Color(0xFFFCC2CF),
                  borderColor: const Color(0xFFFF0707),
                  textColor: const Color(0xFFFF0707),
                ),
              ],
            ),
          );
        },
      ),

//---------------------------------------
// buttom navigate bar
//---------------------------------------
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}
