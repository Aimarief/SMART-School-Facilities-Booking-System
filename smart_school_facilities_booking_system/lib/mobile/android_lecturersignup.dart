import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

import 'package:cloud_firestore/cloud_firestore.dart';               // Firestore database
import 'package:firebase_auth/firebase_auth.dart';                   // Firebase Authentication (sign up / login)
import 'package:flutter/material.dart';                              // Flutter UI
import 'package:flutter/services.dart';                              // For FilteringTextInputFormatter (digits only)
import 'package:flutter_screenutil/flutter_screenutil.dart';         // For .w .h .sp responsive sizes
import 'package:smart_school_facilities_booking_system/mobile/android_signup.dart';

// These are your other screens/files
import 'android_login.dart';                                         // Your Android Login page
import 'android_list_of_facilities.dart';
import 'android_signup.dart';
import 'android_tnc.dart';
import 'android_privacy_policy.dart';

// --------------
// Main Page UI
// --------------

// A simple page that shows a header and the sign up form
class LecturerSignup extends StatelessWidget {
  // build() = function that draws the UI (screen)
  @override
  Widget build(BuildContext context) {
    // Scaffold = basic page structure with background and body
    return Scaffold(
      // SingleChildScrollView = make page scrollable if content is long
      body: SingleChildScrollView(
        child: Column(
          children: [
            GradientHeader(), // our gradient top header
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
              child: SignupInformation(), // the sign up form area
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------
// Pretty Gradient Header
// ---------------------

class GradientHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Get screen width to make header full width
    double screenWidth = MediaQuery.of(context).size.width;

    // Container = a box that can have size, color, padding
    return Container(
      width: screenWidth,
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 30.h),
      decoration: BoxDecoration(
        // Rounded bottom corners only
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40.r),
          bottomRight: Radius.circular(40.r),
        ),
        // LinearGradient = top to bottom purple style
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.01, 0.27, 1.0],
          colors: [
            Color(0xFFF038FF),
            Color(0xFF6E00D4),
            Color(0xFFB779F1),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: 25.h),
          Text(
            'Facilities Booking',
            style: TextStyle(
              fontSize: 24.sp,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 20.h),
          // Row with "Log In" and "Sign Up" buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Outline button = go to Login page
              OutlinedButton(
                onPressed: () {
                  // Navigator.push = go to another page
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AndroidLoginPage()),
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 12.h),
                  side: BorderSide(color: Colors.white),
                  foregroundColor: Colors.white,
                ),
                child: Text('Log In', style: TextStyle(fontSize: 14.sp)),
              ),
              SizedBox(width: 20.w),
              // Current page button (no action needed)
              ElevatedButton(
                onPressed: () {
                  // We are already on Sign Up page, so do nothing
                },
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 35.w, vertical: 12.h),
                ),
                child: Text('Sign Up', style: TextStyle(fontSize: 14.sp)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------
// Sign Up Form (Stateful Widget)
// ------------------------------

class SignupInformation extends StatefulWidget {
  @override
  _SignupInformationState createState() => _SignupInformationState();
}

class _SignupInformationState extends State<SignupInformation> {
  // -------------------------
  // Controllers for TextField
  // -------------------------
  final TextEditingController _usernameController = TextEditingController(); // username input
  final TextEditingController _emailController = TextEditingController();    // email input
  final TextEditingController _contactController = TextEditingController();  // contact input
  final TextEditingController _passwordController = TextEditingController(); // password input
  final TextEditingController _confirmController = TextEditingController();  // confirm password input (NEW)

  // -------------------------
  // Firebase Auth instance
  // -------------------------
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // -------------------------
  // Simple UI states
  // -------------------------
  bool _obscurePassword = true;          // show/hide password
  bool _obscureConfirmPassword = true;   // show/hide confirm password (NEW)
  bool _isTermsAccepted = false;
  bool _isPrivacyAccepted = false;

  // -------------------------
  // Error message strings
  // -------------------------
  String? _usernameError;
  String? _emailError;
  String? _contactError;
  String? _passwordError;
  String? _confirmPasswordError; // (NEW)
  String? _roleError;
  String? _termsError;

  // -------------------------
  // After verification email sent
  // -------------------------
  bool _isVerificationSent = false;

  // Lecturer ID
  final TextEditingController _lecturerIdController = TextEditingController();
  String? _lecturerIdError;

// Image proof preview (bytes + base64)
  Uint8List? _pendingImageBytes;
  String? _pendingBase64;

// Image sizes (same idea as Report Issue)
  static const int _maxBase64Len = 900000;
  static const int _targetMaxWidth = 600;



  // ----------------------------------------
  // Helper: Show an error under a field name
  // ----------------------------------------
  void _showError(String field, String message) {
    // setState = update UI values
    setState(() {
      if (field == "username") {
        _usernameError = message;
      } else if (field == "email") {
        _emailError = message;
      } else if (field == "contact") {
        _contactError = message;
      } else if (field == "password") {
        _passwordError = message;
      } else if (field == "confirm") { // (NEW) support confirm password
        _confirmPasswordError = message;
      } else if (field == "role") {
        _roleError = message;
      } else if (field == "terms") {
        _termsError = message;
      }
    });
  }

  // ----------------------------------------------------
  // Simple password rule: min 8 + 1 uppercase + 1 symbol
  // ----------------------------------------------------
  bool _isPasswordStrong(String password) {
    // RegExp = check pattern
    final regex = RegExp(r'^(?=.*[A-Z])(?=.*[!@#\$%^&*(),.?":{}|<>]).{8,}$');
    if (regex.hasMatch(password)) {
      return true;
    } else {
      return false;
    }
  }
  Future<bool> _usernameExists(String username) async {
    final String u = username.trim();
    if (u.isEmpty) {
      return false;
    }

    try {
      final qs = await FirebaseFirestore.instance
          .collection("UserInformation")
          .where("username", isEqualTo: u)
          .limit(1)
          .get();

      if (qs.docs.isNotEmpty == true) {
        return true;
      } else {
        return false;
      }
    } catch (e) {
      // If the check fails, don't block sign up with a false positive
      return false;
    }
  }

  // ------------------------------------
  // MAIN: Validate form and create user
  // ------------------------------------
  Future<void> _validateAndSignUp() async {
    setState(() {
      _usernameError = null;
      _emailError = null;
      _contactError = null;
      _passwordError = null;
      _confirmPasswordError = null;
      _roleError = null;
      _termsError = null;
      _lecturerIdError = null;
    });

    bool isValid = true;

    // ---- basic field checks ----
    if (_usernameController.text.isEmpty) {
      _showError("username", "Username cannot be empty");
      isValid = false;
    }

    if (_emailController.text.contains("@")) {
      // ok
    } else {
      _showError("email", "Invalid email address");
      isValid = false;
    }

    if (_contactController.text.length == 10) {
      // ok
    } else {
      _showError("contact", "Contact must be exactly 10 digits");
      isValid = false;
    }

    if (_isPasswordStrong(_passwordController.text)) {
      // ok
    } else {
      _showError("password", "Password must be at least 8 characters, include 1 uppercase letter and 1 special character");
      isValid = false;
    }

    if (_confirmController.text.isEmpty) {
      _showError("confirm", "Confirm password cannot be empty");
      isValid = false;
    } else {
      if (_confirmController.text == _passwordController.text) {
        // ok
      } else {
        _showError("confirm", "Passwords do not match");
        isValid = false;
      }
    }

    if (_isTermsAccepted && _isPrivacyAccepted) {
      // ok
    } else {
      _showError("terms", "Please accept all agreements");
      isValid = false;
    }

    // ---- NEW: lecturer-specific checks BEFORE Auth creation ----
    if (_lecturerIdController.text.trim().isEmpty) {
      _lecturerIdError = "Lecturer ID cannot be empty";
      isValid = false;
    } else {
      _lecturerIdError = null;
    }

    if (_pendingBase64 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please attach your proof image.', style: TextStyle(fontSize: 14.sp))),
      );
      isValid = false;
    }

    // If anything failed so far, stop here
    if (isValid == false) {
      setState(() {});
      return;
    }

    // ---- NEW: username uniqueness check ----
    final bool taken = await _usernameExists(_usernameController.text);
    if (taken == true) {
      _showError("username", "Username already taken");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Username already taken.', style: TextStyle(fontSize: 14.sp))),
      );
      setState(() {});
      return;
    }

    // ---- Create Firebase Auth user (unchanged) ----
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      User? user = userCredential.user;

      if (user != null) {
        if (user.emailVerified == false) {
          await user.sendEmailVerification();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Verification email sent. Please check your inbox.', style: TextStyle(fontSize: 14.sp))),
          );

          setState(() { _isVerificationSent = true; });
        } else {
          await _writeUserToFirestoreAndGo(user);
        }
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        _showError("email", "Email already registered");
        setState(() {});
      } else {
        _showFailDialog();
      }
    } catch (e) {
      _showFailDialog();
    }
  }


  // ------------------------------------------------------------
  // Called when user presses "I already verified, continue" button
  // ------------------------------------------------------------
  Future<void> _checkEmailVerified() async {
    User? user = _auth.currentUser;

    if (user != null) {
      // Reload the user to get the latest emailVerified state
      await user.reload();
      user = _auth.currentUser;

      if (user != null) {
        if (user.emailVerified == true) {
          // Email is verified now, write Firestore and go
          await _writeUserToFirestoreAndGo(user);
        } else {
          // Not verified yet
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Email not verified yet. Please check your inbox.', style: TextStyle(fontSize: 14.sp))),
          );
        }
      } else {
        // No user in auth
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No user found. Please sign up again.', style: TextStyle(fontSize: 14.sp))),
        );
      }
    } else {
      // No user in auth
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No user found. Please sign up again.', style: TextStyle(fontSize: 14.sp))),
      );
    }
  }

  // ----------------------------------------------------
  // Write the user document to Firestore (first time),
  // set isVerified: true, and navigate to Facilities.
  // ----------------------------------------------------
  Future<void> _writeUserToFirestoreAndGo(User user) async {
    String proofB64 = '';
    if (_pendingBase64 != null) {
      proofB64 = _pendingBase64!;
    }

    try {
      final Map<String, dynamic> data = {
        "username": _usernameController.text.trim(),
        "email": _emailController.text.trim(),
        "contact": _contactController.text.trim(),
        "role": 'Lecturer',
        "isVerified": true,
        "notifAll": true,
        "notifApprovalBook": true,
        "notifNewBook": true,
        "notifReminder": true,
        "notifUpdatedBook": true,
        "profileImageName": null,
        "lecturerId": _lecturerIdController.text.trim(),
        "proofImageBase64": proofB64,
        "deleted": false,
        "active": false,
        "approval": false,
        "inboxLastSeen": FieldValue.serverTimestamp(),
        "createdAt": FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection("UserInformation")
          .doc(user.uid)
          .set(data);

      if (!mounted) return;

      // Notify, then SIGN OUT the lecturer
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Email verified! Account created.', style: TextStyle(fontSize: 14.sp))),
      );

      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      // Go to Login and clear back stack
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => AndroidLoginPage()),
            (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save account. Please try again.', style: TextStyle(fontSize: 14.sp))),
      );
    }
  }

  // --------------------------------------------
  // Resend verification email if user requests
  // --------------------------------------------
  Future<void> resendVerificationEmail() async {
    try {
      User? user = _auth.currentUser;

      if (user != null) {
        if (user.emailVerified == false) {
          await user.sendEmailVerification();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Verification email sent!", style: TextStyle(fontSize: 14.sp))),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Email is already verified.", style: TextStyle(fontSize: 14.sp))),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No user found.", style: TextStyle(fontSize: 14.sp))),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send verification email.", style: TextStyle(fontSize: 14.sp))),
      );
    }
  }

  // --------------------------
  // Simple "Fail" popup dialog
  // --------------------------
  void _showFailDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Sign Up Failed", style: TextStyle(fontSize: 16.sp)),
        content: Text("Please check your input and try again.", style: TextStyle(fontSize: 14.sp)),
        actions: [
          TextButton(
            onPressed: () {
              // Close dialog
              Navigator.pop(context);
            },
            child: Text("OK", style: TextStyle(fontSize: 14.sp)),
          ),
        ],
      ),
    );
  }
  // Open Terms & Conditions page (no login required)
  void _openTncPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AndroidTNC()),
    );
  }

// Open Privacy Policy page (no login required)
  void _openPrivacyPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AndroidPrivacyPolicy()),
    );
  }

  void _openSignupStudentPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AndroidSignUpPage()),
    );
  }
  Future<void> _pickResizePreviewImage() async {
    try {
      final FilePickerResult? res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
        allowMultiple: false,
        withData: true,
      );

      if (res == null) return;
      if (res.files.isEmpty) return;

      final PlatformFile file = res.files.single;
      Uint8List? raw = file.bytes;

      if (raw == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("This image cannot be read. Please pick a different one.", style: TextStyle(fontSize: 12.sp))),
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

      img.Image toEncode;
      if (decoded.width > _targetMaxWidth) {
        toEncode = img.copyResize(decoded, width: _targetMaxWidth, interpolation: img.Interpolation.average);
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
          if (quality < 40) {
            await _showTooLargeDialog();
            return;
          }
        }
      }

      setState(() {
        _pendingImageBytes = finalBytes;
        _pendingBase64 = finalB64;
      });

    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Picking/compressing failed", style: TextStyle(fontSize: 12.sp))),
      );
    }
  }

  void _clearPendingImage() {
    setState(() {
      _pendingImageBytes = null;
      _pendingBase64 = null;
    });
  }

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

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _lecturerIdController.dispose(); // <-- add this
    super.dispose();
  }

  // -----------------------------------------
  // BUILD: Draw the Sign Up form to the screen
  // -----------------------------------------
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 20.h),

        // Card-like container for the form
        Container(
          width: 0.9.sw,
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            color: Color(0xFFFDF9F9),
            borderRadius: BorderRadius.circular(10.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                offset: Offset(0, 4),
              ),
            ],
          ),

          // The actual form fields
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Username
              Text("Username", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(border: OutlineInputBorder()),
              ),
              if (_usernameError != null)
                Text(_usernameError!, style: TextStyle(color: Colors.red, fontSize: 12.sp)),
              SizedBox(height: 20.h),

              // Email
              Text("Email", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(border: OutlineInputBorder()),
              ),
              if (_emailError != null)
                Text(_emailError!, style: TextStyle(color: Colors.red, fontSize: 12.sp)),
              SizedBox(height: 20.h),

              // Contact Number (digits only)
              Text("Contact Number", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              TextField(
                controller: _contactController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(border: OutlineInputBorder()),
              ),
              if (_contactError != null)
                Text(_contactError!, style: TextStyle(color: Colors.red, fontSize: 12.sp)),
              SizedBox(height: 20.h),

              // Password
              Text("Password", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword, // hide/show password
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () {
                      // Toggle obscureText using if/else
                      if (_obscurePassword == true) {
                        setState(() {
                          _obscurePassword = false;
                        });
                      } else {
                        setState(() {
                          _obscurePassword = true;
                        });
                      }
                    },
                  ),
                ),
              ),
              if (_passwordError != null)
                Text(_passwordError!, style: TextStyle(color: Colors.red, fontSize: 12.sp)),
              SizedBox(height: 20.h), // spacing before Confirm Password (NEW)

              // -------------------------
              // (NEW) Confirm Password
              // -------------------------
              Text("Confirm Password", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              TextField(
                controller: _confirmController,
                obscureText: _obscureConfirmPassword, // hide/show confirm password
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () {
                      // Toggle confirm obscure using if/else
                      if (_obscureConfirmPassword == true) {
                        setState(() {
                          _obscureConfirmPassword = false;
                        });
                      } else {
                        setState(() {
                          _obscureConfirmPassword = true;
                        });
                      }
                    },
                  ),
                ),
              ),
              if (_confirmPasswordError != null)
                Text(_confirmPasswordError!, style: TextStyle(color: Colors.red, fontSize: 12.sp)),
              SizedBox(height: 20.h),


// ---------- Lecturer ID ----------
              Text("Lecturer ID", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              TextField(
                controller: _lecturerIdController,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              if (_lecturerIdError != null)
                Text(_lecturerIdError!, style: TextStyle(color: Colors.red, fontSize: 12.sp)),

              SizedBox(height: 20.h),

// ---------- Proof Image ----------
              Text("Proof", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 8.h),
              Row(
                children: [
                  IconButton(
                    onPressed: null, // disabled (use the box below)
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
              Center(
                child: GestureDetector(
                  onTap: _pickResizePreviewImage,
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
                                Text("Tap to pick image", style: TextStyle(fontSize: 12.sp, color: Colors.black54)),
                              ],
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
              SizedBox(height:20.h),
              Align(
                alignment: Alignment.center,
                child:
                GestureDetector(
                  onTap: _openSignupStudentPage,
                  child: Text(
                    "Sign up as Student?",
                    style: TextStyle(decoration: TextDecoration.underline, fontSize: 14.sp),
                  ),
                ),

              ),


              SizedBox(height:20.h),

              // Agreements
              CheckboxListTile(
                value: _isTermsAccepted,
                onChanged: (value) {
                  if (value == true) {
                    setState(() {
                      _isTermsAccepted = true;
                    });
                  } else {
                    setState(() {
                      _isTermsAccepted = false;
                    });
                  }
                },
                // Terms and Conditions checkbox title
                title: GestureDetector(
                  onTap: _openTncPage, // open T&C page
                  child: Text(
                    "Terms and Conditions",
                    style: TextStyle(decoration: TextDecoration.underline, color: Colors.blue, fontSize: 14.sp),
                  ),
                ),

              ),
              CheckboxListTile(
                value: _isPrivacyAccepted,
                onChanged: (value) {
                  if (value == true) {
                    setState(() {
                      _isPrivacyAccepted = true;
                    });
                  } else {
                    setState(() {
                      _isPrivacyAccepted = false;
                    });
                  }
                },
                // Privacy Policy checkbox title
                title: GestureDetector(
                  onTap: _openPrivacyPage, // open Privacy Policy page
                  child: Text(
                    "Privacy Policy",
                    style: TextStyle(decoration: TextDecoration.underline, color: Colors.blue, fontSize: 14.sp),
                  ),
                ),

              ),
              if (_termsError != null)
                Text(_termsError!, style: TextStyle(color: Colors.red, fontSize: 12.sp)),

              SizedBox(height: 20.h),

              // If verification email not sent yet → show "Sign Up" button
              if (_isVerificationSent == false)
                Center(
                  child: SizedBox(
                    width: 0.3.sw,
                    height: 55.h,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF8620E5)),
                      onPressed: _validateAndSignUp, // create auth user and send verify email
                      child: Text(
                        "Sign Up",
                        style: TextStyle(color: Colors.white, fontSize: 14.sp),
                      ),
                    ),
                  ),
                )
              else
              // If verification email sent → show the verification actions
                Center(
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8.w),
                        child: Text(
                          "A verification email has been sent. Please check your inbox and click the link to verify your email.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16.sp),
                        ),
                      ),
                      SizedBox(height: 20.h),
                      SizedBox(
                        width: 0.9.sw, // wider so it fits on one line
                        height: 55.h,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8620E5)),
                          onPressed: _checkEmailVerified,
                          child: Text(
                            "I have verified. Continue",
                            maxLines: 1,                // force single line
                            overflow: TextOverflow.clip, // don’t wrap
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.sp,
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: 10.h),
                      TextButton(
                        onPressed: resendVerificationEmail, // resend verify email
                        child: Text("Resend Verification Email", style: TextStyle(fontSize: 14.sp)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// -----------------
// Dummy Terms Page
// -----------------

class TermsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Simple page with text only
    return Scaffold(
      appBar: AppBar(title: Text("Terms & Conditions")),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Text("Here are the terms and conditions..."),
      ),
    );
  }
}
