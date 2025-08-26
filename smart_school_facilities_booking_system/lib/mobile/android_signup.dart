// ------------------------------
// ANDROID SIGN UP PAGE (SIMPLE)
// ------------------------------

// Import = bring in packages we need for this file
import 'package:cloud_firestore/cloud_firestore.dart';               // Firestore database
import 'package:firebase_auth/firebase_auth.dart';                   // Firebase Authentication (sign up / login)
import 'package:flutter/material.dart';                              // Flutter UI
import 'package:flutter/services.dart';                              // For FilteringTextInputFormatter (digits only)
import 'package:flutter_screenutil/flutter_screenutil.dart';         // For .w .h .sp responsive sizes

// These are your other screens/files
import 'android_login.dart';                                         // Your Android Login page
import 'android_list_of_facilities.dart';

// --------------
// Main Page UI
// --------------

// A simple page that shows a header and the sign up form
class AndroidSignUpPage extends StatelessWidget {
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
  // TextEditingController = read text from TextFields
  final TextEditingController _usernameController = TextEditingController(); // username input
  final TextEditingController _emailController = TextEditingController();    // email input
  final TextEditingController _contactController = TextEditingController();  // contact input
  final TextEditingController _passwordController = TextEditingController(); // password input

  // FirebaseAuth instance = we use this to create account and send verify email
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Local UI states
  bool _obscurePassword = true; // show/hide password
  String? _selectedRole;        // Student or Lecturer
  bool _isTermsAccepted = false;
  bool _isPrivacyAccepted = false;

  // Error message strings (show under each field)
  String? _usernameError;
  String? _emailError;
  String? _contactError;
  String? _passwordError;
  String? _roleError;
  String? _termsError;

  // After we send verification email, we show the "I have verified" button
  bool _isVerificationSent = false;

  // -------------------------
  // Open Terms Page (dummy)
  // -------------------------
  void _openTermsPage() {
    // Navigator.push = go to another page
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => TermsPage()),
    );
  }

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

  // ------------------------------------
  // MAIN: Validate form and create user
  // ------------------------------------
  Future<void> _validateAndSignUp() async {
    // Reset old errors
    setState(() {
      _usernameError = null;
      _emailError = null;
      _contactError = null;
      _passwordError = null;
      _roleError = null;
      _termsError = null;
    });

    // Assume valid first, then check each rule
    bool isValid = true;

    // Check username not empty
    if (_usernameController.text.isEmpty) {
      _showError("username", "Username cannot be empty");
      isValid = false;
    }

    // Check email has @
    if (_emailController.text.contains("@")) {
      // ok
    } else {
      _showError("email", "Invalid email address");
      isValid = false;
    }

    // Check contact exactly 10 digits
    if (_contactController.text.length == 10) {
      // ok
    } else {
      _showError("contact", "Contact must be exactly 10 digits");
      isValid = false;
    }

    // Check password strength
    if (_isPasswordStrong(_passwordController.text)) {
      // ok
    } else {
      _showError("password", "Password must be at least 8 characters, include 1 uppercase letter and 1 special character");
      isValid = false;
    }

    // Check role selected (Student or Lecturer)
    if (_selectedRole == null) {
      _showError("role", "Please select a role");
      isValid = false;
    } else {
      if (_selectedRole == "Student" || _selectedRole == "Lecturer") {
        // ok
      } else {
        _showError("role", "Invalid role");
        isValid = false;
      }
    }

    // Check terms + privacy ticked
    if (_isTermsAccepted && _isPrivacyAccepted) {
      // ok
    } else {
      _showError("terms", "Please accept all agreements");
      isValid = false;
    }

    // If anything is invalid, stop here
    if (isValid == false) {
      setState(() {}); // refresh UI to show errors
      return;
    }

    // Try to create Firebase Auth user
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      User? user = userCredential.user;

      if (user != null) {
        // If email is not yet verified, send verification email
        if (user.emailVerified == false) {
          await user.sendEmailVerification();

          // Show a small message to user (Snackbar)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Verification email sent. Please check your inbox.')),
          );

          // Show the "I already verified" button on screen
          setState(() {
            _isVerificationSent = true;
          });
        } else {
          // Edge case: if already verified (rare), go write Firestore and go to facilities
          await _writeUserToFirestoreAndGo(user);
        }
      }
    } on FirebaseAuthException catch (e) {
      // Handle some common errors
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

  // ------------------------------------------------------------
  // Called when user presses "I already verified, continue" button
  // This reloads the Firebase user, checks verification, then:
  // - writes the Firestore document
  // - sets isVerified: true (because email is verified now)
  // - navigates to AndroidListOfFacilities
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
            SnackBar(content: Text('Email not verified yet. Please check your inbox.')),
          );
        }
      } else {
        // No user in auth
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No user found. Please sign up again.')),
        );
      }
    } else {
      // No user in auth
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No user found. Please sign up again.')),
      );
    }
  }

  // ----------------------------------------------------
  // Write the user document to Firestore (first time),
  // set isVerified: true, and navigate to Facilities.
  // ----------------------------------------------------
  Future<void> _writeUserToFirestoreAndGo(User user) async {
    try {
      // Prepare the user document data
      Map<String, dynamic> data = {
        "username": _usernameController.text.trim(),
        "email": _emailController.text.trim(),
        "contact": _contactController.text.trim(),
        "role": _selectedRole,                  // "Student" or "Lecturer"
        "isVerified": true,                     // set TRUE now (verified already)
        "notifAll": true,                       // your extra flags
        "notifSuccessfulBook": true,
        "notifFailedBook": true,
        "notifReminder": true,
        "profileImageName": null,               // string null for now
        "createdAt": FieldValue.serverTimestamp(),
      };

      // Write with .set() to create/overwrite doc under "UserInformation/{uid}"
      await FirebaseFirestore.instance
          .collection("UserInformation")
          .doc(user.uid)
          .set(data);

      // Tell user verification success
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Email verified! Account created.')),
      );

      // Go straight to Facilities page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AndroidListOfFacilities()),
      );
    } catch (e) {
      // If Firestore write fails, show message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save account. Please try again.')),
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
            SnackBar(content: Text("Verification email sent!")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Email is already verified.")),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("No user found.")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to send verification email.")),
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
        title: Text("Sign Up Failed"),
        content: Text("Please check your input and try again."),
        actions: [
          TextButton(
            onPressed: () {
              // Close dialog
              Navigator.pop(context);
            },
            child: Text("OK"),
          ),
        ],
      ),
    );
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
                Text(_usernameError!, style: TextStyle(color: Colors.red)),
              SizedBox(height: 20.h),

              // Email
              Text("Email", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(border: OutlineInputBorder()),
              ),
              if (_emailError != null)
                Text(_emailError!, style: TextStyle(color: Colors.red)),
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
                Text(_contactError!, style: TextStyle(color: Colors.red)),
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
                Text(_passwordError!, style: TextStyle(color: Colors.red)),
              SizedBox(height: 20.h),

              // Role Selection
              Text("Select Role", style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              RadioListTile<String>(
                title: Text("Student"),
                value: "Student",
                groupValue: _selectedRole,
                onChanged: (value) {
                  setState(() {
                    _selectedRole = value; // set role to Student
                  });
                },
              ),
              RadioListTile<String>(
                title: Text("Lecturer"),
                value: "Lecturer",
                groupValue: _selectedRole,
                onChanged: (value) {
                  setState(() {
                    _selectedRole = value; // set role to Lecturer
                  });
                },
              ),
              if (_roleError != null)
                Text(_roleError!, style: TextStyle(color: Colors.red)),

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
                title: GestureDetector(
                  onTap: _openTermsPage,
                  child: Text(
                    "Terms and Conditions",
                    style: TextStyle(decoration: TextDecoration.underline, color: Colors.blue),
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
                title: GestureDetector(
                  onTap: _openTermsPage,
                  child: Text(
                    "Privacy Policy",
                    style: TextStyle(decoration: TextDecoration.underline, color: Colors.blue),
                  ),
                ),
              ),
              if (_termsError != null)
                Text(_termsError!, style: TextStyle(color: Colors.red)),

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
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                )
              else
              // If verification email sent → show the verification actions
                Center(
                  child: Column(
                    children: [
                      Text(
                        "A verification email has been sent. Please check your inbox and click the link to verify your email.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                      SizedBox(height: 20.h),
                      SizedBox(
                        width: 0.4.sw,
                        height: 55.h,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF8620E5)),
                          onPressed: _checkEmailVerified, // check if verified, then write Firestore, then go
                          child: Text(
                            "I have verified. Continue",
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      SizedBox(height: 10.h),
                      TextButton(
                        onPressed: resendVerificationEmail, // resend verify email
                        child: Text("Resend Verification Email"),
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
