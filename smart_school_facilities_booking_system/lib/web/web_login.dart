import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:smart_school_facilities_booking_system/web/web_homepage.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'web_account.dart';
import 'dart:async';

class WebLoginPage extends StatefulWidget {
  @override
  _WebLoginPageState createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  bool isAdminSelected = true;
  String? _errorMessage;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;  // optional, for showing loading indicator
  bool _obscurePassword = true;

  Future<void> _handleLogin() async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    String email = _emailController.text.trim();
    String password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = "Email and password cannot be empty.";
        _isLoading = false;
      });
      return;
    }

    try {
      // Sign in with Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = userCredential.user;

      if (user == null) {
        setState(() {
          _errorMessage = "Login failed. User not found.";
          _isLoading = false;
        });
        return;
      }

      // Fetch user role
      // Block Manager login if not verified
      // Block Manager login if not verified
      if (!isAdminSelected) {
        await user.reload(); // refresh
        if (!user.emailVerified) {
          await FirebaseAuth.instance.signOut();
          setState(() {
            _errorMessage = "Please verify your email before logging in.";
            _isLoading = false;
          });
          return;
        }
      }

// Now fetch user data from Firestore
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('UserInformation')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        setState(() {
          _errorMessage = "User data not found.";
          _isLoading = false;
        });
        await FirebaseAuth.instance.signOut();
        return;
      }

      String role = userDoc.get('role');


      // Check if the selected role matches
      if ((isAdminSelected && role != 'Admin') ||
          (!isAdminSelected && role != 'Manager')) {
        setState(() {
          _errorMessage = "You are not authorized as ${isAdminSelected ? 'Admin' : 'Manager'}.";
          _isLoading = false;
        });
        await FirebaseAuth.instance.signOut();
        return;
      }

      // Success
      setState(() => _isLoading = false);

// If logging in as Manager, sync Auth.emailVerified -> Firestore.isVerified
      if (!isAdminSelected) {
        await _syncVerifiedFlag();  // <- This will now correctly refresh and update
      }

      if (isAdminSelected) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.go('/homepage');
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          context.go('/homepage');
        });
      }


    } on FirebaseAuthException catch (_) {
      setState(() {
        _errorMessage = "Incorrect email or password.";
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "An error occurred. Please try again.";
        _isLoading = false;
      });
      print("General error: $e");
    }
  }

  Future<void> _syncVerifiedFlag() async {
    await FirebaseAuth.instance.currentUser?.reload(); // refresh Auth user
    final u = FirebaseAuth.instance.currentUser;

    // Update Firestore if verified
    if (u != null && u.emailVerified) {
      await FirebaseFirestore.instance
          .collection('UserInformation')
          .doc(u.uid)
          .update({'isVerified': true});
    }
  }




  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background image
          Positioned.fill(
            child: Image.asset(
              'asset/image/Web_login.png', // <-- your background image
              fit: BoxFit.cover,
            ),
          ),

          // Footer at bottom
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 149.h,
              width: double.infinity,
              color: const Color(0xFFB779F1).withOpacity(0.95),
              alignment: Alignment.center,
              child: Text(
                "© 2025 SMART School Facility Booking System",
                style: TextStyle(
                  fontSize: 16.sp,
                  color: Colors.white,
                ),
              ),
            ),
          ),

          // Center box, moved slightly upward
          Align(
            alignment: Alignment(0, -0.4), // -0.1 moves it up
            child: Container(
              width: 1177.w,
              height: 637.h,
              decoration: BoxDecoration(
                color: const Color(0xFFE2CCFF).withOpacity(0.94), // #E2CCFF
                border: Border.all(
                  color: const Color(0xFF6E00D4), // outline
                  width: 1.w,
                ),
              ),
              child: Column(
                children: [
                  SizedBox(height: 20.h),

                  // Toggle buttons
                  // Toggle buttons using HoverToggleButton widget
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      HoverToggleButton(
                        text: "Admin",
                        isSelected: isAdminSelected,
                        onTap: () => setState(() => isAdminSelected = true),
                      ),
                      HoverToggleButton(
                        text: "Manager",
                        isSelected: !isAdminSelected,
                        onTap: () => setState(() => isAdminSelected = false),
                      ),
                    ],
                  ),


                  SizedBox(height: 20.h),

                  // Content split
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Left: logo
                        Expanded(
                          flex: 1,
                          child: Center(
                            child: Image.asset(
                              'asset/image/fyp_logo.png',
                              width: 429.w,
                              height: 336.h,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),

                        // Middle divider
                        Container(
                          width: 1.w,
                          height: 470.h,
                          color: const Color(0xFF6E00D4),
                        ),

                        // Right: login form
                        Expanded(
                          flex: 1,
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 40.w),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // erro message box
                                if (_errorMessage != null) ...[
                                  Container(
                                    padding: EdgeInsets.all(8.w),
                                    color: Colors.red.shade100,
                                    child: Row(
                                      children: [
                                        Icon(Icons.error, color: Colors.red, size: 20.sp),
                                        SizedBox(width: 8.w),
                                        Expanded(
                                          child: Text(
                                            _errorMessage!,
                                            style: TextStyle(color: Colors.red, fontSize: 14.sp),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(height: 12.h),
                                ],

                                // Email label
                                Text(
                                  "Email",
                                  style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                ),
                                SizedBox(height: 5.h),
                                TextField(
                                  controller: _emailController,
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: _errorMessage != null ? Colors.red : Colors.grey,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: _errorMessage != null ? Colors.red : Colors.grey,
                                      ),
                                    ),
                                  ),
                                ),

                                SizedBox(height: 20.h),

                                // Password label
                                Text(
                                  "Password",
                                  style: TextStyle(
                                    fontSize: 18.sp,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                ),
                                SizedBox(height: 5.h),
                                TextField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  decoration: InputDecoration(
                                    border: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: _errorMessage != null ? Colors.red : Colors.grey,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(
                                        color: _errorMessage != null ? Colors.red : Colors.grey,
                                      ),
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                        size: 24.sp,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                // Add forget password only for Manager
                                if (!isAdminSelected)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () async {
                                        final email = _emailController.text.trim();
                                        if (email.isEmpty) {
                                          setState(() {
                                            _errorMessage = "Please enter your email to reset password.";
                                          });
                                          return;
                                        }
                                        try {
                                          await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                                          setState(() {
                                            _errorMessage = "Password reset email sent! Check your inbox.";
                                          });
                                        } on FirebaseAuthException catch (e) {
                                          setState(() {
                                            _errorMessage = "Error: ${e.message}";
                                          });
                                        } catch (e) {
                                          setState(() {
                                            _errorMessage = "An error occurred. Please try again.";
                                          });
                                        }
                                      },
                                      child: Text(
                                        "Forgot Password?",
                                        style: TextStyle(
                                          fontSize: 14.sp,
                                          color: Colors.blue,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),

                                SizedBox(height: 20.h),
                                SizedBox(height: 20.h),


                                ElevatedButton(
                                  onPressed: _isLoading ? null : _handleLogin,
                                  style: ButtonStyle(
                                    backgroundColor: MaterialStateProperty.resolveWith<Color>(
                                          (Set<MaterialState> states) {
                                        if (states.contains(MaterialState.hovered)) {
                                          return const Color(0xFF8A2BE2); // lighter purple on hover
                                        }
                                        return const Color(0xFF6E00D4); // normal color
                                      },
                                    ),
                                    padding: MaterialStateProperty.all(
                                      EdgeInsets.symmetric(horizontal: 50.w, vertical: 20.h),
                                    ),
                                    shape: MaterialStateProperty.all(
                                      RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12.r),
                                      ),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? SizedBox(
                                    width: 20.w,
                                    height: 20.w,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                      : Text(
                                    "Login",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),

                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


}

class HoverToggleButton extends StatefulWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onTap;

  const HoverToggleButton({
    required this.text,
    required this.isSelected,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  _HoverToggleButtonState createState() => _HoverToggleButtonState();
}

class _HoverToggleButtonState extends State<HoverToggleButton> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 150.w,
          height: 40.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.isSelected
                ? Colors.white
                : (isHovered ? const Color(0xFF7A1AE4) : const Color(0xFF6E00D4)),
            border: Border.all(color: const Color(0xFF6E00D4), width: 1.w),
          ),
          child: Text(
            widget.text,
            style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: widget.isSelected ? const Color(0xFF6E00D4) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
