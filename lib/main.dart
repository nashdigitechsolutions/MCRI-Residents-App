import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'navigation/app_navigator.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/unread_provider.dart';
import 'providers/websocket_provider.dart';
import 'screens/conversation_detail_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'services/api_service.dart';
import 'services/deep_link_service.dart';
import 'services/device_registration_service.dart';
import 'services/notification_router.dart';
import 'services/onesignal_service.dart';
import 'theme/app_theme.dart';
import 'widgets/animated_splash.dart';
import 'widgets/in_app_banner.dart';

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

  /// "Compact lists": tighter density everywhere (list tiles, buttons, chips).
  static final _compactCache = <ThemeData, ThemeData>{};
  static ThemeData _compact(ThemeData t) => _compactCache.putIfAbsent(
    t,
    () => t.copyWith(
      visualDensity: VisualDensity.compact,
      listTileTheme: t.listTileTheme.copyWith(dense: true),
    ),
  );

  bool _wasLoggedIn = false;
  bool _wasSocketConnected = false;

  @override
  void initState() {
    super.initState();

    // Push tapped (cold start, background or foreground): open its screen.
    // The router holds the route until the shell is ready.
    OneSignalService.listenForTaps(NotificationRouter.open);

    // Push arrived while the app is open: WhatsApp-style drop-down banner,
    // unless it's for the chat the user is already looking at.
    OneSignalService.listenForForeground((title, body, data) {
      final convo = data?['conversation_id'];
      final convoId = convo is int ? convo : int.tryParse('$convo');
      if (convoId != null &&
          convoId == ConversationDetailScreen.openConversationId) {
        return true; // already visible; swallow silently
      }
      if (!_authProvider.isLoggedIn) return false;
      // "In-app pop-ups" off: the Notifications badge still updates live.
      if (!_settingsProvider.prefs.inAppBanners) return true;
      InAppBanner.show(
        title: title,
        body: body,
        data: data,
        icon: data?['screen'] == 'conversation'
            ? Icons.chat_bubble_rounded
            : Icons.notifications_rounded,
      );
      return true;
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
    // I read a chat on another device (website, second phone): clear it here.
    _webSocketProvider.on(
      'read',
      (p) => _unreadProvider.onReadEvent(p, _authProvider.user?.userId),
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

  int? _lastUserId;

  void _onAuthChanged() {
    final loggedIn = _authProvider.isLoggedIn;
    final userId = _authProvider.user?.userId;
    // Same session, nothing to do. A different user while still signed in
    // means "Log in as…" started or ended: reset everything account-bound.
    if (loggedIn == _wasLoggedIn && (!loggedIn || userId == _lastUserId)) {
      return;
    }
    if (loggedIn && _wasLoggedIn && userId != _lastUserId) {
      _lastUserId = userId;
      _switchAccount();
      return;
    }
    _wasLoggedIn = loggedIn;
    _lastUserId = userId;

    if (loggedIn) {
      final settingsReady = _settingsProvider.loaded
          ? Future<void>.value()
          : _settingsProvider.fetch();
      if (_authProvider.token != null) {
        _webSocketProvider.connect(_authProvider.token!);
        _unreadProvider.refresh();
      }
      // Only (re)register for pushes once the user's settings are known, so
      // "Push notifications: off" survives an app restart.
      settingsReady.then((_) async {
        if (!_authProvider.isLoggedIn) return;
        // Never register this phone for someone else's pushes.
        if (_authProvider.isImpersonating) return;
        if (!_settingsProvider.prefs.notificationsEnabled) {
          DeviceRegistrationService.unregister();
          return;
        }
        final granted = await OneSignalService.requestPermission();
        if (granted && _authProvider.isLoggedIn) {
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
      shellTab.value = ShellTab.home;
      if (_authProvider.consumeSessionExpired()) {
        scaffoldMessengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text('Your session expired. Please sign in again.'),
          ),
        );
      }
    }
  }

  /// Signed-in user changed without a sign-out (start/end of "Log in as…").
  void _switchAccount() {
    _webSocketProvider.disconnect();
    ConversationDetailScreen.clearCache();
    _unreadProvider.reset();
    _settingsProvider.reset();
    navigatorKey.currentState?.popUntil((r) => r.isFirst);
    shellTab.value = ShellTab.home;
    _settingsProvider.fetch();
    final token = _authProvider.token;
    if (token != null) _webSocketProvider.connect(token);
    _unreadProvider.refresh();
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          _authProvider.isImpersonating
              ? 'Now viewing the app as ${_authProvider.user?.username ?? 'this user'}'
              : 'Back in your admin account',
        ),
      ),
    );
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
    if (state == AppLifecycleState.resumed) ApiService.invalidateAll();
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
      // Rebuild MaterialApp only for settings that change how it looks.
      child: Selector<SettingsProvider, (String, double, bool)>(
        selector: (_, s) =>
            (s.prefs.theme, s.prefs.textScale, s.prefs.compactLists),
        builder: (context, look, _) {
          final (theme, textScale, compact) = look;
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
            theme: compact ? _compact(_lightTheme) : _lightTheme,
            darkTheme: compact ? _compact(_darkTheme) : _darkTheme,
            // Respect the accessibility font size, but cap it so fixed-height
            // rows and cards can never overflow or overlap.
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              return MediaQuery(
                data: mq.copyWith(
                  // System size × the in-app "Text size" setting, capped.
                  textScaler: TextScaler.linear(
                    mq.textScaler.scale(1) * textScale,
                  ).clamp(minScaleFactor: 0.85, maxScaleFactor: 1.25),
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

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  // The launch animation plays once per cold start, and stays up until both
  // it has finished and the stored session has been checked.
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final showSplash = !_splashDone || auth.loading;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOutCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.98, end: 1.0).animate(anim),
          child: child,
        ),
      ),
      child: showSplash
          ? AnimatedSplash(
              key: const ValueKey('splash'),
              onFinished: () {
                if (mounted) setState(() => _splashDone = true);
              },
            )
          : auth.isLoggedIn
          ? const MainShell(key: ValueKey('shell'))
          : const LoginScreen(key: ValueKey('login')),
    );
  }
}
