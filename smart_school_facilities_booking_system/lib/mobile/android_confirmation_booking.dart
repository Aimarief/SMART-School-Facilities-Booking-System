// android_confirmation_booking.dart (ConfirmBooking)
//
// FIX IN THIS VERSION:
// - When auto-assign + requires approval, we now use the SLOT capacity
//   (from Slots/{slotKey}.capacity) to choose a temporary seat.
//   This prevents false "slot full" even when other seats are still free.
// - We also block "Confirm" while slot stats are loading to avoid stale checks.
//
// Other goals kept:
// - Simple code, diploma level, only if/else (no ? : and no ??).
// - Use .w .h .sw .sh .sp for responsive sizing (works on Huawei P30 ELE-L29).
// - Show reserve (taken) status per slot and turn red when full.
// - Save seatIndex even when approval is required; in Days/Seats we write
//   doc id == seat index, with { taken: false } for pending.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

// Bottom bar + other pages (keep navigation consistent)
import 'android_bottom_menu.dart';
import 'android_calendar.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart';

// Phone notifications (local, free, show 1 day before)
// import 'android_phone_notification.dart';

// Booking service (your Firestore write helpers)
import 'package:smart_school_facilities_booking_system/booking_service.dart';

class ConfirmBooking extends StatefulWidget {
  final String facilityId;
  final String facilityName;
  final String dateYMD;              // "YYYY-MM-DD"
  final List<String> startTimes;     // e.g. ["08:00","09:00"]
  final bool autoAssign;             // system pick seat if true
  final Map<String, int>? seatPicks; // manual picks per start

  const ConfirmBooking({
    Key? key,
    required this.facilityId,
    required this.facilityName,
    required this.dateYMD,
    required this.startTimes,
    required this.autoAssign,
    this.seatPicks,
  }) : super(key: key);

  @override
  State<ConfirmBooking> createState() => _ConfirmBookingState();
}

class _ConfirmBookingState extends State<ConfirmBooking> {
  int _currentIndex = 2;

  // User info
  String _userId = '';
  String _userName = '';
  String _userEmail = '';
  String _userContact = '';

  // Facility info
  bool _loadingFacility = true;
  Map<String, dynamic> _facility = {};
  int _facilityCapacity = 1; // fallback if slot has no capacity set
  String _facilityName = '';
  String _facilityImagePath = '';
  String _location = '';
  String _description = '';
  String _managerId = '';
  bool _requireApproval = false;

  // Manager
  bool _loadingManager = true;
  Map<String, dynamic> _manager = {};

  // Auto-assign preview (treat only taken==true as blocked)
  bool _loadingAutoSeats = false;
  final Map<String, int?> _autoSeatByStart = {};

  // Slot stats (capacity + reserve per start time)
  bool _loadingSlotStats = false;
  final Map<String, int> _capacityByStart = {}; // per-slot capacity
  final Map<String, int> _reserveByStart = {};  // accepted count

  // Approval reason
  final TextEditingController _reasonCtrl = TextEditingController();
  int _reasonLen = 0;

  // Saving flag
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadUser();

    _reasonCtrl.addListener(() {
      final int len = _reasonCtrl.text.characters.length;
      int safe = len;
      if (safe < 0) {
        safe = 0;
      } else {
        if (safe > 99) {
          safe = 99;
        }
      }
      setState(() {
        _reasonLen = safe;
      });
    });

    _loadFacilityThenChain();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  // Load current user
  Future<void> _loadUser() async {
    try {
      final User? u = FirebaseAuth.instance.currentUser;

      if (u != null) {
        _userId = u.uid;

        if (u.email != null) {
          _userEmail = u.email!;
        }

        if (u.displayName != null) {
          final String dn = u.displayName!.trim();
          if (dn.isNotEmpty) {
            _userName = dn;
          }
        }
      }

      if (_userName.isEmpty) {
        if (_userEmail.isNotEmpty) {
          _userName = _userEmail;
        } else {
          _userName = 'User';
        }
      }

      if (_userId.isNotEmpty) {
        final ds = await FirebaseFirestore.instance
            .collection('UserInformation')
            .doc(_userId)
            .get();

        if (ds.exists) {
          final Map<String, dynamic>? m = ds.data();
          if (m != null) {
            if (m.containsKey('username')) {
              final dynamic un = m['username'];
              if (un is String) {
                final String s = un.trim();
                if (s.isNotEmpty) {
                  _userName = s;
                }
              }
            }
            if (m.containsKey('contact')) {
              final dynamic c = m['contact'];
              if (c is String) {
                final String s = c.trim();
                if (s.isNotEmpty) {
                  _userContact = s;
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {});
    }
  }

  // Load facility -> manager -> slot stats -> auto seats (if needed)
  Future<void> _loadFacilityThenChain() async {
    await _loadFacilityOnce();
    await _loadManagerOnce();
    await _prefetchSlotStats();
    if (widget.autoAssign) {
      await _prefetchAutoSeats();
    }
  }

  // Load facility doc once
  Future<void> _loadFacilityOnce() async {
    setState(() {
      _loadingFacility = true;
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .get();

      if (snap.exists) {
        final Map<String, dynamic>? data = snap.data();
        if (data != null) {
          _facility = data;

          if (data.containsKey('name')) {
            final dynamic n = data['name'];
            if (n is String) {
              _facilityName = n;
            }
          }
          if (_facilityName.isEmpty) {
            _facilityName = widget.facilityName;
          }

          String imageName = '';
          if (data.containsKey('imageName')) {
            final dynamic im = data['imageName'];
            if (im is String) {
              imageName = im.trim();
            }
          }
          if (imageName.isNotEmpty) {
            _facilityImagePath = 'asset/image/$imageName';
          } else {
            _facilityImagePath = '';
          }

          if (data.containsKey('location')) {
            final dynamic loc = data['location'];
            if (loc is String) {
              _location = loc;
            }
          }

          if (data.containsKey('details')) {
            final dynamic det = data['details'];
            if (det is String) {
              _description = det;
            }
          }

          _facilityCapacity = 1;
          if (data.containsKey('availableSlots')) {
            final dynamic cap = data['availableSlots'];
            if (cap is int) {
              _facilityCapacity = cap;
            } else {
              final int? parsed = int.tryParse('$cap');
              if (parsed != null) {
                _facilityCapacity = parsed;
              }
            }
          }
          if (_facilityCapacity <= 0) {
            _facilityCapacity = 1;
          }

          _managerId = '';
          if (data.containsKey('managerId')) {
            final dynamic mid = data['managerId'];
            if (mid is String) {
              _managerId = mid;
            }
          }

          _requireApproval = false;
          if (data.containsKey('requireApproval')) {
            final dynamic r = data['requireApproval'];
            if (r is bool) {
              _requireApproval = r;
            } else {
              if (r is String) {
                final String s = r.toLowerCase().trim();
                if (s == 'true') {
                  _requireApproval = true;
                } else {
                  _requireApproval = false;
                }
              }
            }
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _loadingFacility = false;
      });
    }
  }

  // Load manager doc once
  Future<void> _loadManagerOnce() async {
    setState(() {
      _loadingManager = true;
    });

    try {
      if (_managerId.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('UserInformation')
            .doc(_managerId)
            .get();

        if (snap.exists) {
          final Map<String, dynamic>? m = snap.data();
          if (m != null) {
            _manager = m;
          }
        }
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _loadingManager = false;
      });
    }
  }

  // Read per-slot capacity and reserve (or booked) for each selected time
  Future<void> _prefetchSlotStats() async {
    setState(() {
      _loadingSlotStats = true;
    });

    try {
      int i = 0;
      while (i < widget.startTimes.length) {
        final String start = widget.startTimes[i];
        final String key = start.replaceAll(':', '').padLeft(4, '0');

        int cap = _facilityCapacity; // fallback
        int res = 0;

        try {
          final slotRef = FirebaseFirestore.instance
              .collection('Facilities').doc(widget.facilityId)
              .collection('Days').doc(widget.dateYMD)
              .collection('Slots').doc(key);

          final slotSnap = await slotRef.get();
          if (slotSnap.exists) {
            final Map<String, dynamic>? s = slotSnap.data();
            if (s != null) {
              if (s.containsKey('capacity')) {
                final dynamic c = s['capacity'];
                if (c is int) {
                  cap = c;
                } else {
                  final int? p = int.tryParse('$c');
                  if (p != null) {
                    cap = p;
                  }
                }
              }
              if (s.containsKey('reserve')) {
                final dynamic r = s['reserve'];
                if (r is int) {
                  res = r;
                } else {
                  final int? p = int.tryParse('$r');
                  if (p != null) {
                    res = p;
                  }
                }
              } else {
                if (s.containsKey('booked')) {
                  final dynamic b = s['booked'];
                  if (b is int) {
                    res = b;
                  } else {
                    final int? p = int.tryParse('$b');
                    if (p != null) {
                      res = p;
                    }
                  }
                }
              }
            }
          }
        } catch (_) {}

        if (cap <= 0) {
          cap = 1;
        }
        if (res < 0) {
          res = 0;
        }

        _capacityByStart[start] = cap;
        _reserveByStart[start] = res;

        i = i + 1;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _loadingSlotStats = false;
      });
    }
  }

  // Auto-assign helper: find first seat that is NOT taken==true
  Future<int?> _autoAssignSeatIndex(String start, int capacity) async {
    final String key = start.replaceAll(':', '').padLeft(4, '0'); // "0800"

    final qs = await FirebaseFirestore.instance
        .collection('Facilities').doc(widget.facilityId)
        .collection('Days').doc(widget.dateYMD)
        .collection('Slots').doc(key)
        .collection('Seats')
        .get();

    final Set<int> hardTaken = <int>{};

    for (final d in qs.docs) {
      final int? idx = int.tryParse(d.id);
      if (idx != null) {
        bool isTaken = false;
        final Map<String, dynamic> data = d.data();
        if (data.containsKey('taken')) {
          final dynamic t = data['taken'];
          if (t is bool) {
            if (t == true) {
              isTaken = true;
            }
          }
        }
        if (isTaken) {
          hardTaken.add(idx);
        }
      }
    }

    int i = 1;
    while (i <= capacity) {
      if (!hardTaken.contains(i)) {
        return i;
      }
      i = i + 1;
    }

    return null; // all seat docs are taken==true
  }

  // Prefetch auto seats with the CORRECT per-slot capacity
  Future<void> _prefetchAutoSeats() async {
    setState(() {
      _loadingAutoSeats = true;
    });

    try {
      int i = 0;
      while (i < widget.startTimes.length) {
        final String s = widget.startTimes[i];

        // Use per-slot capacity if we have it, else fallback to facility capacity
        int cap = _facilityCapacity;
        if (_capacityByStart.containsKey(s)) {
          cap = _capacityByStart[s]!;
        }

        final int? idx = await _autoAssignSeatIndex(s, cap);
        _autoSeatByStart[s] = idx; // can be null

        i = i + 1;
      }
    } catch (_) {}

    if (mounted) {
      setState(() {
        _loadingAutoSeats = false;
      });
    }
  }

  // Format to "hh:mm am/pm"
  String _toAmPm(String hhmm) {
    final List<String> p = hhmm.split(':');
    int h = 0;
    int m = 0;

    if (p.isNotEmpty) {
      final int? hh = int.tryParse(p[0]);
      if (hh != null) {
        h = hh;
      }
    }

    if (p.length > 1) {
      final int? mm = int.tryParse(p[1]);
      if (mm != null) {
        m = mm;
      }
    }

    String suffix = 'am';
    if (h >= 12) {
      suffix = 'pm';
    }

    final String hh2 = h.toString().padLeft(2, '0');
    final String mm2 = m.toString().padLeft(2, '0');
    return '$hh2:$mm2 $suffix';
  }

  // Pretty date
  String _niceDate(String ymd) {
    try {
      final List<String> parts = ymd.split('-');
      final int y = int.parse(parts[0]);
      final int m = int.parse(parts[1]);
      final int d = int.parse(parts[2]);

      const List<String> months = [
        'January','February','March','April','May','June',
        'July','August','September','October','November','December'
      ];

      return '$d ${months[m - 1]} $y';
    } catch (_) {
      return ymd;
    }
  }

  // Confirm button handler
  Future<void> _onConfirmPressed() async {
    if (_saving) {
      return;
    }

    // Make sure facility loaded
    if (_loadingFacility) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please wait, loading facility...')),
      );
      return;
    }

    // Make sure slot stats loaded when we need them for auto-assign + approval
    if (widget.autoAssign) {
      if (_requireApproval) {
        if (_loadingSlotStats) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please wait, checking availability...')),
          );
          return;
        }
      }
    }

    // Reason if approval is required
    if (_requireApproval) {
      final String reason = _reasonCtrl.text.trim();
      if (reason.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please enter your reason')),
        );
        return;
      }
    }

    // Build final seat map for saving
    final Map<String, int> seatByStart = <String, int>{};

    if (widget.autoAssign) {
      if (_requireApproval) {
        // Auto-assign + approval: pre-pick a TEMP seat using SLOT capacity
        int i = 0;
        while (i < widget.startTimes.length) {
          final String s = widget.startTimes[i];

          // per-slot capacity preferred
          int cap = _facilityCapacity;
          if (_capacityByStart.containsKey(s)) {
            cap = _capacityByStart[s]!;
          }

          final int? idx = await _autoAssignSeatIndex(s, cap);
          if (idx == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Time ${_toAmPm(s)} is full. Choose another.')),
            );
            return;
          } else {
            seatByStart[s] = idx;
          }
          i = i + 1;
        }
      } else {
        // Auto-assign + NO approval: the service will assign in transaction.
      }
    } else {
      // Manual seat picks must exist for every start time
      if (widget.seatPicks == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please pick a seat for every time.')),
        );
        return;
      }

      if (widget.seatPicks!.length != widget.startTimes.length) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please pick a seat for every time.')),
        );
        return;
      }

      int i = 0;
      while (i < widget.startTimes.length) {
        final String s = widget.startTimes[i];
        final int? idx = widget.seatPicks![s];
        if (idx == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Please pick a seat for every time.')),
          );
          return;
        } else {
          seatByStart[s] = idx;
        }
        i = i + 1;
      }
    }

    // Begin saving
    setState(() {
      _saving = true;
    });

    try {
      String managerName = '';
      if (_facility.containsKey('managerName')) {
        final dynamic mn = _facility['managerName'];
        if (mn is String) {
          managerName = mn;
        }
      }

      int i = 0;
      while (i < widget.startTimes.length) {
        final String start = widget.startTimes[i];

        final String slotKey = start.replaceAll(':', '').padLeft(4, '0');

        String end = '';
        if (_facility.containsKey('customTimeSlots')) {
          final dynamic raw = _facility['customTimeSlots'];
          if (raw is List) {
            int k = 0;
            while (k < raw.length) {
              final dynamic item = raw[k];
              if (item is Map<String, dynamic>) {
                final dynamic st = item['start'];
                if (st is String) {
                  if (st == start) {
                    final dynamic ed = item['end'];
                    if (ed is String) {
                      end = ed;
                    }
                  }
                }
              }
              k = k + 1;
            }
          }
        }

        final Map<String, dynamic> bookingBase = <String, dynamic>{};
        bookingBase['userId'] = _userId;
        bookingBase['userName'] = _userName;
        bookingBase['userEmail'] = _userEmail;
        bookingBase['userContact'] = _userContact;
        bookingBase['facilityId'] = widget.facilityId;
        bookingBase['facilityName'] = _facilityName;
        bookingBase['managerId'] = _managerId;
        bookingBase['managerName'] = managerName;
        bookingBase['bookingDate'] = widget.dateYMD; // "YYYY-MM-DD"
        bookingBase['slotKey'] = slotKey;           // "0800"
        bookingBase['start'] = start;               // "HH:mm"
        bookingBase['rated'] = false;
        if (end.isNotEmpty) {
          bookingBase['end'] = end;
        }
        bookingBase['autoAssigned'] = widget.autoAssign;
        bookingBase['createdAt'] = FieldValue.serverTimestamp();

        if (_requireApproval) {
          // ----------- PENDING PATH -----------
          bookingBase['approval'] = 'pending';
          bookingBase['approvalReason'] = _reasonCtrl.text.trim();
          bookingBase['status'] = 'upcoming';

          // seatIndex MUST be stored even when pending (manual or auto)
          if (widget.autoAssign) {
            final int? tempSeat = seatByStart[start];
            if (tempSeat != null) {
              bookingBase['seatIndex'] = tempSeat;
            }
          } else {
            final int? manualSeat = seatByStart[start];
            if (manualSeat != null) {
              bookingBase['seatIndex'] = manualSeat;
            }
          }

          // This writes Bookings + Days/Seats/{seatIndex} with taken:false
          await BookingService.createBookingPending(
            bookingBase: bookingBase,
          );

        } else {
          // ----------- ACCEPTED NOW PATH -----------
          bookingBase['approval'] = 'accepted';
          bookingBase['status'] = 'upcoming';

          if (widget.autoAssign) {
            await BookingService.createBookingAutoAssignTx(
              facilityId: widget.facilityId,
              dateYMD: widget.dateYMD,
              slotKey: slotKey,
              bookingBase: bookingBase,
            );
            // If you use phone notifications, schedule here for accepted only.
            // PhoneNotifications.scheduleReminder(...);

          } else {
            final int seatIdx = seatByStart[start]!;
            bookingBase['seatIndex'] = seatIdx;

            await BookingService.createBookingPickSeatTx(
              facilityId: widget.facilityId,
              dateYMD: widget.dateYMD,
              slotKey: slotKey,
              seatIndex: seatIdx,
              bookingBase: bookingBase,
            );
            // If you use phone notifications, schedule here for accepted only.
            // PhoneNotifications.scheduleReminder(...);
          }
        }

        i = i + 1;
      }

      if (mounted) {
        String msg;
        if (_requireApproval) {
          msg = 'Request sent. An admin will review it.';
        } else {
          msg = 'Booking created';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => AndroidViewBooking()),
              (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create booking: $e')),
        );
      }
    }

    if (mounted) {
      setState(() {
        _saving = false;
      });
    }
  }

  // Bottom bar switching
  void _onTabSelected(int i) {
    if (i == 2) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => AndroidListOfFacilities()),
      );
    } else {
      if (i == 0) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => AndroidCalendar()),
        );
      } else {
        if (i == 1) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => AndroidViewBooking()),
          );
        } else {
          if (i == 3) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => AndroidNotifications()),
            );
          } else {
            if (i == 4) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => AndroidAccount()),
              );
            }
          }
        }
      }
    }
  }

  // Label:Value line (optionally colored)
  Widget _kvLine({required String label, required String value, Color? color}) {
    Color labelColor = Colors.black;
    if (color != null) {
      labelColor = color;
    }
    Color valueColor = Colors.black87;
    if (color != null) {
      valueColor = color;
    }

    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: labelColor),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13.sp, color: valueColor),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  // Grey box
  Widget _box(String text) {
    return Container(
      width: 1.0.sw,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Text(text, style: TextStyle(fontSize: 14.sp)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double barHeight = MediaQuery.of(context).size.height * 0.07;
    final double sw = 1.0.sw;

    Widget imageChild;
    if (_facilityImagePath.isEmpty) {
      imageChild = Center(
        child: Icon(Icons.image_not_supported, size: 40.sp, color: Colors.white),
      );
    } else {
      imageChild = Image.asset(_facilityImagePath, fit: BoxFit.cover);
    }

    double imgH = sw * 0.75;
    if (imgH < 240.h) {
      imgH = 240.h;
    } else {
      if (imgH > 420.h) {
        imgH = 420.h;
      }
    }

    // Build slot rows (seat preview + reserve stats)
    final List<Widget> timeRows = <Widget>[];
    int t = 0;
    while (t < widget.startTimes.length) {
      final String start = widget.startTimes[t];

      // Seat preview text
      String seatTxt = '-';
      if (widget.autoAssign) {
        if (_loadingAutoSeats) {
          seatTxt = 'Checking...';
        } else {
          if (_autoSeatByStart.containsKey(start)) {
            final int? idx = _autoSeatByStart[start];
            if (idx == null) {
              seatTxt = 'Full';
            } else {
              seatTxt = 'Slot $idx';
            }
          } else {
            seatTxt = 'Checking...';
          }
        }
      } else {
        if (widget.seatPicks != null) {
          final int? idx = widget.seatPicks![start];
          if (idx == null) {
            seatTxt = '-';
          } else {
            seatTxt = 'Slot $idx';
          }
        } else {
          seatTxt = '-';
        }
      }
      timeRows.add(_kvLine(label: _toAmPm(start), value: seatTxt));

      // Reserve stats line
      int cap = _facilityCapacity;
      if (_capacityByStart.containsKey(start)) {
        cap = _capacityByStart[start]!;
      }
      int res = 0;
      if (_reserveByStart.containsKey(start)) {
        res = _reserveByStart[start]!;
      }

      bool isFull = false;
      if (res >= cap) {
        isFull = true;
      }

      String statText = 'Taken: $res / $cap';
      if (isFull) {
        statText = 'Taken: $res / $cap (Full)';
      }

      Color? statColor;
      if (isFull) {
        statColor = Colors.red;
      } else {
        statColor = null;
      }

      timeRows.add(_kvLine(label: 'Status', value: statText, color: statColor));
      timeRows.add(SizedBox(height: 8.h));

      t = t + 1;
    }

    // Manager card prep
    String managerName = '';
    String managerEmail = '';
    String managerContact = '';
    String managerAssetPath = '';

    if (_manager.isNotEmpty) {
      if (_manager.containsKey('username')) {
        final dynamic u = _manager['username'];
        if (u is String) {
          managerName = u;
        }
      }
      if (managerName.isEmpty) {
        if (_manager.containsKey('name')) {
          final dynamic n = _manager['name'];
          if (n is String) {
            managerName = n;
          }
        }
      }

      if (_manager.containsKey('email')) {
        final dynamic e = _manager['email'];
        if (e is String) {
          managerEmail = e;
        }
      }

      if (_manager.containsKey('contact')) {
        final dynamic c = _manager['contact'];
        if (c is String) {
          managerContact = c;
        }
      }

      String imgName = '';
      if (_manager.containsKey('profileImageName')) {
        final dynamic im = _manager['profileImageName'];
        if (im is String) {
          imgName = im.trim();
        }
      }
      if (imgName.isNotEmpty) {
        managerAssetPath = 'asset/image/$imgName';
      } else {
        managerAssetPath = '';
      }
    }

    Widget managerImage;
    if (managerAssetPath.isEmpty) {
      managerImage = Container(
        color: Colors.grey.shade400,
        alignment: Alignment.center,
        child: Icon(Icons.person_off, color: Colors.white, size: 26.sp),
      );
    } else {
      managerImage = Image.asset(managerAssetPath, fit: BoxFit.cover);
    }

    // Approval UI
    final List<Widget> approvalWidgets = <Widget>[];
    if (_requireApproval) {
      approvalWidgets.add(
        Text('Reason (required)', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
      );
      approvalWidgets.add(SizedBox(height: 6.h));
      approvalWidgets.add(
        Stack(
          children: [
            TextField(
              controller: _reasonCtrl,
              maxLength: 99,
              maxLines: 3,
              decoration: InputDecoration(
                counterText: '',
                isDense: true,
                hintText: 'Why do you need this booking?',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r)),
                fillColor: Colors.grey.shade200,
                filled: true,
              ),
            ),
            Positioned(
              right: 10.w,
              bottom: 8.h,
              child: Text(
                '$_reasonLen/99',
                style: TextStyle(fontSize: 12.sp, color: Colors.black54),
              ),
            ),
          ],
        ),
      );
      approvalWidgets.add(SizedBox(height: 18.h));
    }

    // Body
    Widget bodyChild;
    if (_loadingFacility) {
      bodyChild = Center(
        child: SizedBox(
          width: 28.w,
          height: 28.w,
          child: CircularProgressIndicator(),
        ),
      );
    } else {
      bodyChild = SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h).copyWith(bottom: 96.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Facility image
            Container(
              width: 1.0.sw,
              height: imgH,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16.r),
                color: Colors.grey.shade300,
              ),
              child: imageChild,
            ),

            SizedBox(height: 16.h),

            // Narrow content for readability
            SizedBox(
              width: 0.90.sw,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _facilityName,
                    style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  SizedBox(height: 12.h),

                  Text('Date', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6.h),
                  _box(_niceDate(widget.dateYMD)),

                  SizedBox(height: 18.h),

                  Text('Start time(s) & slot', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6.h),
                  Container(
                    width: 1.0.sw,
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: timeRows,
                    ),
                  ),

                  SizedBox(height: 18.h),

                  Text('Location', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6.h),
                  _box(_location),

                  SizedBox(height: 18.h),

                  Text('Description', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6.h),
                  _box(_description),

                  SizedBox(height: 18.h),

                  Text('Your info', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6.h),
                  Container(
                    width: 1.0.sw,
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _kvLine(label: 'Username', value: _userName),
                        SizedBox(height: 6.h),
                        _kvLine(label: 'Email', value: _userEmail),
                        SizedBox(height: 6.h),
                        _kvLine(label: 'Contact', value: _userContact),
                      ],
                    ),
                  ),

                  SizedBox(height: 18.h),

                  ...approvalWidgets,

                  Text('Manager', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6.h),

                  Builder(
                    builder: (context) {
                      Widget managerCardChild;
                      if (_loadingManager) {
                        managerCardChild = SizedBox(
                          width: 28.w,
                          height: 28.w,
                          child: CircularProgressIndicator(),
                        );
                      } else {
                        managerCardChild = Container(
                          width: 1.0.sw,
                          constraints: BoxConstraints(minHeight: 135.h),
                          padding: EdgeInsets.all(10.w),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2CCFF),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8.r),
                                child: SizedBox(
                                  width: 110.w,
                                  height: 110.w,
                                  child: managerImage,
                                ),
                              ),
                              SizedBox(width: 15.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _kvLine(label: 'Name', value: managerName),
                                    SizedBox(height: 6.h),
                                    _kvLine(label: 'Email', value: managerEmail),
                                    SizedBox(height: 6.h),
                                    _kvLine(label: 'Contact', value: managerContact),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      return managerCardChild;
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Button label without ternary
    String btnText = 'Confirm';
    if (_saving) {
      btnText = 'Saving...';
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          elevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white, size: 22.sp),
            onPressed: () {
              Navigator.pop(context);
            },
            tooltip: 'Back',
          ),
          title: Text(
            'Confirmation',
            style: TextStyle(color: Colors.white, fontSize: 20.sp, fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.close, color: Colors.white, size: 22.sp),
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => AndroidListOfFacilities()),
                      (route) => false,
                );
              },
              tooltip: 'Close',
            ),
          ],
        ),
      ),

      body: bodyChild,

      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: SizedBox(
          width: 1.0.sw,
          height: 48.h,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9747FF),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            ),
            onPressed: () {
              if (_saving) {
                // ignore while saving
              } else {
                _onConfirmPressed();
              }
            },
            child: Text(
              btnText,
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
