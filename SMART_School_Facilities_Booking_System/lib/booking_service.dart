// lib/booking_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class BookingService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Auto-assign a seat for one facility/time.
  ///
  /// - `facilityId` - Facilities/{id}
  /// - `dateYMD`    - "YYYY-MM-DD"
  /// - `slotKey`    - "HHMM" (e.g. "0900")
  /// - `bookingBase` - base booking fields you already prepared in UI
  ///    (userId, userName, facilityId, facilityName, managerId, managerName,
  ///     bookingDate, start, optional end, status, createdAt, etc.)
  ///
  /// This method will:
  ///   1) Find capacity from Facilities.availableSlots (min 1)
  ///   2) Create/Update Facilities/{id}/Days/{date}/Slots/{slotKey}:
  ///        - reserved += 1
  ///        - Seats/{NNN} first free seat is created {taken:true}
  ///   3) Write a new Bookings doc with:
  ///        - All `bookingBase` fields
  ///        - slotKey (normalized)
  ///        - start (derived if missing)
  ///        - end   (derived from facility.bookingDurationHours if missing)
  ///        - seat  (int)
  ///        - approval = pending if facility requires approval, else accepted
  static Future<void> createBookingAutoAssignTx({
    required String facilityId,
    required String dateYMD,
    required String slotKey,
    required Map<String, dynamic> bookingBase,
  }) async {
    String _startFromKey(String k) =>
        '${k.padLeft(4, '0').substring(0, 2)}:${k.padLeft(4, '0').substring(2, 4)}';

    int _toInt(dynamic v, {int fallback = 0}) {
      if (v is int) return v;
      final p = int.tryParse('$v');
      return p ?? fallback;
    }

    String _computeEnd(String hhmm, int addHours) {
      final parts = hhmm.split(':');
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      int total = (h * 60 + m) + addHours * 60;
      total %= (24 * 60);
      final hh = (total ~/ 60).toString().padLeft(2, '0');
      final mm = (total % 60).toString().padLeft(2, '0');
      return '$hh:$mm';
    }

    final String key = slotKey.padLeft(4, '0');
    String startStr = (bookingBase['start'] ?? '').toString();
    if (startStr.isEmpty) {
      startStr = _startFromKey(key); // derive if not given
    }

    await _db.runTransaction((tx) async {
      final facRef  = _db.collection('Facilities').doc(facilityId);
      final dayRef  = facRef.collection('Days').doc(dateYMD);
      final slotRef = dayRef.collection('Slots').doc(key);

      // ---- Facility info (capacity, duration, approval) ----
      final facSnap = await tx.get(facRef);
      final fac = facSnap.data() ?? {};

      final int capacity = (_toInt(fac['availableSlots'], fallback: 1)).clamp(1, 9999);
      final int durationHrs = _toInt(fac['bookingDurationHours'], fallback: 1).clamp(1, 24);

      // accept either "requireApproval" or "approval" flag
      final bool requireApproval = fac['requireApproval'] == true || fac['approval'] == true;

      // compute end if missing in bookingBase
      String endStr = (bookingBase['end'] ?? '').toString();
      if (endStr.isEmpty) {
        endStr = _computeEnd(startStr, durationHrs);
      }

      // ---- Slot ledger ----
      final slotSnap = await tx.get(slotRef);
      final int reserved = slotSnap.exists ? _toInt(slotSnap.data()?['reserved'], fallback: 0) : 0;

      if (reserved >= capacity) {
        throw Exception('FULL');
      }

      // find & lock the first free seat: Seats/001..Seats/{capacity}
      int? seatNum;
      for (int i = 1; i <= capacity; i++) {
        final seatId  = i.toString().padLeft(3, '0');
        final seatRef = slotRef.collection('Seats').doc(seatId);
        final seatSnap = await tx.get(seatRef);
        if (!seatSnap.exists) {
          tx.set(seatRef, {
            'taken': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          seatNum = i;
          break;
        }
      }
      if (seatNum == null) {
        throw Exception('FULL');
      }

      // bump reserved
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

      // ---- Bookings doc (merge with computed fields) ----
      final bRef = _db.collection('Bookings').doc();

      final Map<String, dynamic> booking = Map<String, dynamic>.from(bookingBase);
      booking['slotKey']  = key;
      booking['start']    = startStr;
      booking['end']      = endStr;
      booking['seat']     = seatNum;                         // int seat number
      booking['approval'] = booking['approval'] ??
          (requireApproval ? 'pending' : 'accepted');
      booking['createdAt'] = booking['createdAt'] ?? FieldValue.serverTimestamp();

      tx.set(bRef, booking);
    });
  }
}
