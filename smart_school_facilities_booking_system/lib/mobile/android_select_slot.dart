import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'android_bottom_menu.dart';
import 'android_agenda.dart';
import 'android_view_booking.dart';
import 'android_notifications.dart';
import 'android_account.dart';
import 'android_list_of_facilities.dart';


class SelectSlot extends StatefulWidget {

  final String facilityId;
  final String facilityName;
  final String dateYMD;
  final List<String> startTimes;

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
  //---------------------------------------
// current page
//---------------------------------------

  int _currentIndex = 2;

  final Map<String, int> _pick = <String, int>{};

  final ValueNotifier<int> _pickedCount = ValueNotifier<int>(0);

  bool _loadingFacility = true;
  bool _saving = false;
  int _capacity = 1;
  int _availableDuration = 1;
//---------------------------------------
// run init state first
//---------------------------------------
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

//---------------------------------------
// get the facilities from database
//---------------------------------------

  Future<void> _loadFacilityOnce() async {

    try {
      final doc = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .get();
//---------------------------------------
// get available slots
//---------------------------------------
      int cap = 1;
      int slotDuration = 1;
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
           cap = data['availableSlots'] as int;
           slotDuration = data['bookingDurationHours'] as int;

        }
      }

      if (cap <= 0) {
        cap = 1;
      }

      _capacity = cap;
      _availableDuration = slotDuration;


    } catch (_) {
      // fallback capacity on any error
      _capacity = 1;
    }

    if (mounted) {
      setState(() {
        _loadingFacility = false;
      });
    }
  }

//---------------------------------------
// navigation for different page
//---------------------------------------
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

//---------------------------------------
// turn time into slot key format
//---------------------------------------

  String _slotKey4(String hhmm) {
    String s = hhmm.replaceAll(':', '');
    if (s.length < 4) {
      s = s.padLeft(4, '0');
    }
    return s; // "08:00" -> "0800", "8:00" -> "0800"
  }

//---------------------------------------
// format time to am pm
//---------------------------------------
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

    final String mm = minute.toString().padLeft(2, '0');
    return '$h12.$mm $suffix';
  }

//---------------------------------------
// format date to day month and year
//---------------------------------------

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

//---------------------------------------
// main build
//---------------------------------------

  @override
  Widget build(BuildContext context) {
    final double barHeight = MediaQuery.of(context).size.height * 0.07;

    String confirmText = 'Confirm';
    if (_saving) {
      confirmText = 'Saving...';
    }

//---------------------------------------
// while still loading
//---------------------------------------
    Widget bodyChild;

    if (_loadingFacility) {
      bodyChild = Center(
        child: SizedBox(width: 28.w, height: 28.w, child: const CircularProgressIndicator()),
      );
    } else {
      //---------------------------------------
// main design 2
//---------------------------------------
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
//---------------------------------------
// display date
//---------------------------------------
                      Text(
                        _niceDate(widget.dateYMD),
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 4.h),
//---------------------------------------
// facility name
//---------------------------------------
                      Text(
                        widget.facilityName,
                        style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 6.h),
//---------------------------------------
// display tips
//---------------------------------------
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline, size: 14.sp, color: Colors.black54),
                          SizedBox(width: 6.w),
                          Text(
                            'Pick exactly one seat for each time',
                            style: TextStyle(fontSize: 12.5.sp, color: Colors.black54, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height:6.h),

                        ],
                      ),
//---------------------------------------
// booking duration
//---------------------------------------
                      Text(
                        'Booking per slot is $_availableDuration hour',
                        style: TextStyle(fontSize: 12.5.sp, color: Colors.black, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 14.h),

//---------------------------------------
// time section
//---------------------------------------
                ..._buildTimeSections(),
              ],
            ),
          ),

//---------------------------------------
// confirm button
//---------------------------------------
          Positioned(
            left: 16.w,
            right: 16.w,
            bottom: 16.h,
            child: ValueListenableBuilder<int>(
              valueListenable: _pickedCount,
              builder: (context, count, _) {
                bool ready = false;
                //---------------------------------------
// check count first to make sure all seat slot is picked
//---------------------------------------
                if (!_saving) {
                  if (count == widget.startTimes.length) {
                    ready = true;
                  }
                }

                VoidCallback? onPressed;
                if (ready) {
                  onPressed = () {
//---------------------------------------
// copy the picked time and back to previous page
//---------------------------------------
                    Navigator.pop<Map<String, int>>(context, Map<String, int>.from(_pick));
                  };
                } else {
                  onPressed = null;
                }
//---------------------------------------
// button design
//---------------------------------------
                return SizedBox(
                  height: 48.h,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (onPressed == null)
                          ? Colors.grey // disabled state
                          : const Color(0xFF9747FF),
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

//---------------------------------------
// main design 1
//---------------------------------------
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

//---------------------------------------
// call teh body child widget
//---------------------------------------
      body: SafeArea(child: bodyChild),
//---------------------------------------
// bottom navigate
//---------------------------------------
      bottomNavigationBar: BottomMenuBar(
        height: barHeight,
        currentIndex: _currentIndex,
        onTabSelected: _onTabSelected,
      ),
    );
  }

//---------------------------------------
// build the slot selection
//---------------------------------------
  List<Widget> _buildTimeSections() {
    final List<Widget> out = <Widget>[];
    int i = 0;
    while (i < widget.startTimes.length) {
      final String start = widget.startTimes[i]; // "08:00"
      out.add(_buildOneTimeSection(start));      // build directly
      out.add(SizedBox(height: 12.h));           // space between sections
      i = i + 1;
    }
    return out;
  }

//---------------------------------------
// turn slot into number int format
//---------------------------------------

  int _idxFromSeatId(String id) {
    final int? a = int.tryParse(id);
    if (a != null) return a;
    final String onlyNum = id.replaceAll(RegExp(r'[^0-9]'), '');
    final int? b = int.tryParse(onlyNum);
    if (b != null) return b;
    return -1;
  }
//---------------------------------------
// build slot for 1 section
//---------------------------------------

  Widget _buildOneTimeSection(String start) {

    final String slotKey = _slotKey4(start);        // "0800"
    final String label = _toAmPmDot(start);         // "8.00 am"
    final Stream<QuerySnapshot<Map<String, dynamic>>> seatsStream =
    FirebaseFirestore.instance
        .collection('Facilities').doc(widget.facilityId)
        .collection('Days').doc(widget.dateYMD)
        .collection('Slots').doc(slotKey)
        .collection('Seats')
        .snapshots();

    //---------------------------------------
// set the size
//---------------------------------------

    final double fullW = 1.0.sw - 65.w;
    final double gap = 8.w;
    final double chipW = (fullW - (gap * 2.0)) / 3.0;

    //---------------------------------------
// check all the slot wether its taken or not taken
//---------------------------------------

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: seatsStream,
      builder: (context, snap) {
        final Set<int> takenTrue = <int>{};
        if (snap.hasData) {
          int k = 0;
          while (k < snap.data!.docs.length) {
            final d = snap.data!.docs[k];
            final int idx = _idxFromSeatId(d.id);
            if (idx > 0) {
              bool isTaken = false;
              final Map<String, dynamic> m = d.data();
              if (m.containsKey('taken')) {
                final dynamic t = m['taken'];
                if (t is bool && t == true) {
                  isTaken = true;
                }
              }
              if (isTaken)
                takenTrue.add(idx);
            }
            k = k + 1;
          }
        }

        final int? chosenIdx = _pick[start];

//---------------------------------------
// if there is someone just book
//---------------------------------------
        if (chosenIdx != null && takenTrue.contains(chosenIdx)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _pick.remove(start);             // remove pick
                _pickedCount.value = _pick.length; // update count
              });
            }
          });
        }

        final List<Widget> chips = <Widget>[];
        int i = 1;
        while (i <= _capacity) {
          final int idx = i;
          final bool isTaken = takenTrue.contains(idx);
          final bool isChosen = (chosenIdx == idx);

          //---------------------------------------
// design gor each chip
//---------------------------------------

          Color fill, border, text;
          double borderW = isChosen ? 2.0 : 1.5;
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

//---------------------------------------
// disable taken , while also once value is pick add pick length
//---------------------------------------

          VoidCallback? onTap;
          if (isTaken) {
            onTap = null; // disable
          } else {
            onTap = () {
              setState(() {
                if (isChosen) {
                  _pick.remove(start);// unpick
                } else {
                  _pick[start] = idx;// pick
                }
                _pickedCount.value = _pick.length;
              });
            };
          }
//---------------------------------------
// each button design
//---------------------------------------
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
                    border: Border.all(color: border, width: borderW),
                  ),
                  child: Text(
                    'Slot $idx',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: text),
                  ),
                ),
              ),
            ),
          );

          i = i + 1;
        }

//---------------------------------------
// main design 3 full container design for each cheap
//---------------------------------------

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
              Text(label, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
              SizedBox(height: 8.h),
              Wrap(spacing: gap, runSpacing: gap, children: chips), // left to right then wrap
            ],
          ),
        );
      },
    );
  }
}
