import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// WiFi payments — "coming soon" preview (UI only, no payments are taken).
///
/// Shows what the feature will do and lets residents ask to be told when it
/// launches; that choice is kept on this device only.
class WifiPaymentsScreen extends StatefulWidget {
  const WifiPaymentsScreen({super.key});

  static const notifyKey = 'wifi_payments_notify_v1';

  @override
  State<WifiPaymentsScreen> createState() => _WifiPaymentsScreenState();
}

class _WifiPaymentsScreenState extends State<WifiPaymentsScreen>
    with SingleTickerProviderStateMixin {
  bool _notify = false;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void initState() {
    super.initState();
    StorageService.getItem(WifiPaymentsScreen.notifyKey)
        .then((v) {
          if (mounted) setState(() => _notify = v == '1');
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _toggleNotify() async {
    final next = !_notify;
    setState(() => _notify = next);
    try {
      if (next) {
        await StorageService.setItem(WifiPaymentsScreen.notifyKey, '1');
      } else {
        await StorageService.removeItem(WifiPaymentsScreen.notifyKey);
      }
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          next
              ? 'Got it — we\'ll let you know when WiFi payments go live.'
              : 'Okay, no launch reminder.',
        ),
      ),
    );
  }

  void _comingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('WiFi payments aren\'t live yet — coming soon!'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('WiFi payments')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Hero with animated signal rings.
          Container(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.ink,
                  Color(0xFF2A160B),
                  AppColors.primaryDeep,
                ],
              ),
            ),
            child: Column(
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => CustomPaint(
                      painter: _RingsPainter(
                        reduceMotion ? 0.35 : _pulse.value,
                      ),
                      child: const Center(
                        child: CircleAvatar(
                          radius: 30,
                          backgroundColor: AppColors.primary,
                          child: Icon(
                            Icons.wifi_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Text(
                    'COMING SOON',
                    style: TextStyle(
                      color: AppColors.primaryBorder,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Pay for WiFi right here',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Buy a bundle, get connected in seconds and keep an eye on your data, without chasing anyone for a voucher.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 13.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          const SectionHeader('What you\'ll be able to do'),
          for (final (icon, title, body) in const [
            (
              Icons.flash_on_rounded,
              'Instant access',
              'Pay and you\'re online straight away. No paper vouchers.',
            ),
            (
              Icons.account_balance_wallet_outlined,
              'Pay your way',
              'Mobile money or card, all from your phone.',
            ),
            (
              Icons.data_usage_rounded,
              'Track your usage',
              'See what you\'ve used and when your bundle runs out.',
            ),
            (
              Icons.receipt_long_outlined,
              'Receipts & history',
              'Every payment saved in the app.',
            ),
            (
              Icons.notifications_active_outlined,
              'Expiry reminders',
              'A heads-up before your WiFi runs out.',
            ),
          ])
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                    ),
                    child: Icon(icon, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          body,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),

          const SectionHeader('Bundles (preview)'),
          Text(
            'Bundles and prices will be confirmed by the lodge manager at launch.',
            style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final (i, (name, icon)) in const [
                ('Daily', Icons.today_outlined),
                ('Weekly', Icons.date_range_outlined),
                ('Monthly', Icons.calendar_month_outlined),
              ].indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Opacity(
                    opacity: 0.75,
                    child: Material(
                      color: colors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        side: BorderSide(
                          color: i == 1
                              ? AppColors.primary
                              : colors.outlineVariant,
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        onTap: _comingSoon,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 14,
                            horizontal: 8,
                          ),
                          child: Column(
                            children: [
                              Icon(icon, color: AppColors.primary),
                              const SizedBox(height: 6),
                              Text(
                                name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: colors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Price TBC',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 15,
                                color: colors.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 22),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: _notify
                ? OutlinedButton.icon(
                    onPressed: _toggleNotify,
                    icon: const Icon(Icons.notifications_active_rounded),
                    label: const Text('We\'ll notify you at launch'),
                  )
                : FilledButton.icon(
                    onPressed: _toggleNotify,
                    icon: const Icon(Icons.notifications_none_rounded),
                    label: const Text('Notify me when it\'s live'),
                  ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              'No payments are taken in this preview.',
              style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Expanding "signal" rings behind the WiFi icon.
class _RingsPainter extends CustomPainter {
  final double t;
  _RingsPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final maxR = math.min(size.width, size.height) / 2;
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final r = 30 + (maxR - 30) * p;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.primary.withValues(alpha: (1 - p) * 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t;
}

/// Home-screen banner that leads to the preview.
class WifiPromoCard extends StatelessWidget {
  const WifiPromoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const WifiPaymentsScreen())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryDeep],
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                ),
                child: const Icon(Icons.wifi_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'WiFi payments',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: const Text(
                            'SOON',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Buy WiFi bundles in the app, coming soon',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
