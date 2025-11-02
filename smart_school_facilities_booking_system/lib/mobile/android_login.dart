import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'android_signup.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'android_list_of_facilities.dart';


class AndroidLoginPage extends StatelessWidget {
  //---------------------------------------
// main build
//---------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            GradientHeader(),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
              child: LoginInformation(),
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
    double screenWidth = MediaQuery.of(context).size.width;

    return Container(
      width: screenWidth,
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 30.h),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40.r),
          bottomRight: Radius.circular(40.r),
        ),
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
          Row(
 //---------------------------------------
// log in page and sign up page navigate button
//---------------------------------------
          mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 12.h),
                ),
                child: Text('Log In', style: TextStyle(fontSize: 14.sp)),
              ),
              SizedBox(width: 20.w),
              OutlinedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => AndroidSignUpPage()),
                  );
                },
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 35.w, vertical: 12.h),
                  side: BorderSide(color: Colors.white),
                  foregroundColor: Colors.white,
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

class LoginInformation extends StatefulWidget {
  @override
  _LoginInformationState createState() => _LoginInformationState();
}

class _LoginInformationState extends State<LoginInformation> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  String? _errorMessage;

//---------------------------------------
// log in proccess
//---------------------------------------
  Future<void> loginUser(BuildContext context, String emailOrUsername, String password) async {
    setState(() { _errorMessage = null; });
//---------------------------------------
// check if it is empty
//---------------------------------------
    String loginEmail = emailOrUsername.trim();
    if (loginEmail.isEmpty || password.isEmpty) {
      setState(() { _errorMessage = "Please enter your email/username and password"; });
      return;
    }
//---------------------------------------
// if it is user name
//---------------------------------------
    if (!loginEmail.contains('@')) {
      final String? resolved = await _getEmailByUsername(loginEmail);
      if (resolved == null) {
        setState(() { _errorMessage = "Incorrect email/username or password"; });
        return;
      }
      loginEmail = resolved;
    } else {
//---------------------------------------
// get user using email
//---------------------------------------

      final doc = await _getUserDocByEmail(loginEmail);
      if (doc == null) {
        setState(() { _errorMessage = "Incorrect email/username or password"; });
        return;
      }
      final data = doc.data();
      if (data != null && data['deleted'] == true) {
        setState(() { _errorMessage = "Incorrect email/username or password"; });
        return;
      }
    }

//---------------------------------------
// get the user doc again
//---------------------------------------
    final DocumentSnapshot<Map<String, dynamic>>? preDoc = await _getUserDocByEmail(loginEmail);
    if (preDoc == null) {
      setState(() { _errorMessage = "Incorrect email/username or password"; });
      return;
    }
    final Map<String, dynamic> pre = preDoc.data() ?? <String, dynamic>{};
    final bool isDeleted = pre['deleted']  == true;
    final bool isActive  = pre['active']   == true;
    final bool approval  = pre['approval'] == true;

    //---------------------------------------
// when user is deleted
//---------------------------------------

    if (isDeleted) {
      setState(() { _errorMessage = "Incorrect email/username or password"; });
      return;
    }

//---------------------------------------
// when user getting rejected
//---------------------------------------

    if (approval && !isActive) {

      final data = pre['rejectDetails'];
      final reason = (data is String ? data.trim() : '');
      final display = reason.isEmpty ? '-' : reason;

      setState(() {
        _errorMessage =
        "This account has been rejected by Admin.\nReason: $display";
      });
      return;
    }

//---------------------------------------
// when havent approve by admin
//---------------------------------------

    if (!approval && !isActive) {
      setState(() { _errorMessage = "Login failed. This account hasn’t been approved by Admin."; });
      return;
    }
//---------------------------------------
// if weird thing happend
//---------------------------------------
    if (!(approval && isActive)) {
      setState(() { _errorMessage = "Login failed. Please contact admin."; });
      return;
    }

    //---------------------------------------
// log in proccess
//---------------------------------------

    try {
      final UserCredential cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: loginEmail, password: password);

      final User? u = cred.user;
      if (u == null) {
        setState(() { _errorMessage = "Login failed. Please try again."; });
        return;
      }

//---------------------------------------
// when success
//---------------------------------------

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login successful')));
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));

      //---------------------------------------
// when there is problem while sing in
//---------------------------------------
    } on FirebaseAuthException catch (e) {
      String message = "Incorrect email/username or password";
      if (e.code == 'invalid-email') message = "Invalid email format";
      else if (e.code == 'user-not-found') message = "No user found";
      else if (e.code == 'wrong-password') message = "Incorrect password";
      else if (e.code == 'too-many-requests') message = "Too many attempts. Try later.";
      setState(() { _errorMessage = message; });
    } catch (_) {
      setState(() { _errorMessage = "Login failed. Please try again."; });
    }
  }

//---------------------------------------
// get username email
//---------------------------------------

  Future<String?> _getEmailByUsername(String username) async {
    try {
      final String u = username.trim();
      if (u.isEmpty) return null;

      final qs = await FirebaseFirestore.instance
          .collection('UserInformation')
          .where('username', isEqualTo: u)
          .limit(1)
          .get();

      if (qs.docs.isEmpty) return null;

      final data = qs.docs.first.data();

      if (data['deleted'] == true) return null;

      final dynamic v = data['email'];
      if (v == null) return null;
      final String email = v.toString().trim();
      return email.isEmpty ? null : email;
    } catch (_) {
      return null;
    }
  }

//---------------------------------------
// see if email exist
//---------------------------------------

  Future<DocumentSnapshot<Map<String, dynamic>>?> _getUserDocByEmail(String email) async {
    try {
      final String e = email.trim();
      if (e.isEmpty) return null;

      final qs = await FirebaseFirestore.instance
          .collection('UserInformation')
          .where('email', isEqualTo: e)
          .limit(1)
          .get();

      if (qs.docs.isEmpty) return null;
      return qs.docs.first;
    } catch (_) {
      return null;
    }
  }

//---------------------------------------
// main build
//---------------------------------------

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 20.h),
        Center(
          child: Image.asset(
            'asset/image/fyp_logo.png',
            width: 171.w,
            height: 134.h,
          ),
        ),
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
// error box
//---------------------------------------

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_errorMessage != null)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(10.w),
                  margin: EdgeInsets.only(bottom: 15.h),
                  decoration: BoxDecoration(
                    color: Color(0xFFFCC2CF),
                    border: Border.all(color: Color(0xFFFF0707), width: 1.5),
                    borderRadius: BorderRadius.circular(5.r),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Color(0xFFFF0707),
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
//---------------------------------------
// show email text box
//---------------------------------------
              Text("Email / Username",
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 8.h),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: "Enter email / username",
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 20.h),
//---------------------------------------
// pass word
//---------------------------------------
              Text("Password",
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 8.h),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: "Enter your password",
                  border: OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      size: 24.w,
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () async {
                    final email = _emailController.text.trim();

                    if (email.isEmpty) {
                      setState(() {
                        _errorMessage = "Please enter your email first";
                      });
                      return;
                    }
//---------------------------------------
// sent reset password
//---------------------------------------
                    try {
                      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Password reset email sent to $email')),
                      );
                    } on FirebaseAuthException catch (e) {
                      String message = "Please enter email to reset password";
                      if (e.code == 'user-not-found') {
                        message = "No account found for that email";
                      }
                      setState(() {
                        _errorMessage = message;
                      });
                    }
                  },
//---------------------------------------
// forget password text
//---------------------------------------
                  child: Text(
                    "Forgot Password?",
                    style: TextStyle(
                      decoration: TextDecoration.underline,
                      color: Colors.blue,
                      fontSize: 14.sp,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20.h),
//---------------------------------------
// log in button
//---------------------------------------
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    loginUser(
                      context,
                      _emailController.text.trim(),
                      _passwordController.text.trim(),
                    );
                  },
                  child: Text("Log In"),
                ),
              ),
            ],
          ),
        ),

      ],
    );
  }
}

