import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// First-run walkthrough: four swipeable pages that explain what the app
/// does. Shown once before the first sign-in, and again from Settings →
/// "App tour".
class OnboardingTutorialScreen extends StatefulWidget {
  /// Called when the tour is finished or skipped. When null (opened from
  /// Settings) the screen simply pops.
  final VoidCallback? onDone;
  const OnboardingTutorialScreen({super.key, this.onDone});

  static const seenKey = 'onboarding_seen_v1';

  static Future<bool> hasBeenSeen() async =>
      (await StorageService.getItem(seenKey)) == '1';

  static Future<void> markSeen() => StorageService.setItem(seenKey, '1');

  @override
  State<OnboardingTutorialScreen> createState() =>
      _OnboardingTutorialScreenState();
}

class _TourPage {
  final IconData icon;
  final List<IconData> orbit;
  final String eyebrow;
  final String title;
  final String body;
  final List<String> tips;
  const _TourPage(
    this.icon,
    this.orbit,
    this.eyebrow,
    this.title,
    this.body,
    this.tips,
  );
}

const _pages = [
  _TourPage(
    Icons.home_work_rounded,
    [Icons.campaign_outlined, Icons.event_outlined, Icons.poll_outlined],
    'Welcome',
    'Your residence, in your pocket',
    'Announcements, events and polls from the lodge, all in one place.',
    [
      'Pull down on any list to refresh',
      'Tap a notification to jump straight to it',
    ],
  ),
  _TourPage(
    Icons.forum_rounded,
    [Icons.done_all_rounded, Icons.reply_rounded, Icons.link_rounded],
    'Chats',
    'Talk to residents and staff',
    'Group and private chats that update live, with read ticks, replies and forwarding.',
    [
      'Long-press a message to copy, reply or forward',
      'Two orange ticks = everyone has read it',
    ],
  ),
  _TourPage(
    Icons.assignment_turned_in_rounded,
    [
      Icons.restaurant_menu_rounded,
      Icons.cleaning_services_outlined,
      Icons.schedule_rounded,
    ],
    'Daily life',
    'Duties and the weekly menu',
    'See your duties, mark them done, and check what\'s cooking today.',
    [
      '"Up next" on the menu shows the coming meal',
      'Share a day\'s menu to WhatsApp',
    ],
  ),
  _TourPage(
    Icons.build_circle_rounded,
    [
      Icons.shopping_cart_outlined,
      Icons.report_problem_outlined,
      Icons.handyman_outlined,
    ],
    'Equipment',
    'Ask for it, or report it broken',
    'Request equipment and the lodge manager buys it. Report faults and maintenance fixes them. You\'re notified at every step.',
    [
      'Anyone can add an item to the list',
      'Track every request from "pending" to "bought"',
    ],
  ),
];

class _OnboardingTutorialScreenState extends State<OnboardingTutorialScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await OnboardingTutorialScreen.markSeen();
    if (!mounted) return;
    if (widget.onDone != null) {
      widget.onDone!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _next() {
    if (_index == _pages.length - 1) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final last = _index == _pages.length - 1;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Text(
                    '${_index + 1} / ${_pages.length}',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: last ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: TextButton(
                      onPressed: last ? null : _finish,
                      child: const Text('Skip'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _PageBody(
                  page: _pages[i],
                  controller: _controller,
                  index: i,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < _pages.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: i == _index ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _index
                                ? AppColors.primary
                                : colors.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton(
                      onPressed: _next,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          last ? 'Get started' : 'Next',
                          key: ValueKey(last),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5,
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
      ),
    );
  }
}

class _PageBody extends StatelessWidget {
  final _TourPage page;
  final PageController controller;
  final int index;
  const _PageBody({
    required this.page,
    required this.controller,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final art = (c.maxHeight * 0.42).clamp(150.0, 260.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Parallax: the art drifts slightly slower than the swipe.
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, child) {
                    final page =
                        controller.hasClients &&
                            controller.position.haveDimensions
                        ? controller.page ?? index.toDouble()
                        : index.toDouble();
                    final delta = (page - index).clamp(-1.0, 1.0);
                    return Transform.translate(
                      offset: Offset(delta * 60, 0),
                      child: Opacity(
                        opacity: (1 - delta.abs()).clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: _Illustration(page: page, size: art),
                ),
                const SizedBox(height: 28),
                Text(
                  page.eyebrow.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  page.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    color: colors.onSurface,
                    letterSpacing: -0.5,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  page.body,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                for (final tip in page.tips)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 17,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tip,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Layered rings with the page icon in the middle and three small icons
/// orbiting it.
class _Illustration extends StatelessWidget {
  final _TourPage page;
  final double size;
  const _Illustration({required this.page, required this.size});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final positions = [
      const Alignment(-0.92, -0.35),
      const Alignment(0.9, -0.7),
      const Alignment(0.72, 0.88),
    ];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.07),
            ),
          ),
          FractionallySizedBox(
            widthFactor: 0.72,
            heightFactor: 0.72,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.12),
              ),
            ),
          ),
          FractionallySizedBox(
            widthFactor: 0.46,
            heightFactor: 0.46,
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryDeep],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x55F97316),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: FittedBox(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Icon(page.icon, color: Colors.white),
                ),
              ),
            ),
          ),
          for (var i = 0; i < page.orbit.length; i++)
            Align(
              alignment: positions[i],
              child: Container(
                width: size * 0.2,
                height: size * 0.2,
                decoration: BoxDecoration(
                  color: colors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  page.orbit[i],
                  color: AppColors.primary,
                  size: size * 0.09,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
