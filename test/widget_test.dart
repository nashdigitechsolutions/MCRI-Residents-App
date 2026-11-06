import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcri_residents_app/config/env.dart';
import 'package:mcri_residents_app/services/api_service.dart';
import 'package:mcri_residents_app/services/storage_service.dart';
import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:mcri_residents_app/widgets/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await StorageService.deleteToken();
    ApiService.onUnauthorized = null;
  });

  group('config', () {
    test('app talks to the same API host as the website', () {
      expect(AppConfig.apiBaseUrl, 'https://api.mcriresidents.online/api');
      expect(AppConfig.wsUrl, 'wss://api.mcriresidents.online/api/ws');
    });
  });

  group('ApiService', () {
    test('sends bearer token and decodes JSON', () async {
      await StorageService.setToken('abc');
      ApiService.client = MockClient((req) async {
        expect(req.headers['Authorization'], 'Bearer abc');
        expect(req.url.toString(), '${AppConfig.apiBaseUrl}/rooms');
        return http.Response('[{"id":1}]', 200);
      });
      expect(await ApiService.get('/rooms'), [
        {'id': 1},
      ]);
    });

    test('extracts Zod-in-a-string error message', () async {
      ApiService.client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': jsonEncode([
              {'message': 'Invalid email address'},
            ]),
          }),
          400,
        ),
      );
      expect(
        () => ApiService.post('/signup', {}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'Invalid email address',
          ),
        ),
      );
    });

    test('non-JSON 502 page does not crash', () async {
      ApiService.client = MockClient(
        (_) async => http.Response('<html>Bad gateway</html>', 502),
      );
      expect(
        () => ApiService.get('/rooms'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 502)),
      );
    });

    test('network failure becomes a friendly ApiException(0)', () async {
      ApiService.client = MockClient(
        (_) async => throw const SocketException('offline'),
      );
      expect(
        () => ApiService.delete('/rooms/1'),
        throwsA(
          isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true),
        ),
      );
    });

    test('401 on an authenticated call triggers sign-out hook', () async {
      await StorageService.setToken('expired');
      var fired = false;
      ApiService.onUnauthorized = () => fired = true;
      ApiService.client = MockClient(
        (_) async => http.Response('{"message":"nope"}', 401),
      );
      await expectLater(
        ApiService.get('/profile'),
        throwsA(isA<ApiException>()),
      );
      expect(fired, isTrue);
    });

    test('401 from /login (wrong password) does NOT sign out', () async {
      await StorageService.setToken('valid');
      var fired = false;
      ApiService.onUnauthorized = () => fired = true;
      ApiService.client = MockClient(
        (_) async => http.Response('{"message":"bad creds"}', 401),
      );
      await expectLater(
        ApiService.post('/login', {}),
        throwsA(isA<ApiException>()),
      );
      expect(fired, isFalse);
    });
  });

  testWidgets('OptionCard renders and reports taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: OptionGrid(
            children: [
              OptionCard(
                icon: Icons.event,
                title: 'Events',
                subtitle: 'Upcoming community events with a very long caption that wraps',
                selected: true,
                onTap: () => taps++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Events'));
    expect(taps, 1);
    expect(tester.takeException(), isNull); // no overflow
  });
}
