import 'package:cloud_firestore/cloud_firestore.dart';               // Firestore database
import 'package:firebase_auth/firebase_auth.dart';                   // Firebase Authentication (sign up / login)
import 'package:flutter/material.dart';                              // Flutter UI
import 'package:flutter/services.dart';                              // For FilteringTextInputFormatter (digits only)
import 'package:flutter_screenutil/flutter_screenutil.dart';         // For .w .h .sp responsive sizes

import 'android_login.dart';                                         // Your Android Login page
import 'android_list_of_facilities.dart';
import 'android_lecturersignup.dart';
import 'android_tnc.dart';
import 'android_privacy_policy.dart';

class AndroidSignUpPage extends StatelessWidget {
//---------------------------------------
// main build
//---------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            GradientHeader(), //gradient top header
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
              child: SignupInformation(),
            ),
          ],
        ),
      ),
    );
  }
}

//---------------------------------------
// gradient header
//---------------------------------------

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
//---------------------------------------
// show log in and sign up navigation button
//---------------------------------------
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () {
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
              ElevatedButton(
                onPressed: () {
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

//---------------------------------------
// sign up information
//---------------------------------------

class SignupInformation extends StatefulWidget {
  @override
  _SignupInformationState createState() => _SignupInformationState();
}

class _SignupInformationState extends State<SignupInformation> {

  final TextEditingController _usernameController = TextEditingController(); // username input
  final TextEditingController _emailController = TextEditingController();    // email input
  final TextEditingController _contactController = TextEditingController();  // contact input
  final TextEditingController _passwordController = TextEditingController(); // password input
  final TextEditingController _confirmController = TextEditingController();  // confirm password input

  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool _obscurePassword = true;          // show/hide password
  bool _obscureConfirmPassword = true;   // show/hide confirm password
  bool _isTermsAccepted = false;
  bool _isPrivacyAccepted = false;

  String? _usernameError;
  String? _emailError;
  String? _contactError;
  String? _passwordError;
  String? _confirmPasswordError;
  String? _roleError;
  String? _termsError;

  bool _isVerificationSent = false;

  //---------------------------------------
// show error message
//---------------------------------------

  void _showError(String field, String message) {
    setState(() {
      if (field == "username") {
        _usernameError = message;
      } else if (field == "email") {
        _emailError = message;
      } else if (field == "contact") {
        _contactError = message;
      } else if (field == "password") {
        _passwordError = message;
      } else if (field == "confirm") {
        _confirmPasswordError = message;
      } else if (field == "role") {
        _roleError = message;
      } else if (field == "terms") {
        _termsError = message;
      }
    });
  }

//---------------------------------------
// strong password
//---------------------------------------
  bool _isPasswordStrong(String password) {
    // RegExp = check pattern
    final regex = RegExp(r'^(?=.*[A-Z])(?=.*[!@#\$%^&*(),.?":{}|<>]).{8,}$');
    if (regex.hasMatch(password)) {
      return true;
    } else {
      return false;
    }
  }

//---------------------------------------
// sign up process
//---------------------------------------
  Future<void> _onSignUp() async {
//---------------------------------------
// clear previous error
//---------------------------------------
    setState(() {
      _usernameError = null;
      _emailError = null;
      _contactError = null;
      _passwordError = null;
      _confirmPasswordError = null; // (NEW)
      _roleError = null;
      _termsError = null;
    });

    bool isValid = true;

//---------------------------------------
// check username
//---------------------------------------
    if (_usernameController.text.isEmpty) {
      _showError("username", "Username cannot be empty");
      isValid = false;
    }
//---------------------------------------
// check email
//---------------------------------------
    if (_emailController.text.contains("@")) {
    } else {
      _showError("email", "Invalid email address");
      isValid = false;
    }
//---------------------------------------
// check contact
//---------------------------------------
    if (_contactController.text.length == 10) {
    } else {
      _showError("contact", "Contact must be exactly 10 digits");
      isValid = false;
    }
//---------------------------------------
// check strong password
//---------------------------------------
    if (_isPasswordStrong(_passwordController.text)) {
    } else {
      _showError("password", "Password must be at least 8 characters, "
          "include 1 uppercase letter and 1 special character");
      isValid = false;
    }
//---------------------------------------
// check confrim password
//---------------------------------------
    if (_confirmController.text.isEmpty) {
      _showError("confirm", "Confirm password cannot be empty");
      isValid = false;
    } else {
      if (_confirmController.text == _passwordController.text) {
      } else {
        _showError("confirm", "Passwords do not match");
        isValid = false;
      }
    }

//---------------------------------------
// check tnc
//---------------------------------------
    if (_isTermsAccepted && _isPrivacyAccepted) {
    } else {
      _showError("terms", "Please accept all agreements");
      isValid = false;
    }

//---------------------------------------
// if not valid refresh UI to show error
//---------------------------------------

    if (isValid == false) {
      setState(() {});
      return;
    }
    //---------------------------------------
// check if username exist
//---------------------------------------
    final bool taken = await _usernameExists(_usernameController.text);
    if (taken == true) {
      _showError("username", "Username already taken");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Username already taken.', style: TextStyle(fontSize: 14.sp))),
      );
      setState(() {});
      return;
    }
//---------------------------------------
// create new user
//---------------------------------------

    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      User? user = userCredential.user;
      if (user != null) {
//---------------------------------------
// if email still not yet varified
//---------------------------------------
        if (user.emailVerified == false) {
          await user.sendEmailVerification();
//---------------------------------------
// when verification send show pop up
//---------------------------------------
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Verification email sent. Please check your inbox.',
                style: TextStyle(fontSize: 14.sp))),
          );

//---------------------------------------
// show verified button
//---------------------------------------
          setState(() {
            _isVerificationSent = true;
          });
        } else {
//---------------------------------------
// write data to firebase
//---------------------------------------

          await _writeUserToFirestoreAndGo(user);
        }
      }
//---------------------------------------
// show error if email already in used
//---------------------------------------

    } on FirebaseAuthException catch (e) {

      if (e.code == 'email-already-in-use') {
        _showError("email", "Email already registered");
        setState(() {});
      } else {
        _showFailDialog();
      }
    } catch (e) {
      // Any other error
      _showFailDialog();
    }
  }

//---------------------------------------
// check if user name exist
//---------------------------------------
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
      return false;
    }
  }

//---------------------------------------
// check email verification already press or not
//---------------------------------------

  Future<void> _checkEmailVerified() async {
    User? user = _auth.currentUser;

    if (user != null) {
      await user.reload();
      user = _auth.currentUser;

      if (user != null) {
        if (user.emailVerified == true) {
//---------------------------------------
// write user to firebase
//---------------------------------------
          await _writeUserToFirestoreAndGo(user);
        } else {

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Email not verified yet. Please check your inbox.',
                style: TextStyle(fontSize: 14.sp))),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No user found. Please sign up again.', style: TextStyle(fontSize: 14.sp))),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No user found. Please sign up again.', style: TextStyle(fontSize: 14.sp))),
      );
    }
  }

//---------------------------------------
// create new user
//---------------------------------------

  Future<void> _writeUserToFirestoreAndGo(User user) async {
    try {

      Map<String, dynamic> data = {
        "username": _usernameController.text.trim(),
        "email": _emailController.text.trim(),
        "contact": _contactController.text.trim(),
        "role": 'Student',
        "isVerified": true,
        "notifAll": true,
        "notifApprovalBook": true,
        "notifNewBook": true,
        "notifReminder": true,
        "notifUpdatedBook": true,
        "profileImageName": null,
        "deleted": false,
        "active": true,
        "approval": true,
        "inboxLastSeen": FieldValue.serverTimestamp(),
        "createdAt": FieldValue.serverTimestamp(),
      };

//---------------------------------------
// set the new data into firebase
//---------------------------------------

      await FirebaseFirestore.instance
          .collection("UserInformation")
          .doc(user.uid)
          .set(data);

//---------------------------------------
// show verified success
//---------------------------------------

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Email verified! Account created.', style: TextStyle(fontSize: 14.sp))),
      );

//---------------------------------------
// got to facility page
//---------------------------------------

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AndroidListOfFacilities()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save account. Please try again.', style: TextStyle(fontSize: 14.sp))),
      );
    }
  }

//---------------------------------------
// resend verification email
//---------------------------------------

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

//---------------------------------------
// show pop up if sign up fail
//---------------------------------------

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
//---------------------------------------
// open tnc page
//---------------------------------------

  void _openTncPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AndroidTNC()),
    );
  }

//---------------------------------------
// open pp page
//---------------------------------------
  void _openPrivacyPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AndroidPrivacyPolicy()),
    );
  }
//---------------------------------------
// go to sign up lecturer page
//---------------------------------------

  void _openSignupLecturerPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LecturerSignup()),
    );
  }


//---------------------------------------
// build for sign up form
//---------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 20.h),

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

//---------------------------------------
// user name text box
//---------------------------------------

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

//---------------------------------------
// email text box
//---------------------------------------

              Text("Email", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(border: OutlineInputBorder()),
              ),
              if (_emailError != null)
                Text(_emailError!, style: TextStyle(color: Colors.red, fontSize: 12.sp)),
              SizedBox(height: 20.h),

//---------------------------------------
// contact number text box
//---------------------------------------

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

//---------------------------------------
// password text box
//---------------------------------------

              Text("Password", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword, // hide/show password
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () {
                      // Toggle obscureText
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

//---------------------------------------
// confirm password text box
//---------------------------------------

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
//---------------------------------------
// sign up as lecturer button
//---------------------------------------
              Align(
                alignment: Alignment.center,
                child:
                GestureDetector(
                  onTap: _openSignupLecturerPage,
                  child: Text(
                    "Sign up as Lecturer?",
                    style: TextStyle(decoration: TextDecoration.underline, fontSize: 14.sp),
                  ),
                ),
                ),

              SizedBox(height:20.h),
//---------------------------------------
// tnc check box
//---------------------------------------
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
                title: GestureDetector(
                  onTap: _openTncPage,
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
//---------------------------------------
// pp text box
//---------------------------------------
                title: GestureDetector(
                  onTap: _openPrivacyPage,
                  child: Text(
                    "Privacy Policy",
                    style: TextStyle(decoration: TextDecoration.underline, color: Colors.blue, fontSize: 14.sp),
                  ),
                ),
              ),
              if (_termsError != null)
                Text(_termsError!, style: TextStyle(color: Colors.red, fontSize: 12.sp)),

              SizedBox(height: 20.h),

//---------------------------------------
// email verification still not sent , show sign up button
//---------------------------------------
              if (_isVerificationSent == false)
                Center(
                  child: SizedBox(
                    width: 0.3.sw,
                    height: 55.h,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF8620E5)),
                      onPressed: _onSignUp,
                      child: Text(
                        "Sign Up",
                        style: TextStyle(color: Colors.white, fontSize: 14.sp),
                      ),
                    ),
                  ),
                )
              else
//---------------------------------------
// if not, show verification button
//---------------------------------------
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
                        width: 0.9.sw,
                        height: 55.h,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8620E5)),
                          onPressed: _checkEmailVerified,
                          child: Text(
                            "I have verified",
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14.sp,
                            ),
                          ),
                        ),
                      ),
//---------------------------------------
// then below show resent verification email button
//---------------------------------------
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
