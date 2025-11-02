import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
//---------------------------------------
// get user info from database
//---------------------------------------
  static CollectionReference<Map<String, dynamic>> _userInfo() {
    return FirebaseFirestore.instance.collection('UserInformation');
  }
//---------------------------------------
// write data to database
//---------------------------------------

  static CollectionReference<Map<String, dynamic>> _inboxOf(String uid) {
    return _userInfo().doc(uid).collection('Inbox');
  }

//---------------------------------------
// get user email
//---------------------------------------

  static Future<String> _readUserEmail(String uid) async {
    String result = '-';
    try {
      final doc = await _userInfo().doc(uid).get();
      if (doc.exists) {
        final m = doc.data();
        if (m != null) {
          if (m['email'] != null && m['email'].toString().trim().isNotEmpty) {
            result = m['email'].toString().trim();
          }
        }
      }
    } catch (_) {}
    if (result.isEmpty) result = '-';
    return result;
  }
//---------------------------------------
// get facility name
//---------------------------------------
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

//---------------------------------------
// the one who write will always recieve the email
//---------------------------------------

  static Future<void> _sendToOneInbox({
    required String toUid,
    required Map<String, dynamic> payload,
  }) async {
    payload['createdAt'] = FieldValue.serverTimestamp();
    payload['isRead'] = false;
    payload['recipientId'] = toUid;
    //---------------------------------------
// this will write the data into inbox database
//---------------------------------------
    await _inboxOf(toUid).add(payload);
  }
//---------------------------------------
// when booking is created mail
//---------------------------------------
  static Future<void> sendBookingCreatedMails({
    required String bookingId,
    required String userId,
    required String bookedBy,
    required String facilityId,
    required String managerId,
    required String approval,
    int? seatIndex,
    String? bookingDate,
    String? start,
    String? end,
    String? amendmentId,
  }) async {
    //---------------------------------------
// get all of their email
//---------------------------------------
    final String userName      = await _readUserEmail(userId);
    final String bookedByName  = await _readUserEmail(bookedBy);
    final String managerName   = await _readUserEmail(managerId);
    final String facilityName  = await _readFacilityName(facilityId);
//---------------------------------------
//  the data that will be send to user inbox
//---------------------------------------
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

    //---------------------------------------
// the one who will be sent to
//---------------------------------------
    final Set<String> recipients = <String>{
      if (userId.trim().isNotEmpty) userId.trim(),
      if (managerId.trim().isNotEmpty) managerId.trim(),
      if (bookedBy.trim().isNotEmpty) bookedBy.trim(),
    };

    for (final to in recipients) {
      await _sendToOneInbox(toUid: to, payload: Map<String, dynamic>.from(base));
    }

  }

//---------------------------------------
// for update booking mails
//---------------------------------------
  static Future<void> sendBookingUpdatedMails({
    required String bookingId,
    required String userId,
    required String bookedBy,
    required String facilityId,
    required String managerId,
    required String approval,
    required int seatIndex,
    required String bookingDate,
    required String start,
    required String end,
  }) async {
    final String userName     = await _readUserEmail(userId);
    final String bookedByName = await _readUserEmail(bookedBy);
    final String managerName  = await _readUserEmail(managerId);
    final String facilityName = await _readFacilityName(facilityId);

    final Map<String, dynamic> base = <String, dynamic>{
      'type': 'booking_updated',
      'bookingId': bookingId,
      'bookBy': userId,
      'createdBy': bookedBy,
      'facilityId': facilityId,
      'managerId': managerId,
      'bookByName': userName,
      'createdByName': bookedByName,
      'managerName': managerName,
      'facilityName': facilityName,
      'approval': approval,
      'seatIndex': seatIndex,
      'bookingDate': bookingDate,
      'start': start,
      'end': end,
    };

    final Set<String> recipients = <String>{
      if (userId.trim().isNotEmpty) userId.trim(),
      if (managerId.trim().isNotEmpty) managerId.trim(),
      if (bookedBy.trim().isNotEmpty) bookedBy.trim(),
    };
//---------------------------------------
// send the email to database
//---------------------------------------
    for (final to in recipients) {
      await _sendToOneInbox(toUid: to, payload: Map<String, dynamic>.from(base));
    }
  }

//---------------------------------------
// for new approval for booking
//---------------------------------------
  static Future<void> sendBookingApprovalMails({
    required String bookingId,
    required String userId,
    required String bookedBy,
    required String facilityId,
    required String managerId,
    required String approval,
    String? approvalReason,
    required int seatIndex,
    required String bookingDate,
    required String start,
    required String end,
  }) async {
    final String userName     = await _readUserEmail(userId);
    final String bookedByName = await _readUserEmail(bookedBy);
    final String managerName  = await _readUserEmail(managerId);
    final String facilityName = await _readFacilityName(facilityId);

    final Map<String, dynamic> base = <String, dynamic>{
      'type': 'approval_status',
      'bookingId': bookingId,
      'bookBy': userId,
      'createdBy': bookedBy,
      'facilityId': facilityId,
      'managerId': managerId,
      'bookByName': userName,
      'createdByName': bookedByName,
      'managerName': managerName,
      'facilityName': facilityName,
      'approval': approval, // accepted | rejected
      if (approvalReason != null)
        'approvalReason': approvalReason.trim().isEmpty ? '-' : approvalReason.trim(),
      'seatIndex': seatIndex,
      'bookingDate': bookingDate,
      'start': start,
      'end': end,
    };
    final Set<String> recipients = <String>{
      if (userId.trim().isNotEmpty) userId.trim(),
      if (managerId.trim().isNotEmpty) managerId.trim(),
      if (bookedBy.trim().isNotEmpty) bookedBy.trim(),
    };
//---------------------------------------
// send email to different user base on above
//---------------------------------------
    for (final to in recipients) {
      await _sendToOneInbox(toUid: to, payload: Map<String, dynamic>.from(base));
    }
  }

  //---------------------------------------
// send request user to update facility time
//---------------------------------------
  static Future<void> sendRequestUpdateMails({
    required String bookingId,
    required String userId,
    required int seatIndex,
    required String start,
    required String end,
    required String facilityId,
    required String bookingDate,
  }) async {
    try {
      final String to = userId.trim();
      if (to.isEmpty) return;

      final Map<String, dynamic> payload = <String, dynamic>{
        'type': 'request_update',
        'bookingId': bookingId,
        'userId': userId,
        'seatIndex': seatIndex,
        'start': start,
        'end': end,
        'facilityId': facilityId,
        'bookingDate': bookingDate,
      };
//---------------------------------------
// only send to the user
//---------------------------------------
      await _sendToOneInbox(toUid: to, payload: payload);
    } catch (_) {

    }
  }
//---------------------------------------
// when bookign is deleted
//---------------------------------------
  static Future<void> sendBookingDeletedMails({
    required String bookingId,
    required String userId,
    required String bookedBy,
    required String facilityId,
    required String managerId,
    required int seatIndex,
    required String start,
    required String end,
    required String bookingDate,
  }) async {
    final String userName     = await _readUserEmail(userId);
    final String actorName    = await _readUserEmail(bookedBy);
    final String managerName  = await _readUserEmail(managerId);
    final String facilityName = await _readFacilityName(facilityId);

    final Map<String, dynamic> base = <String, dynamic>{
      'type': 'booking_deleted',
      'bookingId': bookingId,
      'bookedBy': userId,
      'createdBy': bookedBy,
      'managerId': managerId,
      'facilityId': facilityId,
      'bookedByName': userName,
      'createdByName': actorName,
      'managerName': managerName,
      'facilityName': facilityName,
      'seatIndex': seatIndex,
      'start': start,
      'end': end,
      'bookingDate': bookingDate
    };

    final Set<String> recipients = <String>{
      if (userId.trim().isNotEmpty) userId.trim(),
      if (managerId.trim().isNotEmpty) managerId.trim(),
      if (bookedBy.trim().isNotEmpty) bookedBy.trim(),
    };
//---------------------------------------
// send to user base on above
//---------------------------------------
    for (final to in recipients) {
      await _sendToOneInbox(toUid: to, payload: Map<String, dynamic>.from(base));
    }
  }

}
