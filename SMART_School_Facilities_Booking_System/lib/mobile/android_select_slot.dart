// android_select_slot.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

// keep your bottom bar and other pages
import 'android_bottom_menu.dart';
import 'android_calendar.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart';

class SelectSlot extends StatefulWidget {
  final String facilityId;
  final String facilityName;
  final String dateYMD;          // "YYYY-MM-DD"
  final List<String> startTimes; // e.g. ["08:00","09:00"]

  const SelectSlot({
    Key? key,
    required this.facilityId,
    required this.facilityName,
    required this.dateYMD,
    required this.startTimes,
  }) : super(key: key);

  @override
  State<SelectSlot> createState() => _SelectSlotState();
}

class _SelectSlotState extends State<SelectSlot> {
  int _currentIndex = 2;

  // time("08:00") -> chosen slot index (1-based)
  final Map<String, int> _pick = {};

  // prevent double submit
  bool _saving = false;

  void _onTabSelected(int i) {
    if (i == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
    } else if (i == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidCalendar()));
    } else if (i == 1) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } else if (i == 3) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
    } else if (i == 4) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
    }
  }

  String _toAmPmDotStart(String hhmm) {
    final p = hhmm.split(':');
    int hour = int.tryParse(p.isNotEmpty ? p[0] : '0') ?? 0;
    int minute = int.tryParse(p.length > 1 ? p[1] : '0') ?? 0;
    final suffix = hour >= 12 ? 'pm' : 'am';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    return '$h12.$m $suffix';
  }

  String _slotKey(String hhmm) => hhmm.replaceAll(':', '').padLeft(4, '0'); // "08:00" -> "0800"

  String _niceDate(String ymd) {
    try {
      final parts = ymd.split('-');
      final y = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final d = int.parse(parts[2]);
      const months = [
        'January','February','March','April','May','June',
        'July','August','September','October','November','December'
      ];
      return '$d ${months[m-1]} $y';
    } catch (_) {
      return ymd;
    }
  }

  // ---- TRANSACTION: create a single booking with an exact seat number ----
  Future<void> _createBookingPickSeatTx({
    required String facilityId,
    required String dateYMD,
    required String slotKey, // "0800"
    required int seatIndex,  // 1..capacity
    required Map<String, dynamic> bookingBase,
  }) async {
    final db = FirebaseFirestore.instance;

    await db.runTransaction((tx) async {
      final facRef  = db.collection('Facilities').doc(facilityId);
      final dayRef  = facRef.collection('Days').doc(dateYMD);
      final slotRef = dayRef.collection('Slots').doc(slotKey);

      // per-seat lock doc, zero-padded 3 digits (001..999)
      final seatId  = seatIndex.toString().padLeft(3, '0');
      final seatRef = slotRef.collection('Seats').doc(seatId);

      // Read facility (capacity + manager + requireApproval)
      final facSnap = await tx.get(facRef);
      final fac     = facSnap.data() ?? {};
      final int capacity = (fac['availableSlots'] is int)
          ? fac['availableSlots'] as int
          : int.tryParse('${fac['availableSlots']}') ?? 1;
      final bool requireApproval = fac['requireApproval'] == true;
      final String managerId   = (fac['managerId'] ?? '').toString();
      final String managerName = (fac['managerName'] ?? '').toString();

      // Read ledger for this time
      final slotSnap = await tx.get(slotRef);
      final int reserved = slotSnap.exists
          ? ((slotSnap.data()?['reserved'] ?? 0) as int)
          : 0;
      if (reserved >= capacity) {
        throw Exception('FULL');
      }

      // Seat lock check
      final seatSnap = await tx.get(seatRef);
      if (seatSnap.exists) {
        // someone else took the same seat concurrently
        throw Exception('TAKEN');
      }

      // OK — lock seat and bump reserved
      tx.set(seatRef, {
        'taken': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (slotSnap.exists) {
        tx.update(slotRef, {
          'reserved': reserved + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        tx.set(slotRef, {
          'reserved': 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // write booking
      final bookingsRef = db.collection('Bookings').doc();
      final booking = <String, dynamic>{
        ...bookingBase,
        'managerId': managerId,
        'managerName': managerName,
        'seat': seatIndex,
        'approval': requireApproval ? 'pending' : 'accepted',
      };
      tx.set(bookingsRef, booking);
    });
  }

  // ---- Confirm: create a booking for each time with the chosen seat number ----
  Future<void> _onConfirmPressed({
    required Map<String, dynamic> fac, // facility doc
  }) async {
    if (_saving) return;
    if (_pick.length != widget.startTimes.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick one slot for each time.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      // try to resolve "end" for each start from customTimeSlots
      final List<Map<String, dynamic>> template = <Map<String, dynamic>>[];
      final raw = fac['customTimeSlots'];
      if (raw is List) {
        for (final it in raw) {
          if (it is Map<String, dynamic>) template.add(it);
        }
      }

      String? _endForStart(String start) {
        for (final m in template) {
          if ((m['start'] ?? '').toString() == start) {
            return (m['end'] ?? '').toString();
          }
        }
        return null;
      }

      // current user
      final u = FirebaseAuth.instance.currentUser;
      final userId = u?.uid ?? 'unknown';
      final userName = u?.displayName ?? u?.email ?? 'User';

      // create all bookings, one per selected time
      for (final start in widget.startTimes) {
        final seatIndex = _pick[start]!;
        final slotKey   = _slotKey(start);
        final end       = _endForStart(start) ?? '';

        final bookingBase = <String, dynamic>{
          'userId': userId,
          'userName': userName,
          'facilityId': widget.facilityId,
          'facilityName': widget.facilityName,
          'bookingDate': widget.dateYMD,
          'slotKey': slotKey, // "0800"
          'start': start,     // "08:00"
          'end': end,         // "09:00" if available
          'status': 'upcoming',
          'createdAt': FieldValue.serverTimestamp(),
        };

        await _createBookingPickSeatTx(
          facilityId: widget.facilityId,
          dateYMD: widget.dateYMD,
          slotKey: slotKey,
          seatIndex: seatIndex,
          bookingBase: bookingBase,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking(s) created')),
      );
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
    } catch (e) {
      if (!mounted) return;
      final msg = ('$e'.contains('TAKEN'))
          ? 'One of the selected seats was just taken. Please pick another.'
          : ('$e'.contains('FULL'))
          ? 'One or more selected times are full.'
          : 'Failed to create booking: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double barHeight = MediaQuery.of(context).size.height * 0.07;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          centerTitle: true,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            tooltip: 'Back',
          ),
          title: Text('Pick a slot',
              style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w600)),
          actions: [
            IconButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => AndroidListOfFacilities()),
                      (route) => false,
                );
              },
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Close',
            ),
          ],
        ),
      ),

      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('Facilities')
              .doc(widget.facilityId)
              .snapshots(),
          builder: (context, facSnap) {
            if (facSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!facSnap.hasData || facSnap.data!.data() == null) {
              return const Center(child: Text('Facility not found'));
            }

            final fac = facSnap.data!.data()!;
            final int capacity = (fac['availableSlots'] is int)
                ? fac['availableSlots'] as int
                : int.tryParse('${fac['availableSlots']}') ?? 1;
            final int cap = capacity > 0 ? capacity : 1;

            // Ledger for this day -> reserved per time
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('Facilities').doc(widget.facilityId)
                  .collection('Days').doc(widget.dateYMD)
                  .collection('Slots')
                  .snapshots(),
              builder: (context, slotsSnap) {
                // slotKey -> reserved
                final Map<String, int> reservedByKey = {};
                if (slotsSnap.hasData) {
                  for (final d in slotsSnap.data!.docs) {
                    final m = d.data();
                    final int r = (m['reserved'] is int)
                        ? m['reserved'] as int
                        : int.tryParse('${m['reserved']}') ?? 0;
                    reservedByKey[d.id] = r < 0 ? 0 : r;
                  }
                }

                final List<Widget> sections = <Widget>[];
                for (final start in widget.startTimes) {
                  final key = _slotKey(start);
                  final reserved = reservedByKey[key] ?? 0;
                  final used = reserved.clamp(0, cap);

                  sections.add(_TimeSection(
                    startLabel: _toAmPmDotStart(start),
                    capacity: cap,
                    reserved: used,
                    chosenIndex: _pick[start],
                    onPick: (idx) {
                      setState(() => _pick[start] = idx);
                    },
                  ));

                  sections.add(SizedBox(height: 12.h));
                }

                return Stack(
                  children: [
                    SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h)
                          .copyWith(bottom: 96.h),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: 8.h),
                          Center(
                            child: Column(
                              children: [
                                Text(
                                  _niceDate(widget.dateYMD),
                                  style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  widget.facilityName,
                                  style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 6.h),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.info_outline, size: 14.sp, color: Colors.black54),
                                    SizedBox(width: 6.w),
                                    Text(
                                      'Only one slot can be chosen for each time',
                                      style: TextStyle(fontSize: 12.5.sp, color: Colors.black54, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 14.h),
                          ...sections,
                        ],
                      ),
                    ),

                    Positioned(
                      left: 16.w,
                      right: 16.w,
                      bottom: 16.h,
                      child: SizedBox(
                        height: 48.h,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF9747FF),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28.r)),
                          ),
                          onPressed: _saving
                              ? null
                              : () {
                            if (_pick.length != widget.startTimes.length) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please pick one slot for each time.')),
                              );
                              return;
                            }
                            _onConfirmPressed(fac: fac);
                          },
                          child: Text(
                            _saving ? 'Saving...' : 'Confirm',
                            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),

      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }
}

/// A single “time box” (e.g., “8.00 am” then Slot 1..N chips in 3 per row)
class _TimeSection extends StatelessWidget {
  const _TimeSection({
    Key? key,
    required this.startLabel,
    required this.capacity,
    required this.reserved,
    required this.chosenIndex,
    required this.onPick,
  }) : super(key: key);

  final String startLabel;
  final int capacity;     // total slots
  final int reserved;     // how many are already taken (0..capacity)
  final int? chosenIndex; // user’s pick (1..capacity)
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final double fullW = 1.0.sw - 32.w;
    final double gap = 8.w;
    final double chipW = (fullW - (gap * 2.0)) / 3.0;

    final List<Widget> chips = <Widget>[];
    for (int i = 1; i <= capacity; i++) {
      final bool isTaken = i <= reserved;       // NOTE: uses first-N heuristic
      final bool isChosen = chosenIndex == i;   // picked by user

      Color fill;
      Color border;
      Color text;

      if (isTaken) {
        fill = const Color(0xFFFFE7E9);
        border = const Color(0xFFFF6B7A);
        text = const Color(0xFFB00020);
      } else if (isChosen) {
        fill = const Color(0xFF9747FF);
        border = const Color(0xFF4A00B8);
        text = Colors.white;
      } else {
        fill = const Color(0xFFB779F1);
        border = const Color(0xFF6E00D4);
        text = Colors.white;
      }

      chips.add(
        InkWell(
          onTap: isTaken ? null : () => onPick(i),
          borderRadius: BorderRadius.circular(20.r),
          child: Container(
            width: chipW,
            height: 40.h,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(color: border, width: isChosen ? 2.0 : 1.5),
            ),
            child: Text(
              'Slot $i',
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: text),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 1.0.sw,
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(startLabel, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
          SizedBox(height: 8.h),
          Wrap(spacing: gap, runSpacing: gap, children: chips),
        ],
      ),
    );
  }
}
