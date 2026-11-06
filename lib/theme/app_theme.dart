import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// MCRI design tokens — orange, black and white.
///
/// Visual language: clean white surfaces, hairline grey borders, 12px radius
/// cards, bold black headings, small uppercase orange "eyebrow" labels and a
/// single orange primary action per screen. Selected cards get an orange
/// border + faint orange tint.
class AppColors {
  AppColors._();

  // Brand
  static const primary = Color(0xFFF97316); // orange 500
  static const primaryDark = Color(0xFFEA580C); // orange 600 (pressed)
  static const primaryDeep = Color(0xFF9A3412); // orange 800 (text on tint)
  static const primarySoft = Color(0xFFFFF4EC); // selected-card tint
  static const primaryBorder = Color(0xFFFDBA74); // orange 300

  // Neutrals
  static const ink = Color(0xFF0A0A0A); // headings / black
  static const text = Color(0xFF1F2937);
  static const muted = Color(0xFF6B7280);
  static const subtle = Color(0xFF9CA3AF);
  static const border = Color(
    0xFFDCDFE4,
  ); // visible hairline on white AND canvas
  static const divider = Color(0xFFF0F0F0);
  static const canvas = Color(0xFFF7F7F8); // page background
  static const surface = Colors.white;
  static const fieldDisabled = Color(0xFFF3F4F6);

  // Dark mode neutrals
  static const darkCanvas = Color(0xFF0B0B0C);
  static const darkSurface = Color(0xFF161618);
  static const darkSurfaceHigh = Color(0xFF1F1F22);
  static const darkBorder = Color(0xFF3A3A40);

  // Semantic
  static const danger = Color(0xFFEF4444);
  static const dangerDark = Color(0xFFDC2626);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFD97706);
}

class AppRadius {
  AppRadius._();
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;
}

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Standard horizontal page gutter.
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: 20);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final canvas = dark ? AppColors.darkCanvas : AppColors.canvas;
    final surface = dark ? AppColors.darkSurface : AppColors.surface;
    final border = dark ? AppColors.darkBorder : AppColors.border;
    final onSurface = dark ? Colors.white : AppColors.ink;
    final muted = dark ? const Color(0xFFA1A1AA) : AppColors.muted;

    final scheme = ColorScheme(
      brightness: b,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      primaryContainer: dark ? const Color(0xFF3A1D0A) : AppColors.primarySoft,
      onPrimaryContainer: dark
          ? AppColors.primaryBorder
          : AppColors.primaryDeep,
      secondary: dark ? Colors.white : AppColors.ink,
      onSecondary: dark ? AppColors.ink : Colors.white,
      secondaryContainer: dark
          ? AppColors.darkSurfaceHigh
          : AppColors.fieldDisabled,
      onSecondaryContainer: onSurface,
      tertiary: AppColors.primaryDark,
      onTertiary: Colors.white,
      error: AppColors.dangerDark,
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: muted,
      surfaceContainerLowest: surface,
      surfaceContainerLow: dark
          ? AppColors.darkSurface
          : const Color(0xFFFAFAFA),
      surfaceContainer: dark
          ? AppColors.darkSurfaceHigh
          : const Color(0xFFF5F5F5),
      surfaceContainerHigh: dark
          ? AppColors.darkSurfaceHigh
          : const Color(0xFFF0F0F0),
      surfaceContainerHighest: dark
          ? const Color(0xFF26262A)
          : const Color(0xFFEBEBEB),
      outline: dark ? const Color(0xFF5B5B63) : const Color(0xFF9CA3AF),
      outlineVariant: border,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: dark ? Colors.white : AppColors.ink,
      onInverseSurface: dark ? AppColors.ink : Colors.white,
      inversePrimary: AppColors.primaryBorder,
      surfaceTint: Colors.transparent,
    );

    final radiusMd = BorderRadius.circular(AppRadius.md);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: b,
    );

    final textTheme = base.textTheme
        .apply(bodyColor: onSurface, displayColor: onSurface)
        .copyWith(
          headlineLarge: base.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: onSurface,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: onSurface,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: onSurface,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: onSurface,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            color: onSurface,
            height: 1.45,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            color: muted,
            height: 1.4,
          ),
          labelSmall: base.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        );

    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm + 2),
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);
    const buttonText = TextStyle(fontWeight: FontWeight.w600, fontSize: 15);

    return base.copyWith(
      scaffoldBackgroundColor: canvas,
      canvasColor: canvas,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: border)),
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        systemOverlayStyle: dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: radiusMd,
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white,
          padding: buttonPadding,
          minimumSize: const Size(64, 48),
          shape: buttonShape,
          textStyle: buttonText,
          elevation: 0,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: buttonPadding,
          minimumSize: const Size(64, 48),
          shape: buttonShape,
          textStyle: buttonText,
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.7)),
          padding: buttonPadding,
          minimumSize: const Size(64, 48),
          shape: buttonShape,
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: onSurface),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: AppColors.subtle, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
          borderSide: const BorderSide(color: AppColors.dangerDark),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.primary.withValues(alpha: 0.25),
        selectionHandleColor: AppColors.primary,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),
      // Every state spelled out: ON = white knob on an orange track (the
      // knob must never be orange too, or the switch reads as one blob);
      // OFF = grey knob on a light track with a clearly visible outline.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) {
            return dark ? const Color(0xFF52525B) : const Color(0xFFD4D4D8);
          }
          if (s.contains(WidgetState.selected)) return Colors.white;
          return dark ? const Color(0xFFA1A1AA) : const Color(0xFF71717A);
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) {
            return s.contains(WidgetState.disabled)
                ? AppColors.primary.withValues(alpha: 0.35)
                : AppColors.primary;
          }
          return dark ? AppColors.darkSurfaceHigh : const Color(0xFFF1F1F3);
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return Colors.transparent;
          return dark ? const Color(0xFF52525B) : const Color(0xFFA1A1AA);
        }),
        trackOutlineWidth: const WidgetStatePropertyAll(1.5),
        thumbIcon: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? const Icon(
                  Icons.check_rounded,
                  size: 14,
                  color: AppColors.primary,
                )
              : null,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primary : null,
        ),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: BorderSide(color: scheme.outline, width: 1.6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : scheme.outline,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: scheme.primaryContainer,
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        labelStyle: TextStyle(
          color: onSurface,
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        checkmarkColor: AppColors.primary,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: muted,
        indicatorColor: AppColors.primary,
        dividerColor: border,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        indicatorSize: TabBarIndicatorSize.label,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(borderRadius: radiusMd),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? Colors.white : AppColors.ink,
        contentTextStyle: TextStyle(
          color: dark ? AppColors.ink : Colors.white,
          fontWeight: FontWeight.w500,
        ),
        actionTextColor: AppColors.primary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm + 2),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radiusMd,
          side: BorderSide(color: border),
        ),
      ),
      badgeTheme: const BadgeThemeData(backgroundColor: AppColors.danger),
    );
  }
}
