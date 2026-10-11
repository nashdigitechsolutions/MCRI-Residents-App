import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/device_registration_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _update(
    BuildContext context,
    Preferences Function(Preferences) updater,
  ) async {
    final settings = context.read<SettingsProvider>();
    final ok = await settings.update(updater);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not save that change — please try again'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final prefs = settings.prefs;

    return Scaffold(
      body: !settings.loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                const SizedBox(height: 20),
                _buildSection(
                  context: context,
                  title: 'Notifications',
                  children: [
                    _SwitchRow(
                      icon: Icons.notifications_outlined,
                      label: 'Push notifications',
                      description: 'All in-app alerts',
                      value: prefs.notificationsEnabled,
                      onChanged: (v) {
                        _update(
                          context,
                          (p) => p.copyWith(notificationsEnabled: v),
                        );
                        if (v) {
                          DeviceRegistrationService.registerWhenReady();
                        } else {
                          DeviceRegistrationService.unregister();
                        }
                      },
                    ),
                    _SwitchRow(
                      icon: Icons.chat_bubble_outline,
                      label: 'Chat messages',
                      description: 'Show the unread badge for new messages',
                      value: prefs.chatNotifications,
                      onChanged: (v) => _update(
                        context,
                        (p) => p.copyWith(chatNotifications: v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSection(
                  context: context,
                  title: 'Privacy',
                  children: [
                    _SwitchRow(
                      icon: Icons.shield_outlined,
                      label: 'Show availability status',
                      description:
                          "Let others see when you're around the house",
                      value: prefs.showOnlineStatus,
                      onChanged: (v) => _update(
                        context,
                        (p) => p.copyWith(showOnlineStatus: v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSection(
                  context: context,
                  title: 'Appearance',
                  children: [
                    _ThemeRow(
                      value: prefs.theme,
                      onChanged: (v) =>
                          _update(context, (p) => p.copyWith(theme: v)),
                    ),
                    Divider(
                      height: 1,
                      indent: 48,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                    _SwitchRow(
                      icon: Icons.view_agenda_outlined,
                      label: 'Compact lists',
                      description: 'Tighter spacing in long lists',
                      value: prefs.compactLists,
                      onChanged: (v) =>
                          _update(context, (p) => p.copyWith(compactLists: v)),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => context.read<AuthProvider>().logout(),
                    icon: const Icon(
                      Icons.logout,
                      color: Color(0xFFDC2626),
                      size: 18,
                    ),
                    label: const Text(
                      'Log out',
                      style: TextStyle(color: Color(0xFFDC2626)),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFECACA)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _buildFooter(context),
              ],
            ),
    );
  }

  Widget _buildSection({
    required BuildContext context,
    required String title,
    required List<Widget> children,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: colors.onSurfaceVariant,
              letterSpacing: 0.4,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(
            color: colors.surface,
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Container(
          height: 1,
          color: colors.outlineVariant,
          margin: const EdgeInsets.symmetric(horizontal: 40),
        ),
        const SizedBox(height: 16),
        Text(
          'MCRI Residents',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Version 1.0.0',
          style: TextStyle(
            fontSize: 11,
            color: colors.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurface,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    description!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF3355FF),
          ),
        ],
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _ThemeRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            Icons.dark_mode_outlined,
            size: 18,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Theme',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.onSurface,
              ),
            ),
          ),
          _ThemeChip(
            label: 'Light',
            selected: value == 'light',
            onTap: () => onChanged('light'),
          ),
          const SizedBox(width: 6),
          _ThemeChip(
            label: 'Dark',
            selected: value == 'dark',
            onTap: () => onChanged('dark'),
          ),
          const SizedBox(width: 6),
          _ThemeChip(
            label: 'System',
            selected: value == 'system',
            onTap: () => onChanged('system'),
          ),
        ],
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.onSurface : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? colors.surface : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
