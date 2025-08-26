// booking_service.dart
//
// Firestore helpers for booking + seat management.
// -------------------------------------------------
// Your original APIs (kept intact):
// - createBookingPending
// - createBookingAutoAssignTx
// - createBookingPickSeatTx
// - approvePendingBookingTx
// - cancelAcceptedBookingTx
// - cancelPendingBooking
//
// New id-only APIs (added at the bottom):
// - approveBookingByIdTx           // approval -> accepted, status -> upcoming, booked += 1, seat taken = true
// - rejectBookingByIdSimple        // approval -> rejected, status -> "-" (no counters)
// - deleteAcceptedBookingByIdTx    // only when status == upcoming; booked -= 1, seat taken = false, delete booking
//
// Notes:
// - Transactions read everything before any write (avoid ABORTED).
// - Slot keys are 4-digit "HHmm".
// - bookingDate accepted as Timestamp/DateTime/"YYYY-MM-DD"/"DD/MM/YYYY".

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
  static Future<void> createBookingPending({
    required Map<String, dynamic> bookingBase,
  }) async {
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

    final FirebaseFirestore db = FirebaseFirestore.instance;
    final bookingRef = db.collection(_bookingsCol).doc();
    await bookingRef.set(bookingBase);

    // Optional soft seat doc (range-checked). Do this OUTSIDE a transaction.
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
          if (f is String) facilityId = f; else if (f != null) facilityId = f.toString();
        }
        String dateYMD = '';
        if (bookingBase.containsKey('bookingDate')) {
          final dynamic d = bookingBase['bookingDate'];
          if (d is String) dateYMD = d; else if (d != null) dateYMD = d.toString();
        }

        if (facilityId.isNotEmpty && dateYMD.isNotEmpty) {
          final int capacity = await _readCapacityOutsideTxn(
            facilityId: facilityId,
            dateYMD: dateYMD,
            slotKey: slotKey,
          );
          if (seatIdx >= 1 && seatIdx <= capacity) {
            final seatRef = db
                .collection('Facilities').doc(facilityId)
                .collection('Days').doc(dateYMD)
                .collection('Slots').doc(slotKey)
                .collection('Seats').doc(seatIdx.toString());
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
  }

  // ACCEPT immediately (auto-assign)
  static Future<void> createBookingAutoAssignTx({
    required String facilityId,
    required String dateYMD,
    required String slotKey,
    required Map<String, dynamic> bookingBase,
  }) async {
    final String key = _normalizeSlotKey(slotKey);
    final FirebaseFirestore db = FirebaseFirestore.instance;

    bookingBase['slotKey'] = key;
    if (!bookingBase.containsKey('createdAt')) {
      bookingBase['createdAt'] = FieldValue.serverTimestamp();
    }

    await db.runTransaction((txn) async {
      final facRef = db.collection('Facilities').doc(facilityId);
      final slotRef = facRef
          .collection('Days').doc(dateYMD)
          .collection('Slots').doc(key);

      // ---- READS (all before writes) ----
      final int capacity = await _txReadCapacity(
        txn,
        slotRef: slotRef,
        facRef: facRef,
      );
      final int booked = await _txReadBooked(txn, slotRef);
      if (booked >= capacity) {
        throw Exception('Slot is full');
      }

      // Find first free seat
      int? chosen;
      int i = 1;
      while (i <= capacity) {
        final seatRef = slotRef.collection('Seats').doc(i.toString());
        final bool free = await _txSeatIsFree(txn, seatRef);
        if (free) {
          chosen = i;
          break;
        }
        i = i + 1;
      }
      if (chosen == null) {
        throw Exception('No free seat found');
      }

      // ---- WRITES ----
      final chosenSeatRef = slotRef.collection('Seats').doc(chosen.toString());
      _txSetSeatTaken(txn, chosenSeatRef, true);

      // bump booked by 1 (clamp)
      int nextBooked = booked + 1;
      if (nextBooked > capacity) nextBooked = capacity;
      _txSetBooked(txn, slotRef, nextBooked);

      // write booking
      final bookingRef = db.collection(_bookingsCol).doc();
      final Map<String, dynamic> data = Map<String, dynamic>.from(bookingBase);
      data['seatIndex'] = chosen;
      data['approval'] = 'accepted';
      data['status'] = 'upcoming';
      txn.set(bookingRef, data);
    });
  }

  // ACCEPT immediately (manual seatIndex)
  static Future<void> createBookingPickSeatTx({
    required String facilityId,
    required String dateYMD,
    required String slotKey,
    required int seatIndex,
    required Map<String, dynamic> bookingBase,
  }) async {
    final String key = _normalizeSlotKey(slotKey);
    final FirebaseFirestore db = FirebaseFirestore.instance;

    bookingBase['slotKey'] = key;
    if (!bookingBase.containsKey('createdAt')) {
      bookingBase['createdAt'] = FieldValue.serverTimestamp();
    }

    await db.runTransaction((txn) async {
      final facRef = db.collection('Facilities').doc(facilityId);
      final slotRef = facRef
          .collection('Days').doc(dateYMD)
          .collection('Slots').doc(key);
      final seatRef = slotRef.collection('Seats').doc(seatIndex.toString());

      // ---- READS ----
      final int capacity = await _txReadCapacity(
        txn,
        slotRef: slotRef,
        facRef: facRef,
      );

      bool inRange = false;
      if (seatIndex >= 1 && seatIndex <= capacity) inRange = true;
      if (!inRange) {
        throw Exception('Seat index out of range');
      }

      final int booked = await _txReadBooked(txn, slotRef);
      if (booked >= capacity) {
        throw Exception('Slot is full');
      }

      final bool free = await _txSeatIsFree(txn, seatRef);
      if (!free) {
        throw Exception('Seat already taken');
      }

      // ---- WRITES ----
      _txSetSeatTaken(txn, seatRef, true);

      int nextBooked = booked + 1;
      if (nextBooked > capacity) nextBooked = capacity;
      _txSetBooked(txn, slotRef, nextBooked);

      final bookingRef = db.collection(_bookingsCol).doc();
      final Map<String, dynamic> data = Map<String, dynamic>.from(bookingBase);
      data['seatIndex'] = seatIndex;
      data['approval'] = 'accepted';
      data['status'] = 'upcoming';
      txn.set(bookingRef, data);
    });
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
  static Future<void> deleteAcceptedBookingByIdTx({required String bookingId}) async {
    final db = FirebaseFirestore.instance;
    await db.runTransaction((txn) async {
      final bookingRef = db.collection(_bookingsCol).doc(bookingId);

      // Read booking
      final bSnap = await txn.get(bookingRef);
      if (!bSnap.exists) throw Exception('Booking not found');
      final b = bSnap.data() as Map<String, dynamic>?;

      final approval = _pickStr(b, ['approval']).toLowerCase();
      final status   = _pickStr(b, ['status']).toLowerCase();
      if (approval != 'accepted' && approval != 'approved') {
        throw Exception('Only accepted bookings can be deleted.');
      }
      if (status != 'upcoming') {
        throw Exception('Only upcoming bookings can be deleted.');
      }

      final facilityId = _pickStr(b, ['facilityId', 'facilityID', 'facilityDocId', 'facility_id']);
      final dateYMD   = _toYMD(b?['bookingDate'] ?? _pickStr(b, ['dateYMD', 'date', 'day']));
      final slotKey   = _normalizeSlotKey(_pickStr(b, ['slotKey', 'slot', 'start']));
      final seatIndex = _pickInt(b, ['seatIndex', 'seat', 'seatNumber']) ?? -1;

      if (facilityId.isEmpty || dateYMD.isEmpty || slotKey.isEmpty || seatIndex < 1) {
        throw Exception('Booking missing facility/date/slot/seat.');
      }

      final facRef  = db.collection('Facilities').doc(facilityId);
      final slotRef = facRef.collection('Days').doc(dateYMD).collection('Slots').doc(slotKey);
      final seatRef = slotRef.collection('Seats').doc(seatIndex.toString());

      final bookedCount = await _txReadBooked(txn, slotRef);

      // Writes
      _txSetSeatTaken(txn, seatRef, false);
      _txSetBooked(txn, slotRef, bookedCount - 1);
      txn.delete(bookingRef);
    });
  }
}
