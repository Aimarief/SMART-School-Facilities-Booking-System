import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:file_picker/file_picker.dart';
import 'web_top_bar.dart';
import 'package:flutter/services.dart' show rootBundle;

/// ---------------------------------------------------------------------------
/// WebAccount
/// - Left: Account info, edit profile, reset password, logout
/// - Middle: System settings (Admin: working hours/days + Off Days calendar)
///           Instant save: working hours & working days update Firestore immediately.
///           Warning: only facilities are checked for conflicts; bookings ignored.
/// - Right: Notification settings (moved here from System settings)
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
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? user;
  String? userDocId;

  // -------------------------------------------------------------------------
  // SIMPLE UI STATE FLAGS
  // -------------------------------------------------------------------------
  bool isLoading = true;
  bool isEditing = false;

  // -------------------------------------------------------------------------
  // ACCOUNT INFO
  // -------------------------------------------------------------------------
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _imageNameController = TextEditingController();
  final GlobalKey<FormState> _editFormKey = GlobalKey<FormState>();

  String profileImage = '';
  String profileImageName = '';
  String username = 'Loading...';
  String contact = 'Loading...';
  String role = 'Loading...';

  // -------------------------------------------------------------------------
  // TIME FORMAT (User setting)
  // -------------------------------------------------------------------------
  bool use24HourFormat = true;

  // -------------------------------------------------------------------------
  // WORKING TIME & DAYS (SystemInformation/Setting)
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
  // OFF DAYS (SystemInformation/OffDays.offDays = ["YYYY-MM-DD", ...])
  // Calendar UI states mirror Booking List calendar.
  // -------------------------------------------------------------------------
  DateTime _offCalVisibleMonthFirst =
  DateTime(DateTime.now().year, DateTime.now().month, 1);
  final Set<String> _offDaysYMD = <String>{};
  bool _loadingOffDays = true;

  // ---- Notification toggles (right column)
  bool notifAll = true;
  bool notifNewBooking = true;
  bool notifPending = true;
  bool notifIssue = true;

  @override
  void initState() {
    super.initState();
    user = _auth.currentUser;
    _loadAll();
  }

  // =========================================================================
  // LOADERS
  // =========================================================================
  Future<void> _loadAll() async {
    if (user == null || user!.email == null) {
      setState(() {
        isLoading = false;
        username = 'N/A';
        contact = 'N/A';
        role = 'N/A';
      });
      return;
    }

    await _loadUserInfo(user!.email!);
    await _loadSystemSettings();
    await _loadOffDays();

    setState(() {
      isLoading = false;
    });
  }

  Future<void> _loadUserInfo(String email) async {
    final QuerySnapshot<Map<String, dynamic>> qs = await _firestore
        .collection('UserInformation')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

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

    final doc = qs.docs.first;
    final data = doc.data();
    userDocId = doc.id;

    String newUsername = (data['username'] ?? 'N/A').toString();
    String newContact = (data['contact'] ?? 'N/A').toString();
    String newRole = (data['role'] ?? 'N/A').toString();
    String newImageName = (data['profileImageName'] ?? '').toString();

    bool newUse24 = data['timeFormat24'] is bool ? (data['timeFormat24'] as bool) : true;

    bool newNotifAll = data['notifAll'] is bool ? (data['notifAll'] as bool) : true;
    bool newNotifNewBooking = data['notifNewBooking'] is bool ? (data['notifNewBooking'] as bool) : true;
    bool newNotifPending = data['notifPending'] is bool ? (data['notifPending'] as bool) : true;
    bool newNotifIssue = data['notifIssue'] is bool ? (data['notifIssue'] as bool) : true;

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

  Future<void> _loadSystemSettings() async {
    final snap = await _firestore.collection('SystemInformation').doc('Setting').get();
    if (!snap.exists) return;

    final data = snap.data()!;

    final s = data['start'] is String ? data['start'] as String : null;
    final e = data['end'] is String ? data['end'] as String : null;

    bool sun = data['Sunday'] is bool ? data['Sunday'] as bool : false;
    bool mon = data['Monday'] is bool ? data['Monday'] as bool : false;
    bool tue = data['Tuesday'] is bool ? data['Tuesday'] as bool : false;
    bool wed = data['Wednesday'] is bool ? data['Wednesday'] as bool : false;
    bool thu = data['Thursday'] is bool ? data['Thursday'] as bool : false;
    bool fri = data['Friday'] is bool ? data['Friday'] as bool : false;
    bool sat = data['Saturday'] is bool ? data['Saturday'] as bool : false;

    setState(() {
      startTime = (s != null) ? _parseTime(s) : null;
      endTime = (e != null) ? _parseTime(e) : null;

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

  Future<void> _loadOffDays() async {
    setState(() => _loadingOffDays = true);
    try {
      final doc = await _firestore.collection('SystemInformation').doc('OffDays').get();
      _offDaysYMD.clear();
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data['offDays'] is List) {
          for (final v in (data['offDays'] as List)) {
            final s = v?.toString().trim();
            if (s != null && s.isNotEmpty) _offDaysYMD.add(s);
          }
        }
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingOffDays = false);
    }
  }

  // =========================================================================
  // SAVERS
  // =========================================================================
  Future<void> _saveAccountInfo() async {
    if (userDocId == null) return;

    final String fname = _imageNameController.text.trim();

    if (fname.isNotEmpty) {
      final bool exists = await _assetExistsInBundle(fname);
      if (!exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image not found in asset/image/. Add it and restart the app.'),
          ),
        );
        return;
      }
    }

    final Map<String, dynamic> payload = <String, dynamic>{
      'username': _usernameController.text.trim(),
      'contact': _contactController.text.trim(),
      'profileImageName': fname,
    };

    await _firestore
        .collection('UserInformation')
        .doc(userDocId)
        .set(payload, SetOptions(merge: true));

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

  Future<bool> _assetExistsInBundle(String name) async {
    if (name.isEmpty) return false;
    try {
      await rootBundle.load('asset/image/$name');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _pickImageFileName() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['png', 'jpg', 'jpeg'],
      withData: false,
    );

    if (result == null || result.files.isEmpty) return;

    final String fileName = result.files.single.name;
    setState(() {
      _imageNameController.text = fileName;
    });
  }

  Future<void> _saveTimeFormat(bool value) async {
    if (userDocId == null) return;

    setState(() {
      use24HourFormat = value;
    });

    await _firestore
        .collection('UserInformation')
        .doc(userDocId)
        .set(<String, dynamic>{'timeFormat24': value}, SetOptions(merge: true));
  }

  Future<void> _updateWorkingDay(String day, bool value) async {
    // Update immediately (admin only section)
    setState(() {
      workingDays[day] = value;
    });
    await _firestore
        .collection('SystemInformation')
        .doc('Setting')
        .set(<String, dynamic>{day: value}, SetOptions(merge: true));
  }

  // =========================================================================
  // AUTH / MISC
  // =========================================================================
  Future<void> _sendPasswordReset() async {
    if (user == null || user!.email == null) return;
    await _auth.sendPasswordResetEmail(email: user!.email!);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reset email sent to ${user!.email!}')),
    );
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  // =========================================================================
  // HELPERS
  // =========================================================================
  TimeOfDay _parseTime(String hhmm) {
    final p = hhmm.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }


  /// Pick a time and save only if facility hours fit the new window.
  /// If conflicts exist, show a SnackBar and DO NOT change state or DB.
  Future<void> _pickTime({required bool isStart}) async {
    final TimeOfDay initial = isStart
        ? (startTime ?? const TimeOfDay(hour: 9, minute: 0))
        : (endTime ?? const TimeOfDay(hour: 17, minute: 0));

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;

    // Build candidate pair (what the times WOULD be if this change is applied)
    final TimeOfDay? candStart = isStart ? picked : startTime;
    final TimeOfDay? candEnd   = isStart ? endTime  : picked;

    // If we have both, validate order and check facility conflicts
    if (candStart != null && candEnd != null) {
      final int sMin = _timeToMinutes(_formatTime(candStart));
      final int eMin = _timeToMinutes(_formatTime(candEnd));
      if (eMin <= sMin) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End time must be later than start time.')),
        );
        return; // reject change
      }

      final String newStartStr = _formatTime(candStart);
      final String newEndStr   = _formatTime(candEnd);

      final conflicts = await _findFacilityConflicts(newStartStr, newEndStr);
      if (conflicts.isNotEmpty) {
        // Reject change and keep old values in UI and DB
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Some facilities have available time that does not fit the system start/end time. Reverting change.',
              ),
            ),
          );
        }
        return;
      }

      // No conflicts -> apply to UI and save to Firestore
      setState(() {
        if (isStart) {
          startTime = picked;
        } else {
          endTime = picked;
        }
      });
      await _saveSystemTimes(); // writes {start,end}
      return;
    }

    // If we only have one side (start or end) so far, just set state.
    // We will validate + save when both are available.
    setState(() {
      if (isStart) {
        startTime = picked;
      } else {
        endTime = picked;
      }
    });
  }


  Future<void> _saveSystemTimes() async {
    if (startTime == null || endTime == null) return;
    await _firestore
        .collection('SystemInformation')
        .doc('Setting')
        .set(
      <String, dynamic>{
        'start': _formatTime(startTime!),
        'end': _formatTime(endTime!),
      },
      SetOptions(merge: true),
    );
  }


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

  int _timeToMinutes(String hhmm) {
    try {
      final p = hhmm.split(':');
      final h = int.parse(p[0]);
      final m = int.parse(p[1]);
      return (h * 60) + m;
    } catch (_) {
      return 0;
    }
  }

  // Read facility available time from nested/flat fields
  Map<String, String> _readFacilityAvailableTimes(Map<String, dynamic> data) {
    String s = '';
    String e = '';

    if (data.containsKey('availableTime') &&
        data['availableTime'] is Map<String, dynamic>) {
      final at = data['availableTime'] as Map<String, dynamic>;
      if (at['start'] is String) s = (at['start'] as String).trim();
      if (at['end'] is String) e = (at['end'] as String).trim();
    }

    if (s.isEmpty && data['availableTimeStart'] is String) {
      s = (data['availableTimeStart'] as String).trim();
    }
    if (e.isEmpty && data['availableTimeEnd'] is String) {
      e = (data['availableTimeEnd'] as String).trim();
    }

    return <String, String>{'start': s, 'end': e};
  }

  // Check only facilities against new system hours; return list of conflicts
  Future<List<String>> _findFacilityConflicts(String newStart, String newEnd) async {
    final int sysStart = _timeToMinutes(newStart);
    final int sysEnd = _timeToMinutes(newEnd);

    final qs = await _firestore.collection('Facilities').get();
    final List<String> conflicts = <String>[];

    for (final d in qs.docs) {
      final m = d.data();

      if (m['deleted'] is bool && m['deleted'] == true) continue;

      String name = d.id;
      if (m['name'] is String && (m['name'] as String).trim().isNotEmpty) {
        name = (m['name'] as String).trim();
      }

      final at = _readFacilityAvailableTimes(m);
      final fs = (at['start'] ?? '').trim();
      final fe = (at['end'] ?? '').trim();
      if (fs.isEmpty || fe.isEmpty) continue;

      final facStart = _timeToMinutes(fs);
      final facEnd = _timeToMinutes(fe);

      if (facStart < sysStart || facEnd > sysEnd) {
        conflicts.add(name);
      }
    }

    return conflicts;
  }

  // =========================================================================
  // OFF DAYS (Calendar) Helpers + Actions
  // =========================================================================
  String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    return '$y-$m-$da';
  }

  int _daysInMonth(DateTime firstOfMonth) {
    final firstNext = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 1);
    final lastCurrent = firstNext.subtract(const Duration(days: 1));
    return lastCurrent.day;
  }

  int _leadingEmptyCells(DateTime firstOfMonth) {
    // Sunday=0 .. Saturday=6
    return firstOfMonth.weekday % 7;
  }

  String _monthName(int m) {
    const names = [
      'January','February','March','April','May','June',
      'July','August','September','October','November','December'
    ];
    return names[m - 1];
  }

  void _prevMonthOffCal() {
    final f = _offCalVisibleMonthFirst;
    setState(() => _offCalVisibleMonthFirst = DateTime(f.year, f.month - 1, 1));
  }

  void _nextMonthOffCal() {
    final f = _offCalVisibleMonthFirst;
    setState(() => _offCalVisibleMonthFirst = DateTime(f.year, f.month + 1, 1));
  }

  Future<void> _toggleOffDay(DateTime date) async {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final dateStart = DateTime(date.year, date.month, date.day);
    if (dateStart.isBefore(todayStart)) {
      // past days disabled
      return;
    }

    final ymd = _ymd(date);
    final bool willAdd = !_offDaysYMD.contains(ymd);

    // Optimistic UI update
    setState(() {
      if (willAdd) {
        _offDaysYMD.add(ymd);
      } else {
        _offDaysYMD.remove(ymd);
      }
    });

    try {
      final ref = _firestore.collection('SystemInformation').doc('OffDays');
      if (willAdd) {
        await ref.set({'offDays': FieldValue.arrayUnion([ymd])}, SetOptions(merge: true));
      } else {
        await ref.set({'offDays': FieldValue.arrayRemove([ymd])}, SetOptions(merge: true));
      }
    } catch (_) {
      // revert on failure
      setState(() {
        if (willAdd) {
          _offDaysYMD.remove(ymd);
        } else {
          _offDaysYMD.add(ymd);
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update off day. Please try again.')),
        );
      }
    }
  }

  Future<void> _updateNotif(String field, bool value) async {
    if (userDocId == null) return;

    setState(() {
      switch (field) {
        case 'notifAll':
          notifAll = value;
          break;
        case 'notifNewBooking':
          notifNewBooking = value;
          break;
        case 'notifPending':
          notifPending = value;
          break;
        case 'notifIssue':
          notifIssue = value;
          break;
      }
    });

    await _firestore
        .collection('UserInformation')
        .doc(userDocId)
        .set(<String, dynamic>{field: value}, SetOptions(merge: true));
  }

  // =========================================================================
  // UI
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;

    bool isAdmin = false;
    if (role.isNotEmpty) {
      isAdmin = role.toLowerCase() == 'admin';
    }

    String emailStr = 'N/A';
    if (user != null && user!.email != null) {
      emailStr = user!.email!;
    }

    String statusText = (user != null) ? 'Logged In' : 'Logged Out';

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70.h),
        child: WebCustomTopBar(use24HourFormat: use24HourFormat),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // -----------------------------------------------------------------
            // LEFT: ACCOUNT
            // -----------------------------------------------------------------
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 520.w),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text("Account Settings",
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 26.sp, fontWeight: FontWeight.bold)),
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
                                          _contactController.selection =
                                              TextSelection.collapsed(offset: digitsOnly.length);
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
                                  _detailRow("Email:", emailStr),
                                  _detailRow("Contact:", contact),
                                  _detailRow("Role:", role),
                                  _detailRow("Status:", statusText),
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

            // divider
            Container(width: 1.w, color: Colors.black12, margin: EdgeInsets.symmetric(vertical: 16.h)),

            // -----------------------------------------------------------------
            // MIDDLE: SYSTEM SETTINGS (+ Off Days calendar)
            // -----------------------------------------------------------------
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 560.w),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
                    child: SingleChildScrollView(
                      primary: false,
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text("System Setting",
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 26.sp, fontWeight: FontWeight.bold)),
                          SizedBox(height: 35.h),

                          // Admin-only block
                          if (isAdmin) ...[
                            Text("Working Hour", style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                            SizedBox(height: 12.h),

                            // Start/End on ONE ROW (instant save)
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("Start"),
                                      SizedBox(height: 6.h),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: () => _pickTime(isStart: true),
                                          child: Text((startTime == null) ? "Select" : _formatTime(startTime!)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 12.w),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("End"),
                                      SizedBox(height: 6.h),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          onPressed: () => _pickTime(isStart: false),
                                          child: Text((endTime == null) ? "Select" : _formatTime(endTime!)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 20.h),

                            Text("Working Days", style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                            Column(
                              children: workingDays.keys.map((day) {
                                final bool v = workingDays[day] == true;
                                return CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(day),
                                  value: v,
                                  onChanged: (bool? nv) =>
                                      _updateWorkingDay(day, nv == true),
                                );
                              }).toList(),
                            ),
                            SizedBox(height: 20.h),

                            // -------- Off Days (Holidays) Calendar --------
                            Text("Pick Off Days (Holidays)",
                                style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                            SizedBox(height: 10.h),
                            _buildOffDaysCalendarCard(),
                            SizedBox(height: 6.h),
                            Text(
                              'Tip: Click a future day to toggle holiday. Blue = holiday. Past days are disabled.',
                              style: TextStyle(fontSize: 11.sp, color: const Color(0xFF6B7280)),
                            ),
                            SizedBox(height: 12.h),
                          ],

                          // Time format is for everyone
                          Text("Time Format", style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold)),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text("Use 24-Hour Format"),
                            value: use24HourFormat,
                            onChanged: (bool? v) => _saveTimeFormat(v ?? true),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // divider
            Container(width: 1.w, color: Colors.black12, margin: EdgeInsets.symmetric(vertical: 16.h)),

            // -----------------------------------------------------------------
            // RIGHT: NOTIFICATION SETTINGS (replaces the old Menu)
            // -----------------------------------------------------------------
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 520.w),
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Text(
                          "Notification Settings",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 26.sp, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 35.h),

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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // Profile avatar helpers (unchanged)
  // =========================================================================
  Widget _profileAvatar(String path, {double size = 90}) {
    if (path.isEmpty) {
      return CircleAvatar(
        radius: size,
        backgroundColor: Colors.grey.shade300,
        child: const Text('empty'),
      );
    }

    return CircleAvatar(
      radius: size,
      backgroundColor: Colors.grey.shade200,
      child: ClipOval(
        child: Image.asset(
          path,
          width: size * 2,
          height: size * 2,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => const Center(child: Text('empty')),
        ),
      ),
    );
  }

  String _assetFromName(String name) {
    if (name.isEmpty) return '';
    return 'asset/image/$name';
  }

  Widget _profileAvatarFromName(String name, {double size = 60}) {
    final String path = _assetFromName(name);

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
        errorBuilder: (context, error, stack) => const Center(child: Text('empty')),
      ),
    );
  }

  // =========================================================================
  // Off Days Calendar UI (matching Booking List style)
  // =========================================================================
  Widget _buildOffDaysCalendarCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(12.r),
      ),
      padding: EdgeInsets.all(12.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildOffDaysCalendarHeader(),
          SizedBox(height: 8.h),
          _buildWeekdayRow(),
          SizedBox(height: 8.h),
          _buildOffDaysCalendarGrid(),
        ],
      ),
    );
  }

  Widget _buildOffDaysCalendarHeader() {
    final m = _offCalVisibleMonthFirst;
    final label = '${_monthName(m.month)} ${m.year}';

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w600),
          ),
        ),
        TextButton(onPressed: _prevMonthOffCal, child: Text('Prev', style: TextStyle(fontSize: 12.sp))),
        SizedBox(width: 4.w),
        TextButton(onPressed: _nextMonthOffCal, child: Text('Next', style: TextStyle(fontSize: 12.sp))),
      ],
    );
  }

  Widget _buildWeekdayRow() {
    const days = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    return LayoutBuilder(
      builder: (context, c) {
        final gap = 6.w;
        final totalGaps = gap * 6;
        double cellW = (c.maxWidth - totalGaps) / 7.0;
        if (cellW < 10.w) cellW = 10.w;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (i) {
            return SizedBox(
              width: cellW,
              child: Center(
                child: Text(
                  days[i],
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: const Color(0xFF6B7280),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildOffDaysCalendarGrid() {
    if (_loadingOffDays) {
      return SizedBox(
        height: 160.h,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final f = _offCalVisibleMonthFirst;
    final days = _daysInMonth(f);
    final lead = _leadingEmptyCells(f);
    final total = lead + days;

    int rows = (total / 7.0).ceil();
    if (rows < 6) rows = 6;

    return LayoutBuilder(
      builder: (context, c) {
        final gap = 6.w;
        final totalGapW = gap * 6;
        double cellW = (c.maxWidth - totalGapW) / 7.0;
        if (cellW < 10.w) cellW = 10.w;
        final gridH = (rows * cellW) + ((rows - 1) * gap);

        return SizedBox(
          height: gridH,
          child: Column(
            children: List.generate(rows, (r) {
              return Padding(
                padding: EdgeInsets.only(bottom: r == rows - 1 ? 0 : gap),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(7, (cIdx) {
                    final cellIndex = (r * 7) + cIdx;
                    final dayNum = cellIndex - lead + 1;

                    final inMonth = (dayNum >= 1 && dayNum <= days);
                    final DateTime? cellDate =
                    inMonth ? DateTime(f.year, f.month, dayNum) : null;

                    final today = DateTime.now();
                    final todayStart = DateTime(today.year, today.month, today.day);
                    final isDisabled = cellDate == null
                        ? true
                        : DateTime(cellDate.year, cellDate.month, cellDate.day)
                        .isBefore(todayStart);

                    final String ymd = (cellDate != null) ? _ymd(cellDate) : '';
                    final bool isHoliday =
                        cellDate != null && _offDaysYMD.contains(ymd);

                    return _offDayCell(
                      width: cellW,
                      height: cellW,
                      label: inMonth ? '$dayNum' : '',
                      inMonth: inMonth,
                      isDisabled: isDisabled,
                      isHoliday: isHoliday,
                      date: cellDate,
                    );
                  }),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _offDayCell({
    required double width,
    required double height,
    required String label,
    required bool inMonth,
    required bool isDisabled,
    required bool isHoliday,
    required DateTime? date,
  }) {
    Color border = const Color(0xFFE5E7EB);
    Color bg = Colors.white;
    Color text = const Color(0xFF111827);

    if (!inMonth) text = const Color(0xFF9CA3AF);
    if (isDisabled && inMonth) text = const Color(0xFF9CA3AF);

    // Holiday = blue
    if (isHoliday) {
      bg = const Color(0xFFDBEAFE);        // light blue
      border = const Color(0xFF1D4ED8);    // blue
      text = const Color(0xFF1E3A8A);
    }

    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(8.r),
          onTap: (!inMonth || isDisabled || date == null)
              ? null
              : () => _toggleOffDay(date),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8.r),
              border: Border.all(color: border),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
