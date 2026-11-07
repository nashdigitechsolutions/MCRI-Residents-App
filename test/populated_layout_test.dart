// Layout checks with realistic data (the main overflow test uses empty
// lists): small phone, admin account, light + dark, real fonts.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcri_residents_app/providers/auth_provider.dart';
import 'package:mcri_residents_app/screens/events_screen.dart';
import 'package:mcri_residents_app/screens/house_rules_screen.dart';
import 'package:mcri_residents_app/screens/rooms_screen.dart';
import 'package:mcri_residents_app/screens/wifi_payments_screen.dart';
import 'package:mcri_residents_app/services/api_service.dart';
import 'package:mcri_residents_app/services/storage_service.dart';
import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:provider/provider.dart';

String _jwt(Map<String, dynamic> p) {
  String enc(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${enc({'alg': 'HS256'})}.${enc(p)}.sig';
}

Future<void> _fonts() async {
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable)
          .parent
          .parent
          .parent
          .parent
          .parent
          .parent
          .path;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  if (!Directory(dir).existsSync()) return;
  final l = FontLoader('Roboto');
  for (final f in [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]) {
    l.addFont(
      Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())),
    );
  }
  await l.load();
  final m = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File('$dir/materialicons-regular.otf').readAsBytesSync(),
        ),
      ),
    );
  await m.load();
}

Object _body(String path) {
  final now = DateTime.now();
  String at(int d, int h) =>
      DateTime(now.year, now.month, now.day + d, h).toIso8601String();
  if (path.endsWith('/events')) {
    return [
      {
        'event_id': 1,
        'title': 'Braai night with a very long name for testing',
        'location': 'Back garden by the big tree',
        'start_date': at(1, 18),
        'end_date': at(1, 21),
        'my_attendance_status': 'going',
      },
      {
        'event_id': 2,
        'title': 'House meeting',
        'location': 'Lounge',
        'start_date': at(3, 19),
        'end_date': at(3, 20),
      },
      {
        'event_id': 3,
        'title': 'Movie marathon',
        'start_date': at(12, 17),
        'end_date': at(12, 23),
      },
      {
        'event_id': 4,
        'title': 'Spring clean',
        'start_date': at(-5, 9),
        'end_date': at(-5, 12),
      },
    ];
  }
  if (path.endsWith('/house-rules')) {
    return [
      {
        'rule_id': 1,
        'title': 'Quiet hours after 22:00 on weeknights and weekends',
        'description': 'Keep music and calls low after 10pm.',
      },
      for (var i = 2; i < 7; i++) {'rule_id': i, 'title': 'Rule number $i'},
    ];
  }
  if (path.endsWith('/rooms')) {
    return [
      for (var i = 1; i <= 4; i++)
        {
          'room_id': i,
          'room_number': '10$i',
          'max_capacity': i == 4 ? 8 : 4,
          'current_occupancy': [3, 4, 1, 2][i - 1],
        },
    ];
  }
  if (path.endsWith('/residents')) {
    return [
      {
        'resident_id': 1,
        'user_id': 1,
        'room_id': 1,
        'username': 'alexandria',
        'first_name': 'Alexandria',
        'last_name': 'Montgomery-Smith',
      },
      {
        'resident_id': 2,
        'user_id': 8,
        'room_id': 1,
        'username': 'thabo',
        'first_name': 'Thabo',
      },
      {
        'resident_id': 5,
        'user_id': 11,
        'room_id': null,
        'username': 'a-resident-with-a-long-username',
      },
    ];
  }
  return [];
}

void main() {
  setUpAll(_fonts);
  final screens = <String, (Widget Function(), String?)>{
    'Events': (() => const EventsScreen(), null),
    'HouseRules (rule open)': (
      () => const HouseRulesScreen(),
      'Quiet hours after 22:00 on weeknights and weekends',
    ),
    'Rooms': (() => const RoomsScreen(), null),
    'WifiPayments': (() => const WifiPaymentsScreen(), null),
  };
  for (final dark in [false, true]) {
    for (final e in screens.entries) {
      testWidgets(
        '${e.key} with data fits 320x568 (${dark ? 'dark' : 'light'})',
        (tester) async {
          FlutterSecureStorage.setMockInitialValues({});
          ApiService.invalidateAll();
          await StorageService.setToken(
            _jwt({
              'user_id': 1,
              'role_id': 1,
              'username': 'Alexandria',
              'exp': 4102444800,
            }),
          );
          ApiService.client = MockClient(
            (req) async => http.Response(jsonEncode(_body(req.url.path)), 200),
          );
          final auth = AuthProvider();
          await auth.checkAuthStatus();
          tester.view.physicalSize = const Size(320, 568);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ChangeNotifierProvider.value(
              value: auth,
              child: MaterialApp(
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                home: e.value.$1(),
              ),
            ),
          );
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final tapText = e.value.$2;
          if (tapText != null) {
            await tester.tap(find.text(tapText));
            await tester.pump(const Duration(milliseconds: 400));
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(
            const SizedBox(),
          ); // stop repeating animations
        },
      );
    }
  }
}
