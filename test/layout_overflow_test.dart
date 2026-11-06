// Renders every screen on a small phone (320x640) with the largest font scale
// the app allows (1.25) and fails on any RenderFlex overflow — i.e. any view
// that would overlap or clip.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mcri_residents_app/providers/auth_provider.dart';
import 'package:mcri_residents_app/providers/settings_provider.dart';
import 'package:mcri_residents_app/providers/unread_provider.dart';
import 'package:mcri_residents_app/providers/websocket_provider.dart';
import 'package:mcri_residents_app/screens/conversation_screen.dart';
import 'package:mcri_residents_app/screens/duties_screen.dart';
import 'package:mcri_residents_app/screens/equipment_screen.dart';
import 'package:mcri_residents_app/screens/events_screen.dart';
import 'package:mcri_residents_app/screens/forgot_password_screen.dart';
import 'package:mcri_residents_app/screens/home_screen.dart';
import 'package:mcri_residents_app/screens/house_rules_screen.dart';
import 'package:mcri_residents_app/screens/login_screen.dart';
import 'package:mcri_residents_app/screens/more_screen.dart';
import 'package:mcri_residents_app/screens/notifications_screen.dart';
import 'package:mcri_residents_app/screens/polls_screen.dart';
import 'package:mcri_residents_app/screens/profile_screen.dart';
import 'package:mcri_residents_app/screens/rooms_screen.dart';
import 'package:mcri_residents_app/screens/settings_screen.dart';
import 'package:mcri_residents_app/screens/signup_screen.dart';
import 'package:mcri_residents_app/screens/weekly_menu_screen.dart';
import 'package:mcri_residents_app/services/api_service.dart';
import 'package:mcri_residents_app/services/storage_service.dart';
import 'package:mcri_residents_app/theme/app_theme.dart';
import 'package:provider/provider.dart';

String _jwt(Map<String, dynamic> p) {
  String enc(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${enc({'alg': 'HS256'})}.${enc(p)}.sig';
}

final _screens = <String, Widget Function()>{
  'Login': () => const LoginScreen(),
  'Signup': () => const SignupScreen(),
  'ForgotPassword': () => const ForgotPasswordScreen(),
  'Home': () => const HomeScreen(),
  'Conversations': () => const ConversationsScreen(),
  'Polls': () => const PollsScreen(),
  'Profile': () => const ProfileScreen(),
  'Settings': () => const SettingsScreen(),
  'More': () => const MoreScreen(),
  'Notifications': () => const NotificationsScreen(),
  'Duties': () => const DutiesScreen(),
  'Events': () => const EventsScreen(),
  'Equipment': () => const EquipmentScreen(),
  'HouseRules': () => const HouseRulesScreen(),
  'Rooms': () => const RoomsScreen(),
  'WeeklyMenu': () => const WeeklyMenuScreen(),
};

/// The default test font draws every glyph as a full square (much wider than
/// any real font). Load the real Roboto + Material Icons from the Flutter SDK
/// so widths match an actual Android phone.
Future<void> _loadRealFonts() async {
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
  if (!Directory(dir).existsSync()) return; // fall back to the test font
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$dir/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
    'roboto-light.ttf',
  ]);
  await load('MaterialIcons', ['materialicons-regular.otf']);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadRealFonts);

  for (final dark in [false, true]) {
    for (final entry in _screens.entries) {
      testWidgets(
        '${entry.key} fits 320x640 @1.25x (${dark ? 'dark' : 'light'})',
        (tester) async {
          FlutterSecureStorage.setMockInitialValues({});
          await StorageService.setToken(
            _jwt({
              'user_id': 1,
              'role_id': 1,
              'username': 'Alexandria Montgomery-Smith',
            }),
          );
          // Every endpoint answers with an empty list / object.
          ApiService.client = MockClient((req) async {
            final p = req.url.path;
            final isObject =
                p.endsWith('/profile') || p.endsWith('/user-settings');
            return http.Response(isObject ? '{}' : '[]', 200);
          });

          final auth = AuthProvider();
          await auth.checkAuthStatus();

          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MultiProvider(
              providers: [
                ChangeNotifierProvider.value(value: auth),
                ChangeNotifierProvider(create: (_) => SettingsProvider()),
                ChangeNotifierProvider(create: (_) => WebSocketProvider()),
                ChangeNotifierProvider(create: (_) => UnreadProvider()),
              ],
              child: MaterialApp(
                theme: AppTheme.light(),
                darkTheme: AppTheme.dark(),
                themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.25)),
                  child: child!,
                ),
                home: Scaffold(body: entry.value()),
              ),
            ),
          );
          // Let fetches resolve, without waiting on infinite animations.
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final error = tester.takeException();
          if (error is FlutterError) {
            final where = error
                .toStringDeep()
                .split('\n')
                .firstWhere((l) => l.contains('lib/'), orElse: () => '');
            fail('${error.message}\n$where');
          }
          expect(error, isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 1));
        },
      );
    }
  }
}
