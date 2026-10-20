import 'package:flutter/material.dart';
import 'package:mcri_residents_app/screens/conversation_detail_screen.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/websocket_provider.dart';
import 'providers/unread_provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'services/deep_link_service.dart';
import 'services/onesignal_service.dart';
import 'services/device_registration_service.dart';
import 'services/notification_router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  OneSignalService.initialize();
  runApp(const MyApp());
}

final navigatorKey = GlobalKey<NavigatorState>();

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

    _deepLinkService.listen((token) {
      _authProvider.handleOAuthSuccess(token);
    });
  }

  void _onAuthChanged() {
    if (_authProvider.isLoggedIn) {
      if (!_settingsProvider.loaded) _settingsProvider.fetch();
      if (_authProvider.token != null) {
        _webSocketProvider.connect(_authProvider.token!);
        _unreadProvider.refresh();
      }
      OneSignalService.requestPermission().then((granted) {
        final pushWanted =
            !_settingsProvider.loaded ||
            _settingsProvider.prefs.notificationsEnabled;
        if (granted && pushWanted) {
          DeviceRegistrationService.registerWhenReady();
        }
      });
    } else {
      _settingsProvider.reset();
      _webSocketProvider.disconnect();
      _unreadProvider.reset();
      DeviceRegistrationService.unregister();
      ConversationDetailScreen.clearCache();
    }
  }

  bool _wasSocketConnected = false;

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

  ThemeMode _themeMode() {
    switch (_settingsProvider.prefs.theme) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
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
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return MaterialApp(
            navigatorKey: navigatorKey,
            title: 'MCRI Residents',
            debugShowCheckedModeBanner: false,
            themeMode: _themeMode(),
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF3355FF),
              ),
              scaffoldBackgroundColor: const Color(0xFFF7F6F3),
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF3355FF),
                brightness: Brightness.dark,
              ),
              scaffoldBackgroundColor: const Color(0xFF121212),
              useMaterial3: true,
            ),
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
    if (auth.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return auth.isLoggedIn ? const MainShell() : const LoginScreen();
  }
}
