// android_select_slot.dart
//
// What this page does:
// - Show the chosen booking date and facility name.
// - For each selected start time, show a box with seat chips: Slot 1..N,
//   where N = Facilities.availableSlots.
// - A chip is disabled (red) ONLY if its Firestore doc has { taken: true } at:
//   Facilities/{facilityId}/Days/{dateYMD}/Slots/{HHmm}/Seats/{seatIndex}.
//   If the seat doc is missing OR has { taken:false }, it is selectable.
// - User must choose exactly one seat per start time. Confirm returns a map
//   like { "08:00": 2, "09:00": 1 } back to the previous page.
//
// Rules you asked for:
// - Always use 4-digit slot keys (HHmm).
// - No ternary (?:) and no null-coalescing (??).
// - Use .w .h .sp for sizes.
// - This page DOES NOT write into Days/* — only reads. Confirm just returns
//   the selections; your ConfirmBooking/booking_service will perform writes.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'android_bottom_menu.dart';
import 'android_calendar.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart';

class SelectSlot extends StatefulWidget {
  final String facilityId;
  final String facilityName;
  final String dateYMD;          // "YYYY-MM-DD" (booking date)
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
  // bottom bar index (2 = Facilities)
  int _currentIndex = 2;

  // parent keeps selections: time("08:00") -> seat index (1-based)
  final Map<String, int> _pick = <String, int>{};

  // only the Confirm button listens to this count
  final ValueNotifier<int> _pickedCount = ValueNotifier<int>(0);

  // loading/capacity
  bool _loadingFacility = true;
  bool _saving = false;
  int _capacity = 1;

  @override
  void initState() {
    super.initState();
    _loadFacilityOnce();
  }

  @override
  void dispose() {
    _pickedCount.dispose();
    super.dispose();
  }

  // ---------- Data helpers ----------
  Future<void> _loadFacilityOnce() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .get();

      int cap = 1;
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          final dynamic v = data['availableSlots'];
          if (v is int) {
            cap = v;
          } else {
            final int? p = int.tryParse('$v');
            if (p != null) {
              cap = p;
            }
          }
        }
      }
      if (cap <= 0) {
        cap = 1;
      }
      _capacity = cap;
    } catch (_) {
      _capacity = 1;
    }

    if (mounted) {
      setState(() {
        _loadingFacility = false;
      });
    }
  }

  // ---------- UI helpers ----------
  void _onTabSelected(int i) {
    if (i == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
    } else {
      if (i == 0) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidCalendar()));
      } else {
        if (i == 1) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidViewBooking()));
        } else {
          if (i == 3) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidNotifications()));
          } else {
            if (i == 4) {
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAccount()));
            }
          }
        }
      }
    }
  }

  String _slotKey4(String hhmm) {
    String s = hhmm.replaceAll(':', '');
    if (s.length < 4) {
      s = s.padLeft(4, '0');
    }
    return s; // "08:00" -> "0800", "8:00" -> "0800"
  }

  String _toAmPmDot(String hhmm) {
    final p = hhmm.split(':');
    int hour = 0;
    int minute = 0;

    if (p.isNotEmpty) {
      final int? h = int.tryParse(p[0]);
      if (h != null) {
        hour = h;
      }
    }
    if (p.length > 1) {
      final int? m = int.tryParse(p[1]);
      if (m != null) {
        minute = m;
      }
    }

    String suffix = 'am';
    if (hour >= 12) {
      suffix = 'pm';
    }
    int h12 = hour % 12;
    if (h12 == 0) {
      h12 = 12;
    }
    final String mm = minute.toString().padLeft(2, '0');
    return '$h12.$mm $suffix';
  }

  String _niceDate(String ymd) {
    try {
      final parts = ymd.split('-');
      final int y = int.parse(parts[0]);
      final int m = int.parse(parts[1]);
      final int d = int.parse(parts[2]);

      const months = [
        'January','February','March','April','May','June',
        'July','August','September','October','November','December'
      ];
      return '$d ${months[m - 1]} $y';
    } catch (_) {
      return ymd;
    }
  }

  // child -> parent selection change
  void _onPickChanged(String start, int? idx) {
    if (idx == null) {
      _pick.remove(start);
    } else {
      if (idx >= 1) {
        if (idx <= _capacity) {
          _pick[start] = idx; // enforce range safety here too
        }
      }
    }
    _pickedCount.value = _pick.length;
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    final double barHeight = MediaQuery.of(context).size.height * 0.07;

    String confirmText = 'Confirm';
    if (_saving) {
      confirmText = 'Saving...';
    }

    Widget bodyChild;
    if (_loadingFacility) {
      bodyChild = Center(
        child: SizedBox(width: 28.w, height: 28.w, child: const CircularProgressIndicator()),
      );
    } else {
      bodyChild = Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h).copyWith(bottom: 96.h),
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
                            'Pick exactly one seat for each time',
                            style: TextStyle(fontSize: 12.5.sp, color: Colors.black54, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14.h),
                ..._buildTimeSections(),
              ],
            ),
          ),

          // confirm button (enabled when picked == startTimes.length)
          Positioned(
            left: 16.w,
            right: 16.w,
            bottom: 16.h,
            child: ValueListenableBuilder<int>(
              valueListenable: _pickedCount,
              builder: (context, count, _) {
                bool ready = false;
                if (!_saving) {
                  if (count == widget.startTimes.length) {
                    ready = true;
                  }
                }

                VoidCallback? onPressed;
                if (ready) {
                  onPressed = () {
                    Navigator.pop<Map<String, int>>(context, Map<String, int>.from(_pick));
                  };
                } else {
                  onPressed = null;
                }

                return SizedBox(
                  height: 48.h,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF9747FF),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28.r)),
                    ),
                    onPressed: onPressed,
                    child: Text(
                      confirmText,
                      style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.h),
        child: AppBar(
          backgroundColor: const Color(0xFF9747FF),
          centerTitle: true,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: Icon(Icons.arrow_back, color: Colors.white, size: 20.sp),
            tooltip: 'Back',
          ),
          title: Text(
            'Pick a slot',
            style: TextStyle(color: Colors.white, fontSize: 18.sp, fontWeight: FontWeight.w600),
          ),
          actions: [
            IconButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => AndroidListOfFacilities()),
                      (route) => false,
                );
              },
              icon: Icon(Icons.close, color: Colors.white, size: 20.sp),
              tooltip: 'Close',
            ),
          ],
        ),
      ),

      body: SafeArea(child: bodyChild),

      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }

  // ---------- Sections (one per start time) ----------
  List<Widget> _buildTimeSections() {
    final List<Widget> out = <Widget>[];

    int i = 0;
    while (i < widget.startTimes.length) {
      final String start = widget.startTimes[i];
      final String slotKey = _slotKey4(start); // ALWAYS "HHmm"
      final String label = _toAmPmDot(start);

      final Stream<QuerySnapshot<Map<String, dynamic>>> seatsStream =
      FirebaseFirestore.instance
          .collection('Facilities').doc(widget.facilityId)
          .collection('Days').doc(widget.dateYMD)
          .collection('Slots').doc(slotKey)
          .collection('Seats')
          .snapshots();

      out.add(
        _TimeSection(
          startLabel: label,
          capacity: _capacity,
          seatsStream: seatsStream,
          initialChosenIndex: _pick[start],
          onPickChanged: (int? idx) {
            _onPickChanged(start, idx);
          },
        ),
      );

      out.add(SizedBox(height: 12.h));
      i = i + 1;
    }

    return out;
  }
}

// A single time-box that listens to Seats/* and renders 1..capacity chips.
// A chip is red/disabled only if the doc has { taken:true }.
class _TimeSection extends StatefulWidget {
  const _TimeSection({
    Key? key,
    required this.startLabel,
    required this.capacity,
    required this.seatsStream,
    required this.initialChosenIndex,
    required this.onPickChanged,
  }) : super(key: key);

  final String startLabel;
  final int capacity;
  final Stream<QuerySnapshot<Map<String, dynamic>>> seatsStream;
  final int? initialChosenIndex;
  final ValueChanged<int?> onPickChanged;

  @override
  State<_TimeSection> createState() => _TimeSectionState();
}

class _TimeSectionState extends State<_TimeSection> with AutomaticKeepAliveClientMixin {
  int? _chosenIndex;

  @override
  void initState() {
    super.initState();
    _chosenIndex = widget.initialChosenIndex;
  }

  @override
  bool get wantKeepAlive => true;

  int _idxFromSeatId(String id) {
    final int? a = int.tryParse(id);
    if (a != null) {
      return a;
    } else {
      final String onlyNum = id.replaceAll(RegExp(r'[^0-9]'), '');
      final int? b = int.tryParse(onlyNum);
      if (b != null) {
        return b;
      } else {
        return -1;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final double fullW = 1.0.sw - 32.w;
    final double gap = 8.w;
    final double chipW = (fullW - (gap * 2.0)) / 3.0;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.seatsStream,
      builder: (context, snap) {
        // Identify ONLY seats that are hard-taken (taken:true)
        final Set<int> takenTrue = <int>{};

        if (snap.hasData) {
          int k = 0;
          while (k < snap.data!.docs.length) {
            final d = snap.data!.docs[k];
            final int idx = _idxFromSeatId(d.id);
            if (idx > 0) {
              bool hard = false;
              final Map<String, dynamic> m = d.data();
              if (m.containsKey('taken')) {
                final dynamic t = m['taken'];
                if (t is bool) {
                  if (t == true) {
                    hard = true;
                  }
                }
              }
              if (hard) {
                takenTrue.add(idx);
              }
            }
            k = k + 1;
          }
        }

        // If my chosen seat became taken:true, clear it and notify parent
        if (_chosenIndex != null) {
          if (takenTrue.contains(_chosenIndex!)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _chosenIndex = null;
                });
                widget.onPickChanged(null);
              }
            });
          }
        }

        // Build chips 1..capacity (IMPORTANT: capture per-iteration idx)
        final List<Widget> chips = <Widget>[];
        for (int i = 1; i <= widget.capacity; i++) {
          final int idx = i; // <-- capture the value for this chip

          final bool isTaken = takenTrue.contains(idx);

          bool isChosen = false;
          if (_chosenIndex != null) {
            if (_chosenIndex == idx) {
              isChosen = true;
            }
          }

          Color fill;
          Color border;
          Color text;

          if (isTaken) {
            // taken:true -> hard block (red)
            fill = const Color(0xFFFFE7E9);
            border = const Color(0xFFFF6B7A);
            text = const Color(0xFFB00020);
          } else {
            if (isChosen) {
              fill = const Color(0xFF9747FF);
              border = const Color(0xFF4A00B8);
              text = Colors.white;
            } else {
              fill = const Color(0xFFB779F1);
              border = const Color(0xFF6E00D4);
              text = Colors.white;
            }
          }

          VoidCallback? onTap;
          if (isTaken) {
            onTap = null;
          } else {
            onTap = () {
              setState(() {
                _chosenIndex = idx;
              });
              widget.onPickChanged(idx);
            };
          }

          // Ensure reliable taps (Material parent for InkWell)
          chips.add(
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
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
                    'Slot $idx',
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: text),
                  ),
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
              Text(widget.startLabel, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
              SizedBox(height: 8.h),
              Wrap(spacing: gap, runSpacing: gap, children: chips),
            ],
          ),
        );
      },
    );
  }
}
