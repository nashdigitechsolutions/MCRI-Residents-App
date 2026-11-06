import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../navigation/destinations.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// "All services" hub, laid out like the reference onboarding screen:
/// eyebrow → bold question-style heading → muted caption → card grid.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.select<AuthProvider, bool>((a) => a.isAdmin);
    final q = _query.trim().toLowerCase();
    final items = destinationsFor(isAdmin: isAdmin)
        .where(
          (d) =>
              q.isEmpty ||
              d.label.toLowerCase().contains(q) ||
              d.caption.toLowerCase().contains(q),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('All services')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            const PageHeading(
              eyebrow: 'Resident services',
              title: 'What would you like to do today?',
              subtitle: 'Everything in your residence, one tap away.',
            ),
            const SizedBox(height: AppSpacing.xl),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search services',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            SectionHeader(
              isAdmin ? 'Resident & admin tools' : 'Resident tools',
            ),
            if (items.isEmpty)
              const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No matching services',
                message: 'Try a different word.',
              )
            else
              OptionGrid(
                children: [
                  for (final d in items)
                    OptionCard(
                      icon: d.icon,
                      title: d.label,
                      subtitle: d.caption,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          settings: RouteSettings(name: d.routeName),
                          builder: (_) => d.builder(),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
