import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/unread_provider.dart';
import 'providers/websocket_provider.dart';
import 'screens/conversation_detail_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'services/deep_link_service.dart';
import 'services/device_registration_service.dart';
import 'services/notification_router.dart';
import 'services/onesignal_service.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // debugPrint still writes to logcat / Console in release builds; silence it
  // so no API payloads or tokens ever reach device logs in production.
  if (kReleaseMode) debugPrint = (String? message, {int? wrapWidth}) {};
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  OneSignalService.initialize();
  runApp(const MyApp());
}

final navigatorKey = GlobalKey<NavigatorState>();
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final _authProvider = AuthProvider();
  final _settingsProvider = SettingsProvider();
  final _webSocketProvider = WebSocketProvider();
  final _unreadProvider = UnreadProvider();
  final _deepLinkService = DeepLinkService();

  // Built once; rebuilding ThemeData on every settings change is wasteful.
  static final _lightTheme = AppTheme.light();
  static final _darkTheme = AppTheme.dark();

  bool _wasLoggedIn = false;
  bool _wasSocketConnected = false;

  @override
  void initState() {
    super.initState();

    OneSignalService.listenForTaps((data) {
      final ctx = navigatorKey.currentContext;
      if (ctx != null) NotificationRouter.handle(ctx, data);
    });

    _authProvider.addListener(_onAuthChanged);
    _authProvider.checkAuthStatus();
    _settingsProvider.addListener(_onSettingsChanged);

    _unreadProvider.reset();
    _webSocketProvider.on('message', _unreadProvider.onMessageEvent);
    _webSocketProvider.on('reaction', _unreadProvider.onReactionEvent);
    _webSocketProvider.on(
      'notification',
      (_) => _unreadProvider.onNotificationEvent(),
    );

    // Catch up on anything missed whenever the socket (re)connects.
    _webSocketProvider.addListener(_onSocketChanged);
    WidgetsBinding.instance.addObserver(this);

    _deepLinkService.listen((token) async {
      try {
        await _authProvider.handleOAuthSuccess(token);
      } catch (_) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Google sign-in failed. Please try again.'),
          ),
        );
      }
    });
  }

  void _onAuthChanged() {
    final loggedIn = _authProvider.isLoggedIn;
    if (loggedIn == _wasLoggedIn) return; // ignore non-transition notifies
    _wasLoggedIn = loggedIn;

    if (loggedIn) {
      if (!_settingsProvider.loaded) _settingsProvider.fetch();
      if (_authProvider.token != null) {
        _webSocketProvider.connect(_authProvider.token!);
        _unreadProvider.refresh();
      }
      OneSignalService.requestPermission().then((granted) {
        final pushWanted =
            !_settingsProvider.loaded ||
            _settingsProvider.prefs.notificationsEnabled;
        if (granted && pushWanted && _authProvider.isLoggedIn) {
          DeviceRegistrationService.registerWhenReady();
        }
      });
    } else {
      // Push unregistration happens inside AuthProvider.logout(), while the
      // token is still valid.
      _settingsProvider.reset();
      _webSocketProvider.disconnect();
      _unreadProvider.reset();
      ConversationDetailScreen.clearCache();
      navigatorKey.currentState?.popUntil((r) => r.isFirst);
      if (_authProvider.consumeSessionExpired()) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Your session expired. Please sign in again.'),
          ),
        );
      }
    }
  }

  void _onSocketChanged() {
    final connected = _webSocketProvider.isConnected;
    if (connected && !_wasSocketConnected && _authProvider.isLoggedIn) {
      _unreadProvider.refresh();
    }
    _wasSocketConnected = connected;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _authProvider.isLoggedIn) {
      _unreadProvider.refresh();
    }
  }

  void _onSettingsChanged() {
    _unreadProvider.setChatBadgeEnabled(
      _settingsProvider.prefs.chatNotifications,
    );
  }

  @override
  void dispose() {
    _authProvider.removeListener(_onAuthChanged);
    _settingsProvider.removeListener(_onSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    _webSocketProvider.removeListener(_onSocketChanged);
    _deepLinkService.dispose();
    _webSocketProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _settingsProvider),
        ChangeNotifierProvider.value(value: _webSocketProvider),
        ChangeNotifierProvider.value(value: _unreadProvider),
      ],
      // Only the theme setting rebuilds MaterialApp, not every settings change.
      child: Selector<SettingsProvider, String>(
        selector: (_, s) => s.prefs.theme,
        builder: (context, theme, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            scaffoldMessengerKey: scaffoldMessengerKey,
            title: 'MCRI Residents',
            debugShowCheckedModeBanner: false,
            themeMode: switch (theme) {
              'dark' => ThemeMode.dark,
              'system' => ThemeMode.system,
              _ => ThemeMode.light,
            },
            theme: _lightTheme,
            darkTheme: _darkTheme,
            // Respect the accessibility font size, but cap it so fixed-height
            // rows and cards can never overflow or overlap.
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(
                  textScaler: mq.textScaler.clamp(
                    minScaleFactor: 0.9,
                    maxScaleFactor: 1.25,
                  ),
                ),
                child: child!,
              );
            },
            home: const _AuthGate(),
          );
        },
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: auth.loading
          ? const _Splash(key: ValueKey('splash'))
          : auth.isLoggedIn
          ? const MainShell(key: ValueKey('shell'))
          : const LoginScreen(key: ValueKey('login')),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'lib/assets/logo.png',
              width: 72,
              height: 72,
              cacheWidth: 216,
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ],
        ),
      ),
    );
  }
}
