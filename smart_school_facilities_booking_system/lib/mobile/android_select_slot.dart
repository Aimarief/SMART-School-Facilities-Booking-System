import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore access
import 'package:flutter/material.dart';               // Flutter UI widgets
import 'package:flutter_screenutil/flutter_screenutil.dart'; // .w .h .sp responsive units

// bottom nav + pages (kept as original navigation behavior)
import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart';

// ------------------------------
// Page: SelectSlot (stateful)
// ------------------------------
class SelectSlot extends StatefulWidget {
  // facility doc id (to read capacity + seat collections)
  final String facilityId;
  // facility name (for header display)
  final String facilityName;
  // booking date in "YYYY-MM-DD" (for Days/doc id)
  final String dateYMD;
  // list of time strings "HH:mm" (each renders a section)
  final List<String> startTimes;

  // ctor only wires required arguments
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

// ----------------------------------------
// State: holds selections and live toggles
// ----------------------------------------
class _SelectSlotState extends State<SelectSlot> {
  // bottom bar index (2 = Facilities)
  int _currentIndex = 2;

  // parent map of picks: time("08:00") -> seat index (1-based)
  final Map<String, int> _pick = <String, int>{};

  // picked count notifier (drives Confirm button enabled state)
  final ValueNotifier<int> _pickedCount = ValueNotifier<int>(0);

  // loading flag while reading facility capacity once
  bool _loadingFacility = true;
  // unused saving flag preserved (kept for Confirm label text)
  bool _saving = false;
  // facility capacity (1..N, default 1)
  int _capacity = 1;

  // init: load facility capacity once
  @override
  void initState() {
    super.initState();
    _loadFacilityOnce();
  }

  // dispose: release notifier
  @override
  void dispose() {
    _pickedCount.dispose();
    super.dispose();
  }

  // --------------------------
  // Data: read capacity once
  // --------------------------
  Future<void> _loadFacilityOnce() async {
    try {
      // read Facilities/{facilityId} to get availableSlots
      final doc = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .get();

      int cap = 1;
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          // parse availableSlots as int, accept numeric string fallback
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

      // enforce minimum capacity = 1
      if (cap <= 0) {
        cap = 1;
      }

      // store capacity in state field
      _capacity = cap;
    } catch (_) {
      // fallback capacity on any error
      _capacity = 1;
    }

    // mark loading as done (if still mounted)
    if (mounted) {
      setState(() {
        _loadingFacility = false;
      });
    }
  }

  // ----------------------------------------
  // Bottom nav: route by tapped index (kept)
  // ----------------------------------------
  void _onTabSelected(int i) {
    if (i == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidListOfFacilities()));
    } else {
      if (i == 0) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AndroidAgenda()));
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

  // turn "HH:mm" into "HHmm" (always 4 digits for slot doc id)
  String _slotKey4(String hhmm) {
    String s = hhmm.replaceAll(':', '');
    if (s.length < 4) {
      s = s.padLeft(4, '0');
    }
    return s; // "08:00" -> "0800", "8:00" -> "0800"
  }

  // format "HH:mm" into "h.mm am/pm" (12h with dot minutes)
  String _toAmPmDot(String hhmm) {
    final p = hhmm.split(':');
    int hour = 0;
    int minute = 0;

    // parse hour safely
    if (p.isNotEmpty) {
      final int? h = int.tryParse(p[0]);
      if (h != null) {
        hour = h;
      }
    }
    // parse minute safely
    if (p.length > 1) {
      final int? m = int.tryParse(p[1]);
      if (m != null) {
        minute = m;
      }
    }

    // decide suffix by 24h hour
    String suffix = 'am';
    if (hour >= 12) {
      suffix = 'pm';
    }

    // convert 24h to 12h range
    int h12 = hour % 12;
    if (h12 == 0) {
      h12 = 12;
    }

    // pad minute 2-digit and build "h.mm am/pm"
    final String mm = minute.toString().padLeft(2, '0');
    return '$h12.$mm $suffix';
  }

  // format "YYYY-MM-DD" into "D Month YYYY" nice label
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
      // fallback to raw input on parse failure
      return ymd;
    }
  }

  // selection callback from child → update parent map and count
  void _onPickChanged(String start, int? idx) {
    if (idx == null) {
      // remove pick for this start time when deselected
      _pick.remove(start);
    } else {
      // keep only valid range [1..capacity]
      if (idx >= 1) {
        if (idx <= _capacity) {
          _pick[start] = idx;
        }
      }
    }
    // notify picked count to refresh Confirm button
    _pickedCount.value = _pick.length;
  }

  // ---------------
  // Build the page
  // ---------------
  @override
  Widget build(BuildContext context) {
    // bottom bar height ratio to screen
    final double barHeight = MediaQuery.of(context).size.height * 0.07;

    // dynamic Confirm label when "saving" (kept same semantics)
    String confirmText = 'Confirm';
    if (_saving) {
      confirmText = 'Saving...';
    }

    // decide body content (spinner vs sections)
    Widget bodyChild;
    if (_loadingFacility) {
      // show loader while facility capacity loads
      bodyChild = Center(
        child: SizedBox(width: 28.w, height: 28.w, child: const CircularProgressIndicator()),
      );
    } else {
      // main content stack (scroll list + bottom Confirm)
      bodyChild = Stack(
        children: [
          // scrollable list of sections with extra bottom padding
          SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h).copyWith(bottom: 96.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 8.h),

                // header: date, facility, and tip text
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

                // time sections for each start time (built below)
                ..._buildTimeSections(),
              ],
            ),
          ),

          // bottom-aligned Confirm button that enables only when all times picked
          Positioned(
            left: 16.w,
            right: 16.w,
            bottom: 16.h,
            child: ValueListenableBuilder<int>(
              valueListenable: _pickedCount,
              builder: (context, count, _) {
                // ready when not saving and count equals total times
                bool ready = false;
                if (!_saving) {
                  if (count == widget.startTimes.length) {
                    ready = true;
                  }
                }

                // choose handler based on ready flag
                VoidCallback? onPressed;
                if (ready) {
                  onPressed = () {
                    // return a shallow copy of picks back to previous page
                    Navigator.pop<Map<String, int>>(context, Map<String, int>.from(_pick));
                  };
                } else {
                  onPressed = null;
                }

                // render full-width rounded button
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

    // scaffold with purple app bar + bottom nav
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
              // go back to previous screen (do not modify stack otherwise)
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
                // close and jump to Facilities root, clearing back stack
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

      // safe area around the dynamically chosen body
      body: SafeArea(child: bodyChild),

      // bottom persistent navigation bar (kept same behavior)
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }

  // ---------------------------------------------------------
  // Build all sections (one section per provided start time)
  // ---------------------------------------------------------
  List<Widget> _buildTimeSections() {
    // collector for output widgets
    final List<Widget> out = <Widget>[];

    // iterate times in original order (kept)
    int i = 0;
    while (i < widget.startTimes.length) {
      final String start = widget.startTimes[i];
      final String slotKey = _slotKey4(start);  // convert "HH:mm" -> "HHmm"
      final String label = _toAmPmDot(start);   // convert "HH:mm" -> "h.mm am/pm"

      // live stream to Seats collection for this time section
      final Stream<QuerySnapshot<Map<String, dynamic>>> seatsStream =
      FirebaseFirestore.instance
          .collection('Facilities').doc(widget.facilityId)
          .collection('Days').doc(widget.dateYMD)
          .collection('Slots').doc(slotKey)
          .collection('Seats')
          .snapshots();

      // append a time section with props + callback to parent
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

      // vertical gap between sections
      out.add(SizedBox(height: 12.h));

      // next time
      i = i + 1;
    }

    // return layout list
    return out;
  }
}

// ============================================================
// Child widget: a single time section showing 1..capacity chips
// - Listens to Seats/* for taken:true -> disabled/red chip
// - Holds one local chosen index; notifies parent on change
// - Keeps state alive when scrolled (AutomaticKeepAlive)
// ============================================================
class _TimeSection extends StatefulWidget {
  // label like "8.00 am" derived from time
  const _TimeSection({
    Key? key,
    required this.startLabel,
    required this.capacity,
    required this.seatsStream,
    required this.initialChosenIndex,
    required this.onPickChanged,
  }) : super(key: key);

  // readable time label
  final String startLabel;
  // number of chips to render (1..capacity)
  final int capacity;
  // Firestore stream for Seats documents under this time slot
  final Stream<QuerySnapshot<Map<String, dynamic>>> seatsStream;
  // initial chosen seat index (null if none yet)
  final int? initialChosenIndex;
  // callback back to parent with new chosen index (or null)
  final ValueChanged<int?> onPickChanged;

  @override
  State<_TimeSection> createState() => _TimeSectionState();
}

// ------------------------------------------------------------
// State: maintain one chosen index and reflect live taken seats
// ------------------------------------------------------------
class _TimeSectionState extends State<_TimeSection> with AutomaticKeepAliveClientMixin {
  // currently chosen seat index (1-based) or null when not picked
  int? _chosenIndex;

  // init: hydrate chosen index from parent initial value
  @override
  void initState() {
    super.initState();
    _chosenIndex = widget.initialChosenIndex;
  }

  // keep alive when offscreen for smoother scroll UX
  @override
  bool get wantKeepAlive => true;

  // parse seat doc id into numeric index (accepts "1", "seat1", etc.)
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

  // build a single time section with chips that reflect live "taken" seats
  @override
  Widget build(BuildContext context) {
    super.build(context);

    // compute chip widths for 3 columns layout
    final double fullW = 1.0.sw - 32.w;
    final double gap = 8.w;
    final double chipW = (fullW - (gap * 2.0)) / 3.0;

    // stream builder listens to Seats/* for this time
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.seatsStream,
      builder: (context, snap) {
        // collect numeric seat indices that are hard-taken (taken:true)
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

        // if my local chosen seat turned taken:true, clear and notify parent
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

        // create chips for seat indices 1..capacity
        final List<Widget> chips = <Widget>[];
        for (int i = 1; i <= widget.capacity; i++) {
          // capture this iteration's index for tap handler
          final int idx = i;

          // compute isTaken from live set
          final bool isTaken = takenTrue.contains(idx);

          // compute isChosen from local state
          bool isChosen = false;
          if (_chosenIndex != null) {
            if (_chosenIndex == idx) {
              isChosen = true;
            }
          }

          // choose chip colors based on taken/chosen states
          Color fill;
          Color border;
          Color text;

          if (isTaken) {
            // taken:true -> red/disabled
            fill = const Color(0xFFFFE7E9);
            border = const Color(0xFFFF6B7A);
            text = const Color(0xFFB00020);
          } else {
            if (isChosen) {
              // my current pick -> purple strong
              fill = const Color(0xFF9747FF);
              border = const Color(0xFF4A00B8);
              text = Colors.white;
            } else {
              // available but not chosen -> softer purple
              fill = const Color(0xFFB779F1);
              border = const Color(0xFF6E00D4);
              text = Colors.white;
            }
          }

          // handle taps only when not taken
          VoidCallback? onTap;
          if (isTaken) {
            onTap = null;
          } else {
            onTap = () {
              // set local chosen index and notify parent
              setState(() {
                _chosenIndex = idx;
              });
              widget.onPickChanged(idx);
            };
          }

          // push a single chip with Material/InkWell for ripple feedback
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

        // section card with title + chip grid (Wrap)
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
              // time label like "8.00 am"
              Text(widget.startLabel, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
              SizedBox(height: 8.h),
              // chips grid with spacing + run wrap for multiple rows
              Wrap(spacing: gap, runSpacing: gap, children: chips),
            ],
          ),
        );
      },
    );
  }
}
