import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'web_top_bar.dart';
import 'package:flutter/services.dart'
    show rootBundle;



/// ---------------------------------------------------------------------------
/// WebAccount
/// A simple account + system setting page for Admin/Manager.
/// - Left: Account info, edit profile, reset password, logout
/// - Middle: System settings (Admin: working hours/days, Everyone: time format
///           + notification switches)
/// - Right: Quick menu (Admin sees more)
/// All code below uses basic "if / else" and explicit null checks.
/// ---------------------------------------------------------------------------
class WebAccount extends StatefulWidget {
  const WebAccount({Key? key}) : super(key: key);

  @override
  State<WebAccount> createState() => _AdminWebAccountState();
}

class _AdminWebAccountState extends State<WebAccount> {
  // -------------------------------------------------------------------------
  // FIREBASE REFERENCES
  // -------------------------------------------------------------------------
  // We keep the Auth and Firestore instances here.
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Logged-in user + the Firestore doc id in UserInformation
  User? user;
  String? userDocId;

  // -------------------------------------------------------------------------
  // SIMPLE UI STATE FLAGS
  // -------------------------------------------------------------------------
  bool isLoading = true;          // true while we are loading from Firestore
  bool isEditing = false;         // true when editing profile fields
  bool isApplyingSystem = false;  // true while saving system settings

  // -------------------------------------------------------------------------
  // ACCOUNT INFO (Controllers and local values)
  // -------------------------------------------------------------------------
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _imageNameController = TextEditingController();
  final GlobalKey<FormState> _editFormKey = GlobalKey<FormState>();



  String profileImage = '';        // (not used for asset loading; kept for clarity)
  String profileImageName = '';    // file name stored in Firestore (asset/image/<name>)
  String username = 'Loading...';
  String contact = 'Loading...';
  String role = 'Loading...';

  // -------------------------------------------------------------------------
  // TIME FORMAT (User setting)
  // -------------------------------------------------------------------------
  bool use24HourFormat = true;

  // -------------------------------------------------------------------------
  // WORKING TIME & DAYS (SystemInformation/Setting)
  // Only Admin changes these.
  // -------------------------------------------------------------------------
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  Map<String, bool> workingDays = <String, bool>{
    'Sunday': false,
    'Monday': false,
    'Tuesday': false,
    'Wednesday': false,
    'Thursday': false,
    'Friday': false,
    'Saturday': false,
  };

  // -------------------------------------------------------------------------
  // NOTIFICATION PREFERENCES (flat fields on user doc)
  // -------------------------------------------------------------------------
  bool notifAll = true;
  bool notifNewBooking = true;
  bool notifPending = true;
  bool notifIssue = true;

  // -------------------------------------------------------------------------
  // LIFECYCLE: INIT
  // We get the current user and load both user + system settings.
  // -------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    user = _auth.currentUser;
    _loadAll(); // load everything on start
  }

  // =========================================================================
  // LOADERS (READ FROM FIRESTORE)
  // =========================================================================

  /// Load both user info and system settings.
  /// If no user (or user has no email), we just stop and show N/A text.
  Future<void> _loadAll() async {
    if (user == null) {
      // No logged-in user
      setState(() {
        isLoading = false;
        username = 'N/A';
        contact = 'N/A';
        role = 'N/A';
      });
      return;
    }

    // Extra safety: make sure email is not null
    if (user!.email == null) {
      setState(() {
        isLoading = false;
        username = 'N/A';
        contact = 'N/A';
        role = 'N/A';
      });
      return;
    }

    // Load user info (name/contact/role/profile image, time format, notif flags)
    await _loadUserInfo(user!.email!);

    // Load system settings (working hours + days)
    await _loadSystemSettings();

    // We finished loading
    setState(() {
      isLoading = false;
    });
  }

  /// Load one user doc by email from "UserInformation".
  /// Save basic fields + UI switches to local state.
  Future<void> _loadUserInfo(String email) async {
    final QuerySnapshot<Map<String, dynamic>> qs = await _firestore
        .collection('UserInformation')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    // If not found, show N/A and clear image name input.
    if (qs.docs.isEmpty) {
      setState(() {
        username = 'N/A';
        contact = 'N/A';
        role = 'N/A';
        profileImageName = '';
        _imageNameController.text = '';
      });
      return;
    }

    // We got the doc -> read fields carefully (no "??")
    final QueryDocumentSnapshot<Map<String, dynamic>> doc = qs.docs.first;
    final Map<String, dynamic> data = doc.data();
    userDocId = doc.id;

    // Prepare each field with simple null checks
    String newUsername = 'N/A';
    if (data.containsKey('username') && data['username'] != null) {
      newUsername = data['username'].toString();
    }

    String newContact = 'N/A';
    if (data.containsKey('contact') && data['contact'] != null) {
      newContact = data['contact'].toString();
    }

    String newRole = 'N/A';
    if (data.containsKey('role') && data['role'] != null) {
      newRole = data['role'].toString();
    }

    String newImageName = '';
    if (data.containsKey('profileImageName') && data['profileImageName'] != null) {
      newImageName = data['profileImageName'].toString();
    }

    bool newUse24 = true;
    if (data.containsKey('timeFormat24') && data['timeFormat24'] is bool) {
      newUse24 = data['timeFormat24'] as bool;
    }

    bool newNotifAll = true;
    if (data.containsKey('notifAll') && data['notifAll'] is bool) {
      newNotifAll = data['notifAll'] as bool;
    }

    bool newNotifNewBooking = true;
    if (data.containsKey('notifNewBooking') && data['notifNewBooking'] is bool) {
      newNotifNewBooking = data['notifNewBooking'] as bool;
    }

    bool newNotifPending = true;
    if (data.containsKey('notifPending') && data['notifPending'] is bool) {
      newNotifPending = data['notifPending'] as bool;
    }

    bool newNotifIssue = true;
    if (data.containsKey('notifIssue') && data['notifIssue'] is bool) {
      newNotifIssue = data['notifIssue'] as bool;
    }





    // Save to state and to controllers
    setState(() {
      username = newUsername;
      contact = newContact;
      role = newRole;

      profileImageName = newImageName;
      _imageNameController.text = profileImageName;

      use24HourFormat = newUse24;

      notifAll = newNotifAll;
      notifNewBooking = newNotifNewBooking;
      notifPending = newNotifPending;
      notifIssue = newNotifIssue;

      _usernameController.text = username;
      _contactController.text = contact;
    });
  }

  /// Load system settings from "SystemInformation/Setting".
  /// We read start/end working time and 7 day booleans.
  Future<void> _loadSystemSettings() async {
    final DocumentSnapshot<Map<String, dynamic>> snap = await _firestore
        .collection('SystemInformation')
        .doc('Setting')
        .get();

    // If no Setting doc yet, we just skip.
    if (!snap.exists) {
      return;
    }

    final Map<String, dynamic> data = snap.data()!;

    // Parse "start"/"end" like "08:00"
    String? s = null;
    if (data.containsKey('start') && data['start'] is String) {
      s = data['start'] as String;
    }

    String? e = null;
    if (data.containsKey('end') && data['end'] is String) {
      e = data['end'] as String;
    }

    // Days (default false when not present)
    bool sun = false;
    if (data.containsKey('Sunday') && data['Sunday'] is bool) {
      sun = data['Sunday'] as bool;
    }
    bool mon = false;
    if (data.containsKey('Monday') && data['Monday'] is bool) {
      mon = data['Monday'] as bool;
    }
    bool tue = false;
    if (data.containsKey('Tuesday') && data['Tuesday'] is bool) {
      tue = data['Tuesday'] as bool;
    }
    bool wed = false;
    if (data.containsKey('Wednesday') && data['Wednesday'] is bool) {
      wed = data['Wednesday'] as bool;
    }
    bool thu = false;
    if (data.containsKey('Thursday') && data['Thursday'] is bool) {
      thu = data['Thursday'] as bool;
    }
    bool fri = false;
    if (data.containsKey('Friday') && data['Friday'] is bool) {
      fri = data['Friday'] as bool;
    }
    bool sat = false;
    if (data.containsKey('Saturday') && data['Saturday'] is bool) {
      sat = data['Saturday'] as bool;
    }

    setState(() {
      if (s != null) {
        startTime = _parseTime(s);
      } else {
        startTime = null;
      }
      if (e != null) {
        endTime = _parseTime(e);
      } else {
        endTime = null;
      }

      workingDays = <String, bool>{
        'Sunday': sun,
        'Monday': mon,
        'Tuesday': tue,
        'Wednesday': wed,
        'Thursday': thu,
        'Friday': fri,
        'Saturday': sat,
      };
    });
  }

  // =========================================================================
  // SAVERS (WRITE TO FIRESTORE)
  // =========================================================================

  /// Save profile info (username, contact, profile image name) to user doc.
  /// Also verifies the chosen image file name is inside assets (asset/image/).
  Future<void> _saveAccountInfo() async {
    if (userDocId == null) {
      return;
    }

    final String fname = _imageNameController.text.trim();

    // Check if file exists in the built assets folder asset/image/
    if (fname.isNotEmpty) {
      final bool exists = await _assetExistsInBundle(fname);
      if (!exists) {
        // If not found, warn and stop saving so preview won't break
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image not found in asset/image/. Add it and restart the app.'),
          ),
        );
        return;
      }
    }

    // Build a map with the values we want to save
    final Map<String, dynamic> payload = <String, dynamic>{
      'username': _usernameController.text.trim(),
      'contact': _contactController.text.trim(),
      'profileImageName': fname,
    };

    await _firestore
        .collection('UserInformation')
        .doc(userDocId)
        .set(payload, SetOptions(merge: true));

    // Update local state so UI shows latest info
    setState(() {
      username = _usernameController.text.trim();
      contact = _contactController.text.trim();
      profileImageName = fname;
      isEditing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('User info updated')),
    );
  }

  /// Helper to check if an asset exists inside the app bundle.
  /// We try to load the bytes. If it fails, it's not bundled.
  Future<bool> _assetExistsInBundle(String name) async {
    if (name.isEmpty) {
      return false; // empty means "no image"
    }
    try {
      await rootBundle.load('asset/image/$name');
      return true; // success
    } catch (_) {
      return false; // failed to load
    }
  }

  /// Open a file dialog and keep only the chosen file name (no upload here).
  /// On the web platform, we only get the file's name, not a path.
  Future<void> _pickImageFileName() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['png', 'jpg', 'jpeg'],
      withData: false, // we only need the name
    );

    if (result == null) {
      return; // user canceled
    }
    if (result.files.isEmpty) {
      return;
    }

    final String fileName = result.files.single.name;

    setState(() {
      _imageNameController.text = fileName; // we save just the file name
    });

    // NOTE: To preview this image from assets, a file with the SAME NAME
    // must already exist at asset/image/<fileName> and be declared in pubspec.
    // Otherwise the preview will show "empty" until you add it and rebuild.
  }

  /// Save time format preference (checkbox) to user doc.
  /// We also set local state so switch updates immediately.
  Future<void> _saveTimeFormat(bool value) async {
    if (userDocId == null) {
      return;
    }

    setState(() {
      use24HourFormat = value;
    });

    await _firestore
        .collection('UserInformation')
        .doc(userDocId)
        .set(<String, dynamic>{'timeFormat24': value}, SetOptions(merge: true));
  }

  /// Save system settings (Admin):
  /// - Start / End working time
  /// - Working days (Sun..Sat)
  Future<void> _applySystemSettings() async {
    // Both times are required
    if (startTime == null || endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose both start and end time.')),
      );
      return;
    }

    setState(() {
      isApplyingSystem = true;
    });

    // Build the payload WITHOUT using spread "..."
    final Map<String, dynamic> payload = <String, dynamic>{
      'start': _formatTime(startTime!),
      'end': _formatTime(endTime!),
      'Sunday': workingDays['Sunday'] == true,
      'Monday': workingDays['Monday'] == true,
      'Tuesday': workingDays['Tuesday'] == true,
      'Wednesday': workingDays['Wednesday'] == true,
      'Thursday': workingDays['Thursday'] == true,
      'Friday': workingDays['Friday'] == true,
      'Saturday': workingDays['Saturday'] == true,
    };

    await _firestore
        .collection('SystemInformation')
        .doc('Setting')
        .set(payload, SetOptions(merge: true));

    setState(() {
      isApplyingSystem = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('System settings saved')),
    );
  }

  /// Toggle any one notification field (by field name) and save it.
  /// We also update local state first so the switch feels snappy.
  Future<void> _updateNotif(String field, bool value) async {
    if (userDocId == null) {
      return;
    }

    // Update local booleans
    setState(() {
      if (field == 'notifAll') {
        notifAll = value;
      }
      if (field == 'notifNewBooking') {
        notifNewBooking = value;
      }
      if (field == 'notifPending') {
        notifPending = value;
      }
      if (field == 'notifIssue') {
        notifIssue = value;
      }
    });

    // Save to Firestore
    await _firestore
        .collection('UserInformation')
        .doc(userDocId)
        .set(<String, dynamic>{field: value}, SetOptions(merge: true));
  }

  // =========================================================================
  // AUTH / MISC
  // =========================================================================

  /// Send a password reset email to the current user's email.
  Future<void> _sendPasswordReset() async {
    if (user == null) {
      return;
    }
    if (user!.email == null) {
      return;
    }
    await _auth.sendPasswordResetEmail(email: user!.email!);

    // Show feedback
    final String emailText = user!.email!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reset email sent to $emailText')),
    );
  }

  /// Log out and go to /login route.
  Future<void> _logout() async {
    await _auth.signOut();
    if (!mounted) {
      return;
    }
    // You used Navigator here (kept the same)
    Navigator.pushReplacementNamed(context, '/login');
  }

  // =========================================================================
  // HELPERS
  // =========================================================================

  /// Convert "HH:MM" string to TimeOfDay.
  TimeOfDay _parseTime(String hhmm) {
    final List<String> p = hhmm.split(':');
    final int h = int.parse(p[0]);
    final int m = int.parse(p[1]);
    return TimeOfDay(hour: h, minute: m);
  }

  /// Convert TimeOfDay to "HH:MM" string (24h).
  String _formatTime(TimeOfDay t) {
    final String h = t.hour.toString().padLeft(2, '0');
    final String m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Pick a time for "start" or "end".
  /// We force 24-hour display inside the picker UI for clarity.
  Future<void> _pickTime({required bool isStart}) async {
    // Decide initial time for the picker
    TimeOfDay initial;
    if (isStart) {
      if (startTime == null) {
        initial = const TimeOfDay(hour: 9, minute: 0);
      } else {
        initial = startTime!;
      }
    } else {
      if (endTime == null) {
        initial = const TimeOfDay(hour: 17, minute: 0);
      } else {
        initial = endTime!;
      }
    }

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    // If user canceled, do nothing
    if (picked == null) {
      return;
    }

    // Save picked time
    setState(() {
      if (isStart) {
        startTime = picked;
      } else {
        endTime = picked;
      }
    });
  }

  /// Simple row to show a label and a value in the Account view.
  Widget _detailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        children: <Widget>[
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.sp)),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 18.sp),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }




  /// Round profile avatar that tries to load from an asset path.
  /// If path is empty or load fails, we show a circle with "empty".
  Widget _profileAvatar(String path, {double size = 90}) {
    if (path.isEmpty) {
      // Empty state
      return CircleAvatar(
        radius: size,
        backgroundColor: Colors.grey.shade300,
        child: const Text('empty'),
      );
    }

    // Try to load the asset
    return CircleAvatar(
      radius: size,
      backgroundColor: Colors.grey.shade200,
      child: ClipOval(
        child: Image.asset(
          path,
          width: size * 2,  // CircleAvatar uses diameter
          height: size * 2,
          fit: BoxFit.cover,
          errorBuilder: (BuildContext context, Object error, StackTrace? stack) {
            return const Center(child: Text('empty'));
          },
        ),
      ),
    );
  }

  /// Build an asset path from a file name. If name is empty, return empty string.
  String _assetFromName(String name) {
    if (name.isEmpty) {
      return '';
    }
    return 'asset/image/$name';
  }

  /// Round profile avatar using only the file NAME (we convert to asset path).
  /// If the image is missing in assets, we show "empty".
  Widget _profileAvatarFromName(String name, {double size = 60}) {
    final String path = _assetFromName(name);

    // If no path (empty name), show an empty circle
    if (path.isEmpty) {
      return Container(
        width: size * 2,
        height: size * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black12, width: 2),
          color: Colors.grey.shade300,
        ),
        alignment: Alignment.center,
        child: const Text('empty'),
      );
    }

    // Try to load the asset
    return Container(
      width: size * 2,
      height: size * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        path,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext _, Object __, StackTrace? ___) {
          return const Center(child: Text('empty'));
        },
      ),
    );
  }


  // =========================================================================
  // UI (BUILD)
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    // We keep some basic derived values here to avoid "?:"
    final double screenHeight = MediaQuery.of(context).size.height;

    bool isAdmin = false;
    if (role.isNotEmpty) {
      isAdmin = role.toLowerCase() == 'admin';
    }

    // If you need manager check later; it's not used, but we keep the same style
    bool isManager = false;
    if (role.isNotEmpty) {
      isManager = role.toLowerCase() == 'manager';
    }

    // Prepare email text safely (no "??")
    String emailStr = 'N/A';
    if (user != null && user!.email != null) {
      emailStr = user!.email!;
    }

    // Prepare status text (logged in / out) without using "?:"
    String statusText = 'Logged Out';
    if (user != null) {
      statusText = 'Logged In';
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: WebCustomTopBar(use24HourFormat: use24HourFormat),
      ),

      // If still loading -> show a loader. Else show content.
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Row(
          // don't force equal heights; avoid intrinsic sizing with scrollables
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // -----------------------------------------------------------------
            // LEFT: ACCOUNT
            // -----------------------------------------------------------------
            Expanded(
              child: Center( // clamp the whole column once
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 520.w),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text("Account Settings",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 26.sp, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 35.h),

                        Center(
                          child: _profileAvatarFromName(
                            isEditing ? _imageNameController.text.trim() : profileImageName,
                            size: 150,
                          ),
                        ),
                        SizedBox(height: 16.h),

                        Builder(
                          builder: (BuildContext _) {
                            if (isEditing) {
                              return Form(
                                key: _editFormKey,
                                autovalidateMode: AutovalidateMode.onUserInteraction,
                                child: Column(
                                  children: <Widget>[
                                    SizedBox(height: 8.h),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 40.h,
                                      child: OutlinedButton(
                                        onPressed: _pickImageFileName,
                                        child: const Text("Choose Image"),
                                      ),
                                    ),
                                    SizedBox(height: 12.h),

                                    TextFormField(
                                      controller: _usernameController,
                                      decoration: const InputDecoration(labelText: "Username"),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) return 'Username cannot be empty';
                                        return null;
                                      },
                                    ),
                                    SizedBox(height: 12.h),

                                    TextFormField(
                                      controller: _contactController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: "Contact"),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) return 'Contact cannot be empty';
                                        return null;
                                      },
                                      onChanged: (value) {
                                        final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
                                        if (digitsOnly != value) {
                                          _contactController.text = digitsOnly;
                                          _contactController.selection = TextSelection.collapsed(offset: digitsOnly.length);
                                        }
                                      },
                                    ),
                                    SizedBox(height: 16.h),

                                    SizedBox(
                                      width: double.infinity,
                                      height: 48.h,
                                      child: ElevatedButton(
                                        onPressed: () {
                                          if (_editFormKey.currentState?.validate() != true) return;
                                          _saveAccountInfo();
                                        },
                                        child: const Text("Save"),
                                      ),
                                    ),
                                    SizedBox(height: 8.h),

                                    TextButton(
                                      onPressed: () => setState(() => isEditing = false),
                                      child: const Text("Cancel"),
                                    ),
                                  ],
                                ),
                              );
                            } else {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: <Widget>[
                                  _detailRow("Username:", username),
                                  _detailRow("Email:", (user != null && user!.email != null) ? user!.email! : 'N/A'),
                                  _detailRow("Contact:", contact),
                                  _detailRow("Role:", role),
                                  _detailRow("Status:", user != null ? 'Logged In' : 'Logged Out'),
                                  SizedBox(height: 16.h),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48.h,
                                    child: ElevatedButton(
                                      onPressed: () => setState(() => isEditing = true),
                                      child: const Text("Edit"),
                                    ),
                                  ),
                                ],
                              );
                            }
                          },
                        ),

                        SizedBox(height: 24.h),

                        SizedBox(
                          width: double.infinity,
                          height: 48.h,
                          child: ElevatedButton(
                            onPressed: _sendPasswordReset,
                            child: const Text("Change Password"),
                          ),
                        ),
                        SizedBox(height: 16.h),

                        SizedBox(
                          width: double.infinity,
                          height: 48.h,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: _logout,
                            child: const Text("Log Out"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),


            // divider (won't stretch without IntrinsicHeight; optional)
            Container(width: 1.w, color: Colors.black12, margin: EdgeInsets.symmetric(vertical: 16.h)),

            // -----------------------------------------------------------------
            // MIDDLE: SYSTEM SETTINGS (its own scroll)
            // -----------------------------------------------------------------
            Expanded(
              child: Center( // clamp column width once
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 560.w),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
                    child: SingleChildScrollView(
                      primary: false,
                      padding: const EdgeInsets.only(bottom: 12), // guards tiny zoom overflow
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text("System Setting",
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 26.sp, fontWeight: FontWeight.bold)),
                          SizedBox(height: 35.h),

                          // Admin-only
                          if (role.toLowerCase() == 'admin') ...[
                            Text("Working Hour", style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                            SizedBox(height: 25.h),

                            const Text("Start:"),
                            SizedBox(height: 6.h),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => _pickTime(isStart: true),
                                child: Text((startTime == null) ? "Select Start Time" : _formatTime(startTime!)),
                              ),
                            ),
                            SizedBox(height: 12.h),

                            const Text("End:"),
                            SizedBox(height: 6.h),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => _pickTime(isStart: false),
                                child: Text((endTime == null) ? "Select End Time" : _formatTime(endTime!)),
                              ),
                            ),
                            SizedBox(height: 25.h),

                            Text("Working Days", style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                            Column(
                              children: workingDays.keys.map((day) {
                                final bool v = workingDays[day] == true;
                                return CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(day),
                                  value: v,
                                  onChanged: (bool? nv) => setState(() => workingDays[day] = nv == true),
                                );
                              }).toList(),
                            ),
                            SizedBox(height: 25.h),
                          ],

                          Text("Time Format", style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text("Use 24-Hour Format"),
                            value: use24HourFormat,
                            onChanged: (bool? v) => _saveTimeFormat(v ?? true),
                          ),
                          SizedBox(height: 25.h),

                          Text("Notification Settings", style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                          SwitchListTile(
                            title: const Text("Turn on sound for all notification"),
                            value: notifAll,
                            onChanged: (bool v) => _updateNotif('notifAll', v),
                          ),
                          SwitchListTile(
                            title: const Text("Turn on sound for new booking"),
                            value: notifNewBooking,
                            onChanged: (bool v) => _updateNotif('notifNewBooking', v),
                          ),
                          SwitchListTile(
                            title: const Text("Turn on sound for new pending booking"),
                            value: notifPending,
                            onChanged: (bool v) => _updateNotif('notifPending', v),
                          ),
                          SwitchListTile(
                            title: const Text("Turn on sound for new reported issue"),
                            value: notifIssue,
                            onChanged: (bool v) => _updateNotif('notifIssue', v),
                          ),
                          SizedBox(height: 12.h),

                          if (role.toLowerCase() == 'admin')
                            SizedBox(
                              width: double.infinity,
                              height: 48.h,
                              child: ElevatedButton(
                                onPressed: isApplyingSystem ? null : _applySystemSettings,
                                child: isApplyingSystem
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Text("Apply"),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),


            // divider (optional)
            Container(width: 1.w, color: Colors.black12, margin: EdgeInsets.symmetric(vertical: 16.h)),

            // -----------------------------------------------------------------
            // RIGHT: MENU
            // -----------------------------------------------------------------
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 520.w),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
                    child: Builder(
                      builder: (context) {
                        // Local helper so you don't need a class method
                        Widget menuButton(String title, String route) {
                          return SizedBox(
                            width: double.infinity,
                            height: 60.h,
                            child: ElevatedButton(
                              onPressed: () => context.go(route),
                              child: Text(
                                title,
                                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        }

                        final bool isAdmin = role.toLowerCase() == 'admin';

                        final List<Widget> menuItems = isAdmin
                            ? <Widget>[
                          menuButton("Calendar", '/calendar'),
                          SizedBox(height: 12.h),
                          menuButton("Booking List", '/booking-list'),
                          SizedBox(height: 12.h),
                          menuButton("Facilities", '/facilities'),
                          SizedBox(height: 12.h),
                          menuButton("Manager List", '/manager-list'),
                          SizedBox(height: 12.h),
                          menuButton("Booking", '/booking'),
                          SizedBox(height: 12.h),
                          menuButton("Statistic", '/statistic'),
                          SizedBox(height: 12.h),
                          menuButton("Terms & Conditions", '/terms'),
                        ]
                            : <Widget>[
                          menuButton("Calendar", '/calendar'),
                          SizedBox(height: 12.h),
                          menuButton("Booking List", '/booking-list'),
                          SizedBox(height: 12.h),
                          menuButton("Booking", '/booking'),
                        ];

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Text(
                              "Menu",
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 26.sp, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 35.h),
                            ...menuItems,
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            )



          ],
        ),
      ),

    );
  }
}
