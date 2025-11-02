import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

class BookingService {
  static const String _bookingsCol = 'Bookings';

  //---------------------------------------
// make the key to hhmm no :
//---------------------------------------

  static String _normalizeSlotKey(String raw) {
    String s = raw.trim();
    if (s.contains(':')) {
      s = s.replaceAll(':', '');
    }
    if (s.length < 4) {
      s = s.padLeft(4, '0');
    }
    return s;
  }

//---------------------------------------
// get the facility available slots
//---------------------------------------

  static Future<int> _readCapacityOutsideTxn({
    required String facilityId,
    required String dateYMD,
    required String slotKey,
  }) async {
    int cap = 1;

    try {

        final facSnap = await FirebaseFirestore.instance
            .collection('Facilities').doc(facilityId).get();

        if (facSnap.exists) {
          final Map<String, dynamic>? f = facSnap.data();
          if (f != null && f.containsKey('availableSlots')) {
            final int a = f['availableSlots'] as int;
              cap = a;
          }
        }
    } catch (_) {}
    if (cap <= 0) cap = 1;
    return cap;
  }

//---------------------------------------
// get full date and time
//---------------------------------------

  static DateTime? _startAtLocalFromYMDAndTime(String dateYMD, {String? slotKey, String? startStr}) {
    try {
      //---------------------------------------
// parse the date
//---------------------------------------
      final parts = dateYMD.split('-');            // "2025-09-10"
      if (parts.length != 3) return null;
      final int y = int.parse(parts[0]);
      final int m = int.parse(parts[1]);
      final int d = int.parse(parts[2]);

      String time = '';
      if (startStr != null && startStr.trim().isNotEmpty) {
        time = startStr.trim();                    //  "09:30"
      } else {
        return null;
      }

      //---------------------------------------
// parse the hour
//---------------------------------------
      final tp =time.split(':');
      final int hh = int.parse(tp[0]);
      final int mm = int.parse(tp[1]);
//---------------------------------------
// make a full date time
//---------------------------------------
      return DateTime(y, m, d, hh, mm);
    } catch (_) {
      return null;
    }
  }

//---------------------------------------
// read available slot
//---------------------------------------
  static Future<int> _txReadCapacity(
      Transaction txn, {
        required DocumentReference<Map<String, dynamic>> slotRef,
        required DocumentReference<Map<String, dynamic>> facRef,
      }) async {
    int cap = 1;
    try {
        final f = await txn.get(facRef);
        if (f.exists) {
          final Map<String, dynamic>? d = f.data();
          if (d != null && d.containsKey('availableSlots')) {
            final dynamic a = d['availableSlots'];
            if (a is int) {
              cap = a;
            } else {
              final int? p = int.tryParse('$a');
              if (p != null) cap = p;
            }
          }
        }

    } catch (_) {}
    if (cap <= 0) cap = 1;
    return cap;
  }
//---------------------------------------
// get the booked amount from database
//---------------------------------------

  static Future<int> _txReadBooked(Transaction txn, DocumentReference<Map<String, dynamic>> slotRef,)
  async {
    int booked = 0;
    try {
      final snap = await txn.get(slotRef);
      if (snap.exists) {
        final Map<String, dynamic>? s = snap.data();
         booked = s?['booked'] as int;
      }
    } catch (_) {}
    if (booked < 0) booked = 0;
    return booked;
  }

  //---------------------------------------
// get the seat that is free
//---------------------------------------
  static Future<bool> _txSeatIsFree(Transaction txn, DocumentReference<Map<String, dynamic>> seatRef,)
  async {
    final seatSnap = await txn.get(seatRef);
    if (!seatSnap.exists) return true;

    final Map<String, dynamic>? sd = seatSnap.data();
    if (sd != null && sd.containsKey('taken')) {
      final dynamic t = sd['taken'];
      if (t is bool)
        return t == false;
      return true;
    }
    return true;
  }
//---------------------------------------
// set seat to taken
//---------------------------------------
  static void _txSetSeatTaken(Transaction txn, DocumentReference<Map<String, dynamic>> seatRef, bool taken,) {
    txn.set(
      seatRef,
      {
        'taken': taken,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
//---------------------------------------
// set booked
//---------------------------------------
  static void _txSetBooked(Transaction txn, DocumentReference<Map<String, dynamic>> slotRef, int booked,
      ) {
    int safe = booked;
    if (safe < 0)
      safe = 0;
    txn.set(
      slotRef,
      {'booked': safe},
      SetOptions(merge: true),
    );
  }
//---------------------------------------
// for pending booking
//---------------------------------------
  static Future<String> createBookingPending({
    required Map<String, dynamic> bookingBase,
  }) async {
    //---------------------------------------
// get the time created at
//---------------------------------------

    if (!bookingBase.containsKey('createdAt')) {
      bookingBase['createdAt'] = FieldValue.serverTimestamp();
    }
//---------------------------------------
// get the slotkey
//---------------------------------------
    String slotKey = '';
    if (bookingBase.containsKey('slotKey')) {
      final dynamic sk = bookingBase['slotKey'];
      if (sk is String) slotKey = sk;
    }
    //---------------------------------------
// if no slot key then use start time to turn into slotkey format
//---------------------------------------
    if (slotKey.isEmpty) {
      if (bookingBase.containsKey('start')) {
        final dynamic st = bookingBase['start'];
        if (st is String) slotKey = st;
      }
    }
    slotKey = _normalizeSlotKey(slotKey);
    bookingBase['slotKey'] = slotKey;

    //---------------------------------------
// get the approval
//---------------------------------------
    if (!bookingBase.containsKey('approval')) {
      bookingBase['approval'] = 'pending';
    }
    //---------------------------------------
// set seen to false
//---------------------------------------
    bookingBase['seen'] = false;

    final FirebaseFirestore db = FirebaseFirestore.instance;

    final DocumentReference<Map<String, dynamic>> bookingRef =
    db.collection(_bookingsCol).doc();
//---------------------------------------
// set it into Bookings Database
//---------------------------------------

    await bookingRef.set(bookingBase);
    await bookingRef.set({'reminderSent': {}}, SetOptions(merge: true));

//---------------------------------------
// get the seat index
//---------------------------------------
    try {
      int seatIdx = 0;
      bool hasSeat = false;
      if (bookingBase.containsKey('seatIndex')) {
        final dynamic si = bookingBase['seatIndex'];
        if (si is int && si > 0) {
          hasSeat = true;
          seatIdx = si;
        }
      }

      if (hasSeat) {
        String facilityId = '';
        if (bookingBase.containsKey('facilityId')) {
          final dynamic f = bookingBase['facilityId'];
          facilityId = f is String ? f : (f?.toString() ?? '');
        }
        String dateYMD = '';
        if (bookingBase.containsKey('bookingDate')) {
          final dynamic d = bookingBase['bookingDate'];
          dateYMD = d is String ? d : (d?.toString() ?? '');
        }
//---------------------------------------
// get the available slot
//---------------------------------------
        if (facilityId.isNotEmpty && dateYMD.isNotEmpty) {
          final int capacity = await _readCapacityOutsideTxn(
            facilityId: facilityId,
            dateYMD: dateYMD,
            slotKey: slotKey,
          );
//---------------------------------------
// set new seat index taken = false for pending
//---------------------------------------
          if (seatIdx >= 1 && seatIdx <= capacity) {
            final seatRef = db
                .collection('Facilities')
                .doc(facilityId)
                .collection('Days')
                .doc(dateYMD)
                .collection('Slots')
                .doc(slotKey)
                .collection('Seats')
                .doc(seatIdx.toString());
            await seatRef.set(
              {
                'taken': false,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          }
        }
      }
    } catch (_) {}
//---------------------------------------
// return the booking id to mail can use in the other page
//---------------------------------------
    return bookingRef.id;
  }

//---------------------------------------
// create new booking for admin part
//---------------------------------------

  static Future<String> createBookingPickSeatTx({
    required String facilityId,
    required String dateYMD,
    required String slotKey,
    required int seatIndex,
    required Map<String, dynamic> bookingBase,
  }) async {

    String bookingId = '';
    final String key = _normalizeSlotKey(slotKey);
    final FirebaseFirestore db = FirebaseFirestore.instance;

    if (!bookingBase.containsKey('createdAt')) {
      bookingBase['createdAt'] = FieldValue.serverTimestamp();
    }

//---------------------------------------
// get the info from database
//---------------------------------------

    final facRef  = db.collection('Facilities')
        .doc(facilityId);
    final dayRef  = facRef.collection('Days').doc(dateYMD);
    final slotRef = dayRef.collection('Slots').doc(key);
    final seatRef = slotRef
        .collection('Seats')
        .doc(seatIndex.toString());

//---------------------------------------
// set the taken to true
//---------------------------------------
    await seatRef.set(
      {
        'taken': true,
        'updatedAt': FieldValue.serverTimestamp()
      },
      SetOptions(merge: true),
    );

//---------------------------------------
// set the booked + 1
//---------------------------------------
    await slotRef.set(
      {
        'booked': FieldValue.increment(1),
      },
      SetOptions(merge: true),
    );

//---------------------------------------
// create new booking into bookings database
//---------------------------------------
    final bookingRef = db.collection(_bookingsCol).doc();
    bookingId = bookingRef.id;

    final Map<String, dynamic> data = Map<String, dynamic>.from(bookingBase);
    data['facilityId'] = facilityId;
    data['slotKey']    = key;
    data['seatIndex']  = seatIndex;
    data['approval']   = data['approval'] ?? 'accepted';
    data['status']     = data['status'] ?? 'upcoming';
    data['seen']       = data['seen']   ?? false;
    //---------------------------------------
// set the data into database
//---------------------------------------
    await bookingRef.set(data);

//---------------------------------------
// return the new booking id for email purpose
//---------------------------------------
    return bookingId;
  }

//---------------------------------------
// change to string format
//---------------------------------------

  static String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    return '$y-$m-$da';
  }

// Only accept a string in YYYY-MM-DD. Anything else -> '' (empty).
  static String _toYMD(dynamic v) {
    // if not a String, we reject
    if (v is! String) return '';

    // trim spaces
    final String s = v.trim();

    // if pattern matches YYYY-MM-DD, we accept; else reject
    final bool ok = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s);
    if (ok) return s;

    return ''; // not in correct format
  }


  static String _pickStr(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return '';
    for (final k in keys) {
      if (m.containsKey(k)) {
        final v = m[k];
        if (v == null) continue;
        if (v is String && v.trim().isNotEmpty) return v.trim();
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
    }
    return '';
  }

  static int? _pickInt(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return null;
    for (final k in keys) {
      if (m.containsKey(k)) {
        final v = m[k];
        if (v is int) return v;
        final p = int.tryParse('$v');
        if (p != null) return p;
      }
    }
    return null;
  }

//---------------------- -----------------
// for booking approve
//---------------------------------------

  static Future<void> approveBookingByIdTx({required String bookingId}) async {
    final db = FirebaseFirestore.instance;

    await db.runTransaction((txn) async {
      final bookingRef = db.collection(_bookingsCol).doc(bookingId);

//---------------------------------------
// get the booking from database
//---------------------------------------
      final bSnap = await txn.get(bookingRef);
      if (!bSnap.exists) throw Exception('Booking not found');
      final b = bSnap.data() as Map<String, dynamic>;

      //---------------------------------------
// get the required data
//---------------------------------------
      final facilityId = b['facilityId'];
      final dateYMD   = b['bookingDate'];
      final slotKey   = _normalizeSlotKey(b['slotKey']);
      final seatIndex = _pickInt(b, ['seatIndex']);
//---------------------------------------
// if one of them is empty then show error
//---------------------------------------
      if (facilityId.isEmpty || dateYMD.isEmpty || slotKey.isEmpty || seatIndex == null || seatIndex < 1) {
        throw Exception('Booking missing facility/date/slot/seat.');
      }

      final facRef  = db.collection('Facilities').doc(facilityId);
      final slotRef = facRef.collection('Days').doc(dateYMD).collection('Slots').doc(slotKey);
      final seatRef = slotRef.collection('Seats').doc(seatIndex.toString());

      //---------------------------------------
// get the available slot
//---------------------------------------
      final capacity = await _txReadCapacity(txn, slotRef: slotRef, facRef: facRef);
      if (seatIndex < 1 || seatIndex > capacity) {
        throw Exception('Seat index out of range.');
      }
      //---------------------------------------
// get the booked
//---------------------------------------
      final bookedCount = await _txReadBooked(txn, slotRef);
      if (bookedCount >= capacity) throw Exception('Slot is full.');
      //---------------------------------------
// check if seat is not free then seat ia already taken
//---------------------------------------
      final free = await _txSeatIsFree(txn, seatRef);
      if (!free) throw Exception('Seat already taken.');

//---------------------------------------
// set the seat to true , then add one for booked
//---------------------------------------
      _txSetSeatTaken(txn, seatRef, true);
      _txSetBooked(txn, slotRef, (bookedCount + 1 > capacity ? capacity : bookedCount + 1));
//---------------------------------------
// update the new data
//---------------------------------------
      txn.set(
        bookingRef,
        {
          'approval': 'accepted',
          'status': 'upcoming',
          'slotKey': slotKey,
          'seatIndex': seatIndex,
          'approvedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

  }

//---------------------------------------
// when booking is rejected
//---------------------------------------
  static Future<void> rejectBookingById({required String bookingId}) async {
    final db = FirebaseFirestore.instance;
    //---------------------------------------
// get the booking and set approval to rejected
//---------------------------------------
    await db.collection(_bookingsCol).doc(bookingId).set(
      {
        'approval': 'rejected',
        'status': '-',
        'rejectedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
  //---------------------------------------
// when booking is deleted / cancelled
//---------------------------------------

  static Future<void> deleteAcceptedBookingByIdTx({required String bookingId}) async {
    final db = FirebaseFirestore.instance;

    await db.runTransaction((txn) async {
      final bookingRef = db.collection(_bookingsCol).doc(bookingId);

//---------------------------------------
// get the booking from dtabase
//---------------------------------------
      final bSnap = await txn.get(bookingRef);
      if (!bSnap.exists) throw Exception('Booking not found');
      final b = bSnap.data() as Map<String, dynamic>;
      //---------------------------------------
// get the important info
//---------------------------------------

      final facilityId= b['facilityId'];
      final dateYMD   = b['bookingDate'];
      final slotKey   = _normalizeSlotKey(_pickStr(b, ['slotKey']));
      final seatIndex = _pickInt(b, ['seatIndex']);

      int bookedCount = 0;
      DocumentReference<Map<String, dynamic>>? slotRef;
      DocumentReference<Map<String, dynamic>>? seatRef;
//---------------------------------------
// procceed to cancel booking
//---------------------------------------
        final facRef = db.collection('Facilities').doc(facilityId);
        slotRef = facRef.collection('Days').doc(dateYMD).collection('Slots').doc(slotKey);
        seatRef = slotRef.collection('Seats').doc(seatIndex.toString());
        bookedCount = await _txReadBooked(txn, slotRef);

      //---------------------------------------
// set the booking to deleted
//---------------------------------------
      txn.set(
        bookingRef,
        {
          'deleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
//---------------------------------------
// set the seat to false and - 1 booked
//---------------------------------------
        _txSetSeatTaken(txn, seatRef, false);
        _txSetBooked(txn, slotRef, bookedCount - 1);
    });
  }

//---------------------------------------
// when edit booking is made
//---------------------------------------
  static Future<void> moveAcceptedBookingByIdTx({
    required String bookingId,
    required String newFacilityId,
    required String newDateYMD,
    required String newSlotKey,
    required int newSeatIndex,
    String? newStartStr,
    String? newEndStr,
  }) async {
    final db = FirebaseFirestore.instance;
    final String newKey = _normalizeSlotKey(newSlotKey);

    await db.runTransaction((txn) async {
      final bookingRef = db.collection(_bookingsCol).doc(bookingId);
//---------------------------------------
// get the booking from database
//---------------------------------------
      final bSnap = await txn.get(bookingRef);
      if (!bSnap.exists) throw Exception('Booking not found');
      final b = bSnap.data() as Map<String, dynamic>;

      final approval = b['approval'].toLowerCase();
      final status   = b['status'].toLowerCase();
      if (approval != 'accepted' ) {
        throw Exception('Only accepted bookings can be edited.');
      }
      if (status != 'upcoming') {
        throw Exception('Only upcoming bookings can be edited.');
      }
//---------------------------------------
// get all old facility info
//---------------------------------------
      final oldFacilityId = b['facilityId'];
      final oldDateYMD    = b['bookingDate'];
      final oldSlotKey    = _normalizeSlotKey(b['slotKey']);
      final int oldSeatIndex = _pickInt(b, ['seatIndex']) ?? -1;

//---------------------------------------
// get old and new facilities info
//---------------------------------------
      final oldFacRef   = db.collection('Facilities').doc(oldFacilityId);
      final oldSlotRef  = oldFacRef.collection('Days').doc(oldDateYMD).collection('Slots').doc(oldSlotKey);
      final oldSeatRef  = oldSlotRef.collection('Seats').doc(oldSeatIndex.toString());

      final newFacRef   = db.collection('Facilities').doc(newFacilityId);
      final newSlotRef  = newFacRef.collection('Days').doc(newDateYMD).collection('Slots').doc(newKey);
      final newSeatRef  = newSlotRef.collection('Seats').doc(newSeatIndex.toString());

      final bool sameFacility = (oldFacilityId == newFacilityId);
      final bool sameDate     = (oldDateYMD   == newDateYMD);
      final bool sameSlot     = (oldSlotKey   == newKey);
      final bool isSameSlot   = sameFacility && sameDate && sameSlot;
      //---------------------------------------
// get old booked
//---------------------------------------
      final int oldBooked = await _txReadBooked(txn, oldSlotRef);
      final int newBooked = await _txReadBooked(txn, newSlotRef);
//---------------------------------------
// get the new place capacity
//---------------------------------------
      final int newCapacity = await _txReadCapacity(txn, slotRef: newSlotRef, facRef: newFacRef);
      if (!(newSeatIndex >= 1 && newSeatIndex <= newCapacity)) {
        throw Exception('Seat index out of range');
      }
//---------------------------------------
// make sure slot is free
//---------------------------------------
      final bool newFree = await _txSeatIsFree(txn, newSeatRef);
      if (!newFree) throw Exception('Seat already taken');


      if (newBooked >= newCapacity) throw Exception('Slot is full');

      //---------------------------------------
// check if same slot just different seat, just set old to false and new to true
//---------------------------------------
      if (isSameSlot) {

        if (newSeatIndex != oldSeatIndex) {
          _txSetSeatTaken(txn, oldSeatRef, false);
          _txSetSeatTaken(txn, newSeatRef, true);
        }
        //---------------------------------------
// or esle will need to
//---------------------------------------
      } else {
        _txSetSeatTaken(txn, oldSeatRef, false);   // free old seat
        _txSetSeatTaken(txn, newSeatRef, true);    // take new seat

//---------------------------------------
// decrement old booking by 1
//---------------------------------------
        _txSetBooked(txn, oldSlotRef, oldBooked -1);

        //---------------------------------------
// inreament new booking
//---------------------------------------
        _txSetBooked(txn, newSlotRef, newBooked + 1);
      }
//---------------------------------------
// update tha booking id
//---------------------------------------
      final Map<String, dynamic> patch = {
        'facilityId': newFacilityId,
        'bookingDate': newDateYMD,
        'slotKey': newKey,
        'seatIndex': newSeatIndex,
        'updatedAt': FieldValue.serverTimestamp(),
        'start':newStartStr,
        'end':newEndStr,
      };

      txn.set(bookingRef, patch, SetOptions(merge: true));
    });
  }

}
