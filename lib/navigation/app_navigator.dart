import 'package:flutter/material.dart';

/// Global navigation handles, shared by main.dart, the notification router
/// and the in-app banner (kept here to avoid importing main.dart).
final navigatorKey = GlobalKey<NavigatorState>();
final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Bottom-tab indexes in MainShell.
abstract final class ShellTab {
  static const messages = 0;
  static const polls = 1;
  static const home = 2;
  static const profile = 3;
  static const settings = 4;
}

/// The selected MainShell tab. Anything (e.g. a notification tap) can switch
/// tabs by setting this; MainShell listens.
final shellTab = ValueNotifier<int>(ShellTab.home);
