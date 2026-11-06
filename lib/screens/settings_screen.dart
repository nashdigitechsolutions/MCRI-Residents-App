import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/env.dart';
import '../navigation/app_navigator.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../services/biometric_store.dart';
import '../services/device_registration_service.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import '../widgets/app_loader.dart';
import '../widgets/in_app_banner.dart';
import '../widgets/ui.dart';
import 'conversation_detail_screen.dart';
import 'profile_screen.dart';

const _appVersion = '1.1.0';

/// Every switch here does something real:
/// - notification switches filter pushes on the server (per category) and
///   register/unregister this device,
/// - appearance switches restyle the whole app instantly,
/// - privacy hides your availability from other residents.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _bioAvailable;
  bool _bioEnabled = false;
  bool _bioBusy = false;

  @override
  void initState() {
    super.initState();
    _loadBiometrics();
  }

  Future<void> _loadBiometrics() async {
    final available = await BiometricStore.isAvailable();
    final enabled = available && await BiometricStore.isUsable();
    if (mounted) {
      setState(() {
        _bioAvailable = available;
        _bioEnabled = enabled;
      });
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _update(Preferences Function(Preferences) updater) async {
    AppHaptics.selection();
    final ok = await context.read<SettingsProvider>().update(updater);
    if (!ok && mounted) _toast('Could not save that change — please try again');
  }

  Future<void> _setPush(bool on) async {
    await _update((p) => p.copyWith(notificationsEnabled: on));
    if (on) {
      DeviceRegistrationService.registerWhenReady();
    } else {
      DeviceRegistrationService.unregister();
    }
  }

  // ── Biometric sign-in ──────────────────────────────────────────────────
  Future<void> _setBiometrics(bool on) async {
    if (_bioBusy) return;
    if (!on) {
      await BiometricStore.clear();
      setState(() => _bioEnabled = false);
      _toast('Biometric sign-in turned off');
      return;
    }
    final email = context.read<AuthProvider>().user?.email ?? '';
    final password = await _askPassword();
    if (password == null || password.isEmpty || !mounted) return;
    setState(() => _bioBusy = true);
    try {
      // Verify the password before storing it for biometric sign-in.
      await ApiService.post('/login', {'email': email, 'password': password});
      if (!await BiometricStore.confirm(
        'Confirm to enable biometric sign-in',
      )) {
        return;
      }
      await BiometricStore.save(email, password);
      if (mounted) setState(() => _bioEnabled = true);
      _toast('Biometric sign-in is on');
    } on ApiException catch (e) {
      _toast(e.statusCode == 401 ? 'Incorrect password' : e.message);
    } finally {
      if (mounted) setState(() => _bioBusy = false);
    }
  }

  Future<String?> _askPassword() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm your password'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Password'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  // ── Other actions ──────────────────────────────────────────────────────
  Future<void> _changePassword() async {
    final email = context.read<AuthProvider>().user?.email;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangePasswordSheet(email: email),
    );
    if (ok == true) _toast('Password changed');
  }

  void _clearCache() {
    ConversationDetailScreen.clearCache();
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    _toast('Cached data cleared');
  }

  void _testBanner() {
    InAppBanner.show(
      title: 'This is how alerts look',
      body: 'Tap a notification to jump straight to what it\'s about.',
      icon: Icons.notifications_active_rounded,
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You\'ll need to sign in again to use the app on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.dangerDark,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await context.read<AuthProvider>().logout();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final p = settings.prefs;
    final user = context.select<AuthProvider, String?>((a) => a.user?.email);

    if (!settings.loaded) {
      return const AppLoadingView(message: 'Loading your settings…');
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        PageHeading(
          eyebrow: 'Preferences',
          title: 'Settings',
          subtitle: user == null ? null : 'Signed in as $user',
        ),
        const SizedBox(height: 20),

        _Section(
          title: 'Account',
          children: [
            _NavRow(
              icon: Icons.person_outline_rounded,
              label: 'Edit profile',
              onTap: () => shellTab.value = ShellTab.profile,
            ),
            _NavRow(
              icon: Icons.lock_outline_rounded,
              label: 'Change password',
              onTap: _changePassword,
            ),
            if (_bioAvailable == true)
              _SwitchRow(
                icon: Icons.fingerprint_rounded,
                label: 'Biometric sign-in',
                description: 'Use fingerprint or face to sign in',
                value: _bioEnabled,
                busy: _bioBusy,
                onChanged: _setBiometrics,
              ),
          ],
        ),

        _Section(
          title: 'Notifications',
          footer: 'Turned-off categories still appear in your Notifications list — you just won\'t be alerted.',
          children: [
            _SwitchRow(
              icon: Icons.notifications_outlined,
              label: 'Push notifications',
              description: 'Alerts on this phone when the app is closed',
              value: p.notificationsEnabled,
              onChanged: _setPush,
            ),
            _SwitchRow(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Chat messages',
              description: 'Message alerts and the unread badge',
              value: p.chatNotifications,
              enabled: p.notificationsEnabled,
              onChanged: (v) =>
                  _update((x) => x.copyWith(chatNotifications: v)),
            ),
            _SwitchRow(
              icon: Icons.campaign_outlined,
              label: 'Announcements',
              value: p.notifyAnnouncements,
              enabled: p.notificationsEnabled,
              onChanged: (v) =>
                  _update((x) => x.copyWith(notifyAnnouncements: v)),
            ),
            _SwitchRow(
              icon: Icons.ramen_dining_outlined,
              label: 'Meal polls',
              value: p.notifyPolls,
              enabled: p.notificationsEnabled,
              onChanged: (v) => _update((x) => x.copyWith(notifyPolls: v)),
            ),
            _SwitchRow(
              icon: Icons.build_outlined,
              label: 'Equipment & repairs',
              value: p.notifyEquipment,
              enabled: p.notificationsEnabled,
              onChanged: (v) => _update((x) => x.copyWith(notifyEquipment: v)),
            ),
            _SwitchRow(
              icon: Icons.calendar_today_outlined,
              label: 'Events',
              value: p.notifyEvents,
              enabled: p.notificationsEnabled,
              onChanged: (v) => _update((x) => x.copyWith(notifyEvents: v)),
            ),
            _SwitchRow(
              icon: Icons.cleaning_services_outlined,
              label: 'Duties',
              value: p.notifyDuties,
              enabled: p.notificationsEnabled,
              onChanged: (v) => _update((x) => x.copyWith(notifyDuties: v)),
            ),
            _SwitchRow(
              icon: Icons.restaurant_outlined,
              label: 'Weekly menu',
              value: p.notifyMenu,
              enabled: p.notificationsEnabled,
              onChanged: (v) => _update((x) => x.copyWith(notifyMenu: v)),
            ),
            _SwitchRow(
              icon: Icons.web_asset_rounded,
              label: 'In-app pop-ups',
              description: 'Drop-down banner while you\'re using the app',
              value: p.inAppBanners,
              onChanged: (v) => _update((x) => x.copyWith(inAppBanners: v)),
            ),
            _NavRow(
              icon: Icons.play_circle_outline_rounded,
              label: 'Preview an alert',
              onTap: _testBanner,
            ),
          ],
        ),

        _Section(
          title: 'Privacy',
          children: [
            _SwitchRow(
              icon: Icons.shield_outlined,
              label: 'Show availability status',
              description: 'Let others see when you\'re around the house',
              value: p.showOnlineStatus,
              onChanged: (v) => _update((x) => x.copyWith(showOnlineStatus: v)),
            ),
          ],
        ),

        _Section(
          title: 'Appearance',
          children: [
            _ChoiceRow(
              icon: Icons.dark_mode_outlined,
              label: 'Theme',
              value: p.theme,
              options: const {
                'light': 'Light',
                'dark': 'Dark',
                'system': 'Auto',
              },
              onChanged: (v) => _update((x) => x.copyWith(theme: v)),
            ),
            _ChoiceRow(
              icon: Icons.format_size_rounded,
              label: 'Text size',
              value: p.textSize,
              options: const {'small': 'A−', 'normal': 'A', 'large': 'A+'},
              onChanged: (v) => _update((x) => x.copyWith(textSize: v)),
            ),
            _SwitchRow(
              icon: Icons.view_agenda_outlined,
              label: 'Compact lists',
              description: 'Tighter spacing to fit more on screen',
              value: p.compactLists,
              onChanged: (v) => _update((x) => x.copyWith(compactLists: v)),
            ),
            _SwitchRow(
              icon: Icons.vibration_rounded,
              label: 'Vibration feedback',
              description: 'Light taps when you switch tabs and get alerts',
              value: p.haptics,
              onChanged: (v) => _update((x) => x.copyWith(haptics: v)),
            ),
          ],
        ),

        _Section(
          title: 'Storage & about',
          children: [
            _NavRow(
              icon: Icons.cleaning_services_rounded,
              label: 'Clear cached data',
              trailing: 'Frees space; nothing is lost',
              onTap: _clearCache,
            ),
            _NavRow(
              icon: Icons.language_rounded,
              label: 'Open the website',
              trailing: AppConfig.webHost,
              onTap: () => launchUrl(
                Uri.https(AppConfig.webHost),
                mode: LaunchMode.externalApplication,
              ),
            ),
            const _NavRow(
              icon: Icons.info_outline_rounded,
              label: 'Version',
              trailing: _appVersion,
            ),
          ],
        ),

        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _confirmLogout,
            icon: const Icon(
              Icons.logout,
              color: AppColors.dangerDark,
              size: 18,
            ),
            label: const Text(
              'Log out',
              style: TextStyle(color: AppColors.dangerDark),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: AppColors.dangerDark.withValues(alpha: 0.35),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────────── rows ─────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final String? footer;
  const _Section({required this.title, required this.children, this.footer});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, indent: 52, color: colors.outlineVariant));
      }
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Eyebrow(title),
          ),
          Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Material(
              color: Colors.transparent,
              child: Column(children: rows),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Text(
                footer!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  const _RowIcon(this.icon, {this.enabled = true});

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      color: enabled
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppRadius.sm),
    ),
    child: Icon(
      icon,
      size: 16,
      color: enabled
          ? AppColors.primary
          : Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? description;
  final bool value;
  final bool enabled;
  final bool busy;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.label,
    this.description,
    required this.value,
    this.enabled = true,
    this.busy = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return MergeSemantics(
      child: InkWell(
        onTap: enabled && !busy ? () => onChanged(!value) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              _RowIcon(icon, enabled: enabled),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    if (description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          description!,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: AppLoader(size: 20),
                )
              else
                Switch(
                  value: value && enabled,
                  onChanged: enabled ? onChanged : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback? onTap;
  const _NavRow({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 13, 12, 13),
        child: Row(
          children: [
            _RowIcon(icon),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurface,
                ),
              ),
            ),
            if (trailing != null)
              Flexible(
                child: Text(
                  trailing!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Label + compact segmented choice (Theme, Text size).
class _ChoiceRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  const _ChoiceRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          _RowIcon(icon),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.sm + 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in options.entries)
                  Semantics(
                    button: true,
                    selected: e.key == value,
                    child: GestureDetector(
                      onTap: () => onChanged(e.key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: e.key == value
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          e.value,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: e.key == value
                                ? Colors.white
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
