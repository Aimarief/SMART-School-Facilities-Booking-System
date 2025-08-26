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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView( // ✅ Allows scrolling if content doesn't fit
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
  String? _errorMessage; // ✅ Store the error message

  Future<void> loginUser(BuildContext context, String email, String password) async {
    setState(() {
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login successful')),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AndroidListOfFacilities()),
      );

    } on FirebaseAuthException catch (e) {
      String message = "Incorrect email or password";

      if (e.code == 'invalid-email') {
        message = "Invalid email format";
      }

      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        message = "Incorrect email or password";
      }

      setState(() {
        _errorMessage = message;
      });
    }
  }




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
          width: 0.9.sw, // ✅ 90% of screen width
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ✅ Error Box
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

              Text("Email",
                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.bold)),
              SizedBox(height: 8.h),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: "Enter your email",
                  border: OutlineInputBorder(),
                ),
              ),
              SizedBox(height: 20.h),
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

                    try {
                      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Password reset email sent to $email')),
                      );
                    } on FirebaseAuthException catch (e) {
                      String message = "Failed to send reset email";
                      if (e.code == 'user-not-found') {
                        message = "No account found for that email";
                      }
                      setState(() {
                        _errorMessage = message;
                      });
                    }
                  },
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

