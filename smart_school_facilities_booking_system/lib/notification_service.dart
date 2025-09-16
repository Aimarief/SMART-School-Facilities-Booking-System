import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  // ------------------ basic refs ------------------
  static CollectionReference<Map<String, dynamic>> _userInfo() {
    return FirebaseFirestore.instance.collection('UserInformation');
  }

  static CollectionReference<Map<String, dynamic>> _inboxOf(String uid) {
    return _userInfo().doc(uid).collection('Inbox');
  }

  // ------------------ name readers ------------------
  static Future<String> _readUserName(String uid) async {
    String result = '-';
    try {
      final doc = await _userInfo().doc(uid).get();
      if (doc.exists) {
        final m = doc.data();
        if (m != null) {
          if (m['name'] != null && m['name'].toString().trim().isNotEmpty) {
            result = m['name'].toString().trim();
          } else if (m['displayName'] != null && m['displayName'].toString().trim().isNotEmpty) {
            result = m['displayName'].toString().trim();
          } else if (m['fullName'] != null && m['fullName'].toString().trim().isNotEmpty) {
            result = m['fullName'].toString().trim();
          } else if (m['email'] != null && m['email'].toString().trim().isNotEmpty) {
            result = m['email'].toString().trim();
          }
        }
      }
    } catch (_) {}
    if (result.isEmpty) result = '-';
    return result;
  }

  static Future<String> _readFacilityName(String facilityId) async {
    String result = '-';
    if (facilityId.isEmpty) return result;
    try {
      final doc = await FirebaseFirestore.instance.collection('Facilities').doc(facilityId).get();
      if (doc.exists) {
        final m = doc.data();
        if (m != null) {
          if (m['name'] != null && m['name'].toString().trim().isNotEmpty) {
            result = m['name'].toString().trim();
          }
        }
      }
    } catch (_) {}
    if (result.isEmpty) result = '-';
    return result;
  }

  // ------------------ internal writer ------------------
  static Future<void> _sendToOneInbox({
    required String toUid,
    required Map<String, dynamic> payload,
  }) async {
    payload['createdAt'] = FieldValue.serverTimestamp();
    payload['isRead'] = false;
    payload['recipientId'] = toUid;
    await _inboxOf(toUid).add(payload);
  }

  static Future<void> sendBookingCreatedMails({
    required String bookingId,
    required String userId,
    required String bookedBy, // actor (who created)
    required String facilityId,
    required String managerId,
    required String approval,
    int?    seatIndex,                 // NEW (optional)
    String? bookingDate,               // NEW (optional, "YYYY-MM-DD")
    String? start,                     // NEW (optional, "HH:mm")
    String? end,                       // NEW (optional, "HH:mm")
    String? amendmentId,               // NEW (optional, when sending for an amendment)
  }) async {
    final String userName      = await _readUserName(userId);
    final String bookedByName  = await _readUserName(bookedBy);
    final String managerName   = await _readUserName(managerId);
    final String facilityName  = await _readFacilityName(facilityId);

    final Map<String, dynamic> base = <String, dynamic>{
      'type': 'booking_created',
      'bookingId': bookingId,
      'bookedBy': userId,
      'createdBy': bookedBy,
      'facilityId': facilityId,
      'managerId': managerId,
      'bookedByName': userName,
      'createdByName': bookedByName,
      'managerName': managerName,
      'facilityName': facilityName,
      'approval': approval,
      if (seatIndex != null) 'seatIndex': seatIndex,
      if (bookingDate != null) 'bookingDate': bookingDate,
      if (start != null) 'start': start,
      if (end != null) 'end': end,

      if (amendmentId != null && amendmentId.trim().isNotEmpty) ...{
        'amendmentId': amendmentId.trim(),
        'isAmendment': true,
        'requestType': 'amendment',
      },
      'createdAt': FieldValue.serverTimestamp(),
    };

    // write to your inbox collection / topic as you already do
    final Set<String> recipients = <String>{
      if (userId.trim().isNotEmpty) userId.trim(),
      if (managerId.trim().isNotEmpty) managerId.trim(),
      if (bookedBy.trim().isNotEmpty) bookedBy.trim(),
    };

    for (final to in recipients) {
      await _sendToOneInbox(toUid: to, payload: Map<String, dynamic>.from(base));
    }

  }

// _readUserName, _readFacilityName … unchanged


  static Future<void> sendBookingUpdatedMails({
    required String bookingId,
    required String userId,        // owner (booker)
    required String bookedBy,      // actor who edited
    required String facilityId,
    required String managerId,
    required String approval,

    // NEW required details
    required int seatIndex,        // 1-based
    required String bookingDate,   // "YYYY-MM-DD"
    required String start,         // "HH:MM"
    required String end,           // "HH:MM"
  }) async {
    final String userName     = await _readUserName(userId);
    final String bookedByName = await _readUserName(bookedBy);
    final String managerName  = await _readUserName(managerId);
    final String facilityName = await _readFacilityName(facilityId);

    final Map<String, dynamic> base = <String, dynamic>{
      'type': 'booking_updated',
      'bookingId': bookingId,

      // who/what
      'bookBy': userId,            // (kept same keys as before for Android)
      'createdBy': bookedBy,
      'facilityId': facilityId,
      'managerId': managerId,

      // friendly labels
      'bookByName': userName,
      'createdByName': bookedByName,
      'managerName': managerName,
      'facilityName': facilityName,

      // approval + NEW details
      'approval': approval,
      'seatIndex': seatIndex,
      'bookingDate': bookingDate,  // "YYYY-MM-DD"
      'start': start,              // "HH:MM"
      'end': end,                  // "HH:MM"
    };

    final Set<String> recipients = <String>{
      if (userId.trim().isNotEmpty) userId.trim(),
      if (managerId.trim().isNotEmpty) managerId.trim(),
      if (bookedBy.trim().isNotEmpty) bookedBy.trim(),
    };

    for (final to in recipients) {
      await _sendToOneInbox(toUid: to, payload: Map<String, dynamic>.from(base));
    }
  }


  // ------------------ NEW: approval status mails ------------------
  // type = 'approval_status', same payload as "edit booking", PLUS approval & reason
  static Future<void> sendBookingApprovalMails({
    required String bookingId,
    required String userId,        // booking owner
    required String bookedBy,      // actor who approved/rejected
    required String facilityId,
    required String managerId,
    required String approval,      // 'accepted' | 'rejected'
    String? approvalReason,

    // NEW required details
    required int seatIndex,        // 1-based
    required String bookingDate,   // "YYYY-MM-DD"
    required String start,         // "HH:MM"
    required String end,           // "HH:MM"
  }) async {
    final String userName     = await _readUserName(userId);
    final String bookedByName = await _readUserName(bookedBy);
    final String managerName  = await _readUserName(managerId);
    final String facilityName = await _readFacilityName(facilityId);

    final Map<String, dynamic> base = <String, dynamic>{
      'type': 'approval_status',
      'bookingId': bookingId,

      // who/what
      'bookBy': userId,            // keep SAME keys used elsewhere
      'createdBy': bookedBy,
      'facilityId': facilityId,
      'managerId': managerId,

      // friendly labels
      'bookByName': userName,
      'createdByName': bookedByName,
      'managerName': managerName,
      'facilityName': facilityName,

      // status + reason
      'approval': approval,        // accepted | rejected
      if (approvalReason != null)
        'approvalReason': approvalReason.trim().isEmpty ? '-' : approvalReason.trim(),

      // NEW details
      'seatIndex': seatIndex,
      'bookingDate': bookingDate,  // "YYYY-MM-DD"
      'start': start,              // "HH:MM"
      'end': end,                  // "HH:MM"
    };

    final Set<String> recipients = <String>{
      if (userId.trim().isNotEmpty) userId.trim(),
      if (managerId.trim().isNotEmpty) managerId.trim(),
      if (bookedBy.trim().isNotEmpty) bookedBy.trim(),
    };

    for (final to in recipients) {
      await _sendToOneInbox(toUid: to, payload: Map<String, dynamic>.from(base));
    }
  }

  static Future<void> sendRequestUpdateMails({
    required String bookingId,     // booking doc id
    required String userId,        // owner of the booking
    required int seatIndex,        // seat/slot index (int)
    required String start,         // "HH:MM"
    required String end,           // "HH:MM"
    required String facilityId,    // facility doc id
    required String bookingDate,   // "YYYY-MM-DD"
  }) async {
    try {
      final String to = userId.trim();
      if (to.isEmpty) return; // nothing to send

      final Map<String, dynamic> payload = <String, dynamic>{
        'type': 'request_update',   // <-- required mail type
        'bookingId': bookingId,
        'userId': userId,
        'seatIndex': seatIndex,
        'start': start,
        'end': end,
        'facilityId': facilityId,
        'bookingDate': bookingDate,
      };

      await _sendToOneInbox(toUid: to, payload: payload);
    } catch (_) {
      // keep silent to avoid breaking the flow; you can log if needed
    }
  }

  static Future<void> sendBookingDeletedMails({
    required String bookingId,
    required String userId,     // owner of the booking
    required String bookedBy,   // actor who deleted
    required String facilityId,
    required String managerId,
    required int seatIndex,
    required String start,
    required String end,
    required String bookingDate, // "YYYY-MM-DD"
  }) async {
    final String userName     = await _readUserName(userId);
    final String actorName    = await _readUserName(bookedBy);
    final String managerName  = await _readUserName(managerId);
    final String facilityName = await _readFacilityName(facilityId);

    final Map<String, dynamic> base = <String, dynamic>{
      'type': 'booking_deleted',
      'bookingId': bookingId,

      // who/what
      'bookedBy': userId,        // booking owner (Android reads bookedBy/bookBy)
      'createdBy': bookedBy,     // the deleter (actor)
      'managerId': managerId,
      'facilityId': facilityId,

      // friendly labels
      'bookedByName': userName,
      'createdByName': actorName,
      'managerName': managerName,
      'facilityName': facilityName,

      // extras you asked to store
      'seatIndex': seatIndex,
      'start': start,            // "HH:MM"
      'end': end,                // "HH:MM"
      'bookingDate': bookingDate // "YYYY-MM-DD"
    };

    // send to: user, manager, actor
    final Set<String> recipients = <String>{
      if (userId.trim().isNotEmpty) userId.trim(),
      if (managerId.trim().isNotEmpty) managerId.trim(),
      if (bookedBy.trim().isNotEmpty) bookedBy.trim(),
    };

    for (final to in recipients) {
      await _sendToOneInbox(toUid: to, payload: Map<String, dynamic>.from(base));
    }
  }

}
