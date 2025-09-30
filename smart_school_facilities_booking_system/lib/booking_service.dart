import 'package:flutter/foundation.dart' show kIsWeb;     // to skip on web
import 'package:firebase_auth/firebase_auth.dart';        // (optional) if you want uid checks later

import 'package:cloud_firestore/cloud_firestore.dart';

class BookingService {
  static const String _bookingsCol = 'Bookings';

  // -------- Key helper --------
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

  // -------- Non-transactional helpers (used outside txns only) --------

  // Prefer Slots/{HHmm}.capacity -> Facilities.availableSlots -> 1
  static Future<int> _readCapacityOutsideTxn({
    required String facilityId,
    required String dateYMD,
    required String slotKey,
  }) async {
    final String key = _normalizeSlotKey(slotKey);
    int cap = 1;

    try {
      final slotRef = FirebaseFirestore.instance
          .collection('Facilities').doc(facilityId)
          .collection('Days').doc(dateYMD)
          .collection('Slots').doc(key);

      final slotSnap = await slotRef.get();
      if (slotSnap.exists) {
        final Map<String, dynamic>? s = slotSnap.data();
        if (s != null && s.containsKey('capacity')) {
          final dynamic c = s['capacity'];
          if (c is int) {
            cap = c;
          } else {
            final int? p = int.tryParse('$c');
            if (p != null) cap = p;
          }
        }
      }

      if (cap <= 1) {
        final facSnap = await FirebaseFirestore.instance
            .collection('Facilities').doc(facilityId).get();
        if (facSnap.exists) {
          final Map<String, dynamic>? f = facSnap.data();
          if (f != null && f.containsKey('availableSlots')) {
            final dynamic a = f['availableSlots'];
            if (a is int) {
              cap = a;
            } else {
              final int? p = int.tryParse('$a');
              if (p != null) cap = p;
            }
          }
        }
      }
    } catch (_) {}

    if (cap <= 0) cap = 1;
    return cap;
  }

  // Make a local DateTime "YYYY-MM-DD" + "HHmm"/"HH:MM"
// Returns null if input is invalid.
  static DateTime? _startAtLocalFromYMDAndTime(String dateYMD, {String? slotKey, String? startStr}) {
    try {
      // ---- parse date ----
      final parts = dateYMD.split('-');            // "2025-09-10"
      if (parts.length != 3) return null;
      final int y = int.parse(parts[0]);
      final int m = int.parse(parts[1]);
      final int d = int.parse(parts[2]);

      // ---- decide time string ----
      String time = '';
      if (startStr != null && startStr.trim().isNotEmpty) {
        time = startStr.trim();                    // e.g. "09:30"
      } else if (slotKey != null && slotKey.trim().isNotEmpty) {
        final String k = _normalizeSlotKey(slotKey); // e.g. "0930"
        time = k.substring(0, 2) + ':' + k.substring(2, 4);
      } else {
        return null;
      }

      // ---- parse time ----
      final tp = time.contains(':') ? time.split(':') : [time.substring(0,2), time.substring(2,4)];
      if (tp.length != 2) return null;
      final int hh = int.parse(tp[0]);
      final int mm = int.parse(tp[1]);

      // ---- build local DateTime ----
      return DateTime(y, m, d, hh, mm);
    } catch (_) {
      return null;
    }
  }


  // -------- Transaction helpers (ONLY use txn.get inside a txn) --------

  static Future<int> _txReadCapacity(
      Transaction txn, {
        required DocumentReference<Map<String, dynamic>> slotRef,
        required DocumentReference<Map<String, dynamic>> facRef,
      }) async {
    int cap = 1;
    try {
      final s = await txn.get(slotRef);
      if (s.exists) {
        final Map<String, dynamic>? d = s.data();
        if (d != null && d.containsKey('capacity')) {
          final dynamic c = d['capacity'];
          if (c is int) {
            cap = c;
          } else {
            final int? p = int.tryParse('$c');
            if (p != null) cap = p;
          }
        }
      }
      if (cap <= 1) {
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
      }
    } catch (_) {}
    if (cap <= 0) cap = 1;
    return cap;
  }

  static Future<int> _txReadBooked(
      Transaction txn,
      DocumentReference<Map<String, dynamic>> slotRef,
      ) async {
    int booked = 0;
    try {
      final snap = await txn.get(slotRef);
      if (snap.exists) {
        final Map<String, dynamic>? s = snap.data();
        if (s != null && s.containsKey('booked')) {
          final dynamic b = s['booked'];
          if (b is int) {
            booked = b;
          } else {
            final int? p = int.tryParse('$b');
            if (p != null) booked = p;
          }
        }
      }
    } catch (_) {}
    if (booked < 0) booked = 0;
    return booked;
  }

  static Future<bool> _txSeatIsFree(
      Transaction txn,
      DocumentReference<Map<String, dynamic>> seatRef,
      ) async {
    final seatSnap = await txn.get(seatRef);
    if (!seatSnap.exists) return true;

    final Map<String, dynamic>? sd = seatSnap.data();
    if (sd != null && sd.containsKey('taken')) {
      final dynamic t = sd['taken'];
      if (t is bool) return t == false;
      return true;
    }
    return true;
  }

  static void _txSetSeatTaken(
      Transaction txn,
      DocumentReference<Map<String, dynamic>> seatRef,
      bool taken,
      ) {
    txn.set(
      seatRef,
      {
        'taken': taken,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static void _txSetBooked(
      Transaction txn,
      DocumentReference<Map<String, dynamic>> slotRef,
      int booked,
      ) {
    int safe = booked;
    if (safe < 0) safe = 0;
    txn.set(
      slotRef,
      {'booked': safe},
      SetOptions(merge: true),
    );
  }

  // -------- Public APIs (ORIGINAL ONES — kept) --------

  // PENDING booking (no counter change)
  static Future<String> createBookingPending({
    required Map<String, dynamic> bookingBase,
  }) async {
    // keep your existing field normalisation
    if (!bookingBase.containsKey('createdAt')) {
      bookingBase['createdAt'] = FieldValue.serverTimestamp();
    }

    String slotKey = '';
    if (bookingBase.containsKey('slotKey')) {
      final dynamic sk = bookingBase['slotKey'];
      if (sk is String) slotKey = sk;
    }
    if (slotKey.isEmpty) {
      if (bookingBase.containsKey('start')) {
        final dynamic st = bookingBase['start'];
        if (st is String) slotKey = st;
      }
    }
    slotKey = _normalizeSlotKey(slotKey);
    bookingBase['slotKey'] = slotKey;

    if (!bookingBase.containsKey('approval')) {
      bookingBase['approval'] = 'pending';
    }

    // (unchanged) – mark unseen on create
    bookingBase['seen'] = false;

    final FirebaseFirestore db = FirebaseFirestore.instance;

    // IMPORTANT: allocate the doc BEFORE writing so we can return the id
    final DocumentReference<Map<String, dynamic>> bookingRef =
    db.collection(_bookingsCol).doc();

    await bookingRef.set(bookingBase);


    await bookingRef.set({'reminderSent': {}}, SetOptions(merge: true));

    // (unchanged) optional soft seat doc
    try {
      int seatIdx = 0;
      bool hasSeat = false;
      if (bookingBase.containsKey('seatIndex')) {
        final dynamic si = bookingBase['seatIndex'];
        if (si is int && si > 0) {
          hasSeat = true;
          seatIdx = si;
        } else {
          final int? p = int.tryParse('$si');
          if (p != null && p > 0) {
            hasSeat = true;
            seatIdx = p;
          }
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

        if (facilityId.isNotEmpty && dateYMD.isNotEmpty) {
          final int capacity = await _readCapacityOutsideTxn(
            facilityId: facilityId,
            dateYMD: dateYMD,
            slotKey: slotKey,
          );
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

    // NEW: return the real id so callers can use it in Inbox mails
    return bookingRef.id;
  }

  // ACCEPT immediately (auto-assign)
  static Future<String> createBookingAutoAssignTx({
    required String facilityId,
    required String dateYMD,
    required String slotKey,
    required Map<String, dynamic> bookingBase,
  }) async {
    final db  = FirebaseFirestore.instance;
    final key = _normalizeSlotKey(slotKey);

    // make sure base has normalized slotKey + createdAt
    bookingBase['slotKey'] = key;
    if (!bookingBase.containsKey('createdAt')) {
      bookingBase['createdAt'] = FieldValue.serverTimestamp();
    }

    // PRE-ALLOCATE so we can return the real id
    final bookingRef = db.collection(_bookingsCol).doc();
    String createdId = bookingRef.id;

    await db.runTransaction((txn) async {
      final facRef = db.collection('Facilities').doc(facilityId);
      final slotRef = facRef
          .collection('Days').doc(dateYMD)
          .collection('Slots').doc(key);

      // ---- READS ----
      final capacity = await _txReadCapacity(txn, slotRef: slotRef, facRef: facRef);
      final booked   = await _txReadBooked(txn, slotRef);
      if (booked >= capacity) throw Exception('Slot is full');

      // pick first free seat
      int? chosen;
      for (int i = 1; i <= capacity; i++) {
        final seatRef = slotRef.collection('Seats').doc(i.toString());
        if (await _txSeatIsFree(txn, seatRef)) { chosen = i; break; }
      }
      if (chosen == null) throw Exception('No free seat found');

      // ---- WRITES ----
      final chosenSeatRef = slotRef.collection('Seats').doc(chosen.toString());
      _txSetSeatTaken(txn, chosenSeatRef, true);

      int nextBooked = booked + 1;
      if (nextBooked > capacity) nextBooked = capacity;
      _txSetBooked(txn, slotRef, nextBooked);

      final data = Map<String, dynamic>.from(bookingBase)
        ..['seatIndex'] = chosen
        ..['approval']  = 'accepted'
        ..['status']    = 'upcoming'
        ..['seen']      = false;

      txn.set(bookingRef, data);

    });



    await FirebaseFirestore.instance
        .collection(_bookingsCol)
        .doc(createdId)
        .set({'reminderSent': {}}, SetOptions(merge: true));
    return createdId;
  }

  // ACCEPT immediately (manual seatIndex)
  static Future<String> createBookingPickSeatTx({
    required String facilityId,                 // facility to book
    required String dateYMD,                    // date "YYYY-MM-DD"
    required String slotKey,                    // slot key like "0930"
    required int seatIndex,                     // 1-based seat index chosen by user
    required Map<String, dynamic> bookingBase,  // base fields for the booking doc
  }) async {
    // we store the new booking id here and return it after transaction
    String createdBookingId = '';

    // normalize the slot key once (e.g., "9:30" -> "0930")
    final String key = _normalizeSlotKey(slotKey);

    // get the Firestore instance (we will run a transaction)
    final FirebaseFirestore db = FirebaseFirestore.instance;

    // make sure the base map has the slotKey and createdAt
    bookingBase['slotKey'] = key;                                // store normalized key
    if (!bookingBase.containsKey('createdAt')) {                 // add createdAt if missing
      bookingBase['createdAt'] = FieldValue.serverTimestamp();
    }

    // run everything atomically inside a transaction
    await db.runTransaction((txn) async {
      // references for facility, day and slot documents (where seats live)
      final facRef = db.collection('Facilities').doc(facilityId);
      final slotRef = facRef
          .collection('Days')
          .doc(dateYMD)
          .collection('Slots')
          .doc(key);

      // -------------------------
      // READS (checks before write)
      // -------------------------

      // read capacity from slot (or facility fallback) using your helper
      final int capacity = await _txReadCapacity(
        txn,
        slotRef: slotRef,
        facRef: facRef,
      );

      // seat index must be between 1 and capacity
      final int seatIdx = seatIndex;
      if (!(seatIdx >= 1 && seatIdx <= capacity)) {
        throw Exception('Seat index out of range');
      }

      // read current "booked" counter on this slot
      final int booked = await _txReadBooked(txn, slotRef);

      // stop if slot is already full
      if (booked >= capacity) {
        throw Exception('Slot is full');
      }

      // read the chosen seat doc to see if free
      final seatRef = slotRef.collection('Seats').doc(seatIdx.toString());
      final bool free = await _txSeatIsFree(txn, seatRef);
      if (!free) {
        throw Exception('Seat is already taken');
      }

      // -------------------------
      // WRITES (apply the changes)
      // -------------------------

      // mark the chosen seat as taken
      _txSetSeatTaken(txn, seatRef, true);

      // increase the booked counter (clamp to capacity)
      int nextBooked = booked + 1;
      if (nextBooked > capacity) {
        nextBooked = capacity;
      }
      _txSetBooked(txn, slotRef, nextBooked);

      // create the booking doc with a pre-generated id so we can return it
      final bookingRef = db.collection(_bookingsCol).doc();
      createdBookingId = bookingRef.id; // <-- SAVE the id to return later

      // clone the base map and fill required booking fields
      final Map<String, dynamic> data = Map<String, dynamic>.from(bookingBase);
      data['seatIndex'] = seatIdx;        // store the chosen 1-based seat index
      data['approval'] = 'accepted';      // accept immediately in this flow
      data['status'] = 'upcoming';        // upcoming by default
      data['seen'] = false;               // unseen on create (for your UI)

      // write the booking inside the transaction
      txn.set(bookingRef, data);
    });




    // after the transaction completes OK, return the new id
    return createdBookingId;
  }

  // APPROVE pending -> accepted
  static Future<void> approvePendingBookingTx({
    required String bookingId,
    required String facilityId,
    required String dateYMD,
    required String slotKey,
    int? desiredSeatIndex,
  }) async {
    final String key = _normalizeSlotKey(slotKey);
    final FirebaseFirestore db = FirebaseFirestore.instance;

    await db.runTransaction((txn) async {
      final bookingRef = db.collection(_bookingsCol).doc(bookingId);
      final facRef = db.collection('Facilities').doc(facilityId);
      final slotRef = facRef
          .collection('Days').doc(dateYMD)
          .collection('Slots').doc(key);

      // ---- READS ----
      final bSnap = await txn.get(bookingRef);
      if (!bSnap.exists) throw Exception('Booking not found');
      final Map<String, dynamic>? b = bSnap.data() as Map<String, dynamic>?;
      String approval = 'pending';
      if (b != null && b.containsKey('approval')) {
        final dynamic a = b['approval'];
        if (a is String) approval = a;
      }
      if (approval != 'pending') throw Exception('Booking already processed');

      int? seatIdx = desiredSeatIndex;
      if (seatIdx == null && b != null && b.containsKey('seatIndex')) {
        final dynamic r = b['seatIndex'];
        if (r is int) {
          seatIdx = r;
        } else {
          final int? p = int.tryParse('$r');
          if (p != null) seatIdx = p;
        }
      }
      if (seatIdx == null) throw Exception('No seatIndex on this pending booking');

      final int capacity = await _txReadCapacity(
        txn,
        slotRef: slotRef,
        facRef: facRef,
      );
      if (!(seatIdx >= 1 && seatIdx <= capacity)) {
        throw Exception('Seat index out of range');
      }

      final int booked = await _txReadBooked(txn, slotRef);
      if (booked >= capacity) throw Exception('Slot is full');

      final seatRef = slotRef.collection('Seats').doc(seatIdx.toString());
      final bool free = await _txSeatIsFree(txn, seatRef);
      if (!free) throw Exception('Seat already taken');

      // ---- WRITES ----
      _txSetSeatTaken(txn, seatRef, true);
      int nextBooked = booked + 1;
      if (nextBooked > capacity) nextBooked = capacity;
      _txSetBooked(txn, slotRef, nextBooked);

      txn.set(
        bookingRef,
        {
          'approval': 'accepted',
          'status': 'upcoming',
          'seatIndex': seatIdx,
          'approvedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });




  }

  // CANCEL accepted -> booked -= 1
  static Future<void> cancelAcceptedBookingTx({
    required String bookingId,
    required String facilityId,
    required String dateYMD,
    required String slotKey,
    required int seatIndex,
    bool hardDelete = false,
  }) async {
    final String key = _normalizeSlotKey(slotKey);
    final FirebaseFirestore db = FirebaseFirestore.instance;

    await db.runTransaction((txn) async {
      final bookingRef = db.collection(_bookingsCol).doc(bookingId);
      final facRef = db.collection('Facilities').doc(facilityId);
      final slotRef = facRef
          .collection('Days').doc(dateYMD)
          .collection('Slots').doc(key);
      final seatRef = slotRef.collection('Seats').doc(seatIndex.toString());

      // ---- READS ----
      final bSnap = await txn.get(bookingRef);
      if (!bSnap.exists) throw Exception('Booking not found');

      final int booked = await _txReadBooked(txn, slotRef);

      // ---- WRITES ----
      _txSetSeatTaken(txn, seatRef, false);

      int after = booked - 1;
      if (after < 0) after = 0;
      _txSetBooked(txn, slotRef, after);

      if (hardDelete) {
        txn.delete(bookingRef);
      } else {
        txn.set(
          bookingRef,
          {
            'status': 'cancelled',
            'cancelledAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });

  }

  // CANCEL pending (no counter change)
  static Future<void> cancelPendingBooking({
    required String bookingId,
    bool hardDelete = false,
  }) async {
    final FirebaseFirestore db = FirebaseFirestore.instance;
    final bookingRef = db.collection(_bookingsCol).doc(bookingId);

    if (hardDelete) {
      await bookingRef.delete();
    } else {
      await bookingRef.set(
        {
          'status': 'cancelled',
          'approval': 'cancelled',
          'cancelledAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }


  }

  // -------- Extra helpers for id-only actions --------

  static String _ymd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final da = d.day.toString().padLeft(2, '0');
    return '$y-$m-$da';
  }

  static String _toYMD(dynamic v) {
    if (v == null) return '';
    if (v is Timestamp) return _ymd(v.toDate());
    if (v is DateTime) return _ymd(v);
    if (v is String) {
      final s = v.trim();
      if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return s;
      try {
        // try DD/MM/YYYY
        final p = s.split('/');
        if (p.length == 3) {
          return _ymd(DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])));
        }
      } catch (_) {}
    }
    return '';
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

  // -------- New id-only Public APIs --------

  /// APPROVE (by id): set approval='accepted', status='upcoming',
  /// booked += 1 (clamped), and seats/{seatIndex}.taken = true.
  /// Uses fields inside the booking doc: facilityId, bookingDate, slotKey, seatIndex.
  static Future<void> approveBookingByIdTx({required String bookingId}) async {
    final db = FirebaseFirestore.instance;
    DateTime? _approvedStart;    // capture start to schedule after txn
    await db.runTransaction((txn) async {
      final bookingRef = db.collection(_bookingsCol).doc(bookingId);


      // Read booking
      final bSnap = await txn.get(bookingRef);
      if (!bSnap.exists) throw Exception('Booking not found');
      final b = bSnap.data() as Map<String, dynamic>?;

      final approval = _pickStr(b, ['approval']).toLowerCase();
      if (approval == 'accepted' || approval == 'approved') {
        // already accepted; nothing to do
        return;
      }
      if (approval == 'rejected') {
        throw Exception('This booking was rejected.');
      }

      final facilityId = _pickStr(b, ['facilityId', 'facilityID', 'facilityDocId', 'facility_id']);
      final dateYMD   = _toYMD(b?['bookingDate'] ?? _pickStr(b, ['dateYMD', 'date', 'day']));
      final slotKey   = _normalizeSlotKey(_pickStr(b, ['slotKey', 'slot', 'start']));
      final seatIndex = _pickInt(b, ['seatIndex', 'seat', 'seatNumber']);

      if (facilityId.isEmpty || dateYMD.isEmpty || slotKey.isEmpty || seatIndex == null || seatIndex < 1) {
        throw Exception('Booking missing facility/date/slot/seat.');
      }

      final facRef  = db.collection('Facilities').doc(facilityId);
      final slotRef = facRef.collection('Days').doc(dateYMD).collection('Slots').doc(slotKey);
      final seatRef = slotRef.collection('Seats').doc(seatIndex.toString());

      // Reads (capacity & booked & seat free)
      final capacity = await _txReadCapacity(txn, slotRef: slotRef, facRef: facRef);
      if (seatIndex < 1 || seatIndex > capacity) {
        throw Exception('Seat index out of range.');
      }
      final bookedCount = await _txReadBooked(txn, slotRef);
      if (bookedCount >= capacity) throw Exception('Slot is full.');
      final free = await _txSeatIsFree(txn, seatRef);
      if (!free) throw Exception('Seat already taken.');

      // Writes
      _txSetSeatTaken(txn, seatRef, true);
      _txSetBooked(txn, slotRef, (bookedCount + 1 > capacity ? capacity : bookedCount + 1));
      _approvedStart = _startAtLocalFromYMDAndTime(dateYMD, slotKey: slotKey);

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

  /// REJECT (by id): approval='rejected', status='-'. No counters.
  static Future<void> rejectBookingByIdSimple({required String bookingId}) async {
    final db = FirebaseFirestore.instance;
    await db.collection(_bookingsCol).doc(bookingId).set(
      {
        'approval': 'rejected',
        'status': '-',
        'rejectedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );


  }

  /// DELETE accepted & UPCOMING booking (by id):
  /// Decrement booked by 1, set Seats/{seatIndex}.taken=false, and delete Bookings/{bookingId}.
// SOFT-DELETE by id.
// - Always sets Bookings/{id}.deleted=true (+deletedAt)
// - If approval in [accepted/approved] AND status == upcoming -> free seat + booked -= 1
  // SOFT-DELETE by id.
// - Always sets Bookings/{id}.deleted=true (+deletedAt)
// - If approval in [accepted/approved] AND status == upcoming -> free seat + booked -= 1
// Soft-delete by id.
// - Always sets deleted=true (+ deletedAt).
// - If the booking actually holds a seat (accepted/approved + upcoming),
//   also frees the seat and decrements booked by 1 (clamped >= 0).
  static Future<void> deleteAcceptedBookingByIdTx({required String bookingId}) async {
    final db = FirebaseFirestore.instance;

    await db.runTransaction((txn) async {
      final bookingRef = db.collection(_bookingsCol).doc(bookingId);

      // ---- READS (all reads before any writes) ----
      final bSnap = await txn.get(bookingRef);
      if (!bSnap.exists) throw Exception('Booking not found');
      final b = bSnap.data() as Map<String, dynamic>?;

      final approval  = _pickStr(b, ['approval']).toLowerCase();
      final status    = _pickStr(b, ['status']).toLowerCase();
      final facilityId= _pickStr(b, ['facilityId','facilityID','facilityDocId','facility_id']);
      final dateYMD   = _toYMD(b?['bookingDate'] ?? _pickStr(b, ['dateYMD','date','day']));
      final slotKey   = _normalizeSlotKey(_pickStr(b, ['slotKey','slot','start']));
      final seatIndex = _pickInt(b, ['seatIndex','seat','seatNumber']);

      final bool shouldRelease =
          (approval == 'accepted' || approval == 'approved') &&
              status == 'upcoming' &&
              facilityId.isNotEmpty &&
              dateYMD.isNotEmpty &&
              slotKey.isNotEmpty &&
              seatIndex != null &&
              seatIndex! > 0;

      // Pre-read slot.booked if we will touch it (still no writes yet)
      int bookedCount = 0;
      DocumentReference<Map<String, dynamic>>? slotRef;
      DocumentReference<Map<String, dynamic>>? seatRef;

      if (shouldRelease) {
        final facRef = db.collection('Facilities').doc(facilityId);
        slotRef = facRef.collection('Days').doc(dateYMD).collection('Slots').doc(slotKey);
        seatRef = slotRef.collection('Seats').doc(seatIndex!.toString());
        bookedCount = await _txReadBooked(txn, slotRef);
        // (We don't need to read the seat doc; setting taken=false with merge is safe.)
      }

      // ---- WRITES (after all reads) ----
      // Always soft-delete the booking
      txn.set(
        bookingRef,
        {
          'deleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (shouldRelease) {
        // Free the seat and decrement booked (clamped in _txSetBooked)
        _txSetSeatTaken(txn, seatRef!, false);
        _txSetBooked(txn, slotRef!, bookedCount - 1);
      }
    });


  }




  // -------- Move/Reschedule accepted booking (by id) --------
  /// Move an ACCEPTED + UPCOMING booking to a new (facilityId/date/slot/seat).
  /// - If slot/date/facility are the same and only seat changes, booked counter stays the same.
  /// - Otherwise: old.booked -= 1, new.booked += 1.
  /// - Flips Seats/{seat}.taken accordingly.
  /// - All reads happen before any writes inside the transaction.
  // -------- Move/Reschedule accepted booking (by id) --------
  /// Move an ACCEPTED + UPCOMING booking to a new (facilityId/date/slot/seat).
  /// Also updates Bookings/{bookingId}.start and .end (if provided).
  static Future<void> moveAcceptedBookingByIdTx({
    required String bookingId,
    required String newFacilityId,
    required String newDateYMD,
    required String newSlotKey,
    required int newSeatIndex,       // 1-based
    String? newStartStr,             // optional "HH:MM" from UI
    String? newEndStr,               // optional "HH:MM" from UI
  }) async {
    final db = FirebaseFirestore.instance;
    final String newKey = _normalizeSlotKey(newSlotKey);

    await db.runTransaction((txn) async {
      final bookingRef = db.collection(_bookingsCol).doc(bookingId);

      // ---- READ booking first ----
      final bSnap = await txn.get(bookingRef);
      if (!bSnap.exists) throw Exception('Booking not found');
      final b = bSnap.data() as Map<String, dynamic>?;

      final approval = _pickStr(b, ['approval']).toLowerCase();
      final status   = _pickStr(b, ['status']).toLowerCase();
      if (approval != 'accepted' && approval != 'approved') {
        throw Exception('Only accepted bookings can be edited.');
      }
      if (status != 'upcoming') {
        throw Exception('Only upcoming bookings can be edited.');
      }

      final oldFacilityId = _pickStr(b, ['facilityId','facilityID','facilityDocId','facility_id']);
      final oldDateYMD    = _toYMD(b?['bookingDate'] ?? _pickStr(b, ['dateYMD','date','day']));
      final oldSlotKey    = _normalizeSlotKey(_pickStr(b, ['slotKey','slot','start']));
      final int oldSeatIndex = _pickInt(b, ['seatIndex','seat','seatNumber']) ?? -1;

      if (oldFacilityId.isEmpty || oldDateYMD.isEmpty || oldSlotKey.isEmpty || oldSeatIndex < 1) {
        throw Exception('Booking missing old facility/date/slot/seat.');
      }
      if (newSeatIndex < 1) {
        throw Exception('Seat index out of range.');
      }

      // If nothing actually changes, just update start/end if provided and return
      final sameFacility = (oldFacilityId == newFacilityId);
      final sameDate     = (oldDateYMD == newDateYMD);
      final sameSlot     = (oldSlotKey == newKey);
      final sameSeat     = (oldSeatIndex == newSeatIndex);

      if (sameFacility && sameDate && sameSlot && sameSeat) {
        final Map<String, dynamic> patch = {
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (newStartStr != null && newStartStr.trim().isNotEmpty) {
          patch['start'] = newStartStr.trim();
        } else {
          // ensure at least start matches slot key
          patch['start'] = _hhmmFromKey(newKey); // "HH:MM"
        }
        if (newEndStr != null && newEndStr.trim().isNotEmpty) {
          patch['end'] = newEndStr.trim();
        }
        txn.set(bookingRef, patch, SetOptions(merge: true));
        return;
      }

      // Build refs
      final oldFacRef   = db.collection('Facilities').doc(oldFacilityId);
      final oldSlotRef  = oldFacRef.collection('Days').doc(oldDateYMD).collection('Slots').doc(oldSlotKey);
      final oldSeatRef  = oldSlotRef.collection('Seats').doc(oldSeatIndex.toString());

      final newFacRef   = db.collection('Facilities').doc(newFacilityId);
      final newSlotRef  = newFacRef.collection('Days').doc(newDateYMD).collection('Slots').doc(newKey);
      final newSeatRef  = newSlotRef.collection('Seats').doc(newSeatIndex.toString());

      // ---- READS (all before writes) ----
      final int oldBooked = await _txReadBooked(txn, oldSlotRef);

      final int newCapacity = await _txReadCapacity(txn, slotRef: newSlotRef, facRef: newFacRef);
      if (!(newSeatIndex >= 1 && newSeatIndex <= newCapacity)) {
        throw Exception('Seat index out of range');
      }
      final int newBooked = await _txReadBooked(txn, newSlotRef);
      final bool newFree = await _txSeatIsFree(txn, newSeatRef);
      if (!newFree) throw Exception('Seat already taken');

      final bool movingWithinSameSlot = (sameFacility && sameDate && sameSlot);
      if (!movingWithinSameSlot) {
        if (newBooked >= newCapacity) throw Exception('Slot is full');
      }

      // ---- WRITES ----
      // 1) Free old seat
      _txSetSeatTaken(txn, oldSeatRef, false);

      // 2) If slot is different, decrement old booked
      if (!movingWithinSameSlot) {
        _txSetBooked(txn, oldSlotRef, oldBooked - 1);
      }

      // 3) Take new seat
      _txSetSeatTaken(txn, newSeatRef, true);

      // 4) If slot is different, increment new booked
      if (!movingWithinSameSlot) {
        int next = newBooked + 1;
        if (next > newCapacity) next = newCapacity;
        _txSetBooked(txn, newSlotRef, next);
      }

      // 5) Update booking doc (also start/end)
      final Map<String, dynamic> patch = {
        'facilityId': newFacilityId,
        'bookingDate': newDateYMD,
        'slotKey': newKey,
        'seatIndex': newSeatIndex,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Start: prefer provided; else derive from key
      if (newStartStr != null && newStartStr.trim().isNotEmpty) {
        patch['start'] = newStartStr.trim();
      } else {
        patch['start'] = _hhmmFromKey(newKey); // "HH:MM"
      }

      // End: only set if provided (we cannot reliably infer end)
      if (newEndStr != null && newEndStr.trim().isNotEmpty) {
        patch['end'] = newEndStr.trim();
      }

      txn.set(bookingRef, patch, SetOptions(merge: true));
    });

  }

// Convert "HHmm" -> "HH:MM"
  static String _hhmmFromKey(String key) {
    String k = key;
    if (k.contains(':')) k = k.replaceAll(':', '');
    if (k.length < 4) k = k.padLeft(4, '0');
    final String hh = k.substring(0, 2);
    final String mm = k.substring(2, 4);
    return hh + ':' + mm;
  }

}
