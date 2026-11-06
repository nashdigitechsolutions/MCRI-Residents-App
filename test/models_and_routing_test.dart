import 'package:flutter_test/flutter_test.dart';
import 'package:mcri_residents_app/models/equipment_request.dart';
import 'package:mcri_residents_app/models/notification.dart';
import 'package:mcri_residents_app/services/notification_router.dart';

void main() {
  group('AppNotification.route', () {
    Map<String, dynamic> base(Object? data) => {
          'user_notification_id': 7,
          'title': 'New poll: Friday dinner',
          'message': 'Vote now',
          'created_at': '2026-11-06T10:00:00Z',
          'data': data,
        };

    test('parses a JSON object route', () {
      final n = AppNotification.fromJson(base({'screen': 'poll', 'poll_id': 3}));
      expect(n.route, {'screen': 'poll', 'poll_id': 3});
    });

    test('parses a JSON-string route', () {
      final n = AppNotification.fromJson(base('{"screen":"equipment","tab":"issues"}'));
      expect(n.route?['tab'], 'issues');
    });

    test('missing route stays null (older rows)', () {
      expect(AppNotification.fromJson(base(null)).route, isNull);
    });
  });

  group('NotificationRouter.inferFromTitle (rows stored before routes)', () {
    test('maps known titles', () {
      expect(NotificationRouter.inferFromTitle('New poll: Lunch')?['screen'], 'poll');
      expect(NotificationRouter.inferFromTitle('New announcement: Water off')?['screen'], 'home');
      expect(NotificationRouter.inferFromTitle('Fault reported: Washing machine')?['screen'], 'equipment');
      expect(NotificationRouter.inferFromTitle('Bought: Kettle')?['screen'], 'equipment');
      expect(NotificationRouter.inferFromTitle('Welcome to MCRI Residents')?['screen'], 'profile');
    });

    test('unknown titles have no destination', () {
      expect(NotificationRouter.inferFromTitle('Hello'), isNull);
    });
  });

  group('EquipmentRequest', () {
    test('purchase request for a new item has no equipment id', () {
      final r = EquipmentRequest.fromJson({
        'equip_request_id': '12',
        'equipment_id': null,
        'item_name': 'Kettle',
        'quantity': 2,
        'reason': 'Ours broke',
        'status': 'approved',
        'request_date': '2026-11-06T10:00:00Z',
      });
      expect(r.equipmentId, isNull);
      expect(r.displayName, 'Kettle');
      expect(r.quantity, 2);
      expect(r.status, 'approved');
    });

    test('catalogue name wins over free-text name', () {
      final r = EquipmentRequest.fromJson({
        'equip_request_id': 1,
        'equipment_id': 4,
        'equipment_name': 'Iron (Block B)',
        'item_name': 'iron',
        'status': 'pending',
        'request_date': '2026-11-06T10:00:00Z',
      });
      expect(r.displayName, 'Iron (Block B)');
      expect(r.quantity, 1);
    });
  });
}
