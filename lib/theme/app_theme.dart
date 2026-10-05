import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Vaulty design tokens ("Editorial Vault", see DESIGN.md).
///
/// Paper + ink carry the interface; violet is reserved for brand moments and
/// lime is a tiny, sharp accent. Status colours are only used for countdowns.
@immutable
class VaultyColors extends ThemeExtension<VaultyColors> {
  const VaultyColors({
    required this.bg,
    required this.surface,
    required this.sunken,
    required this.line,
    required this.ink,
    required this.inkSoft,
    required this.inkFaint,
    required this.onInk,
    required this.brand,
    required this.brandSoft,
    required this.acid,
    required this.danger,
    required this.dangerSoft,
    required this.warn,
    required this.warnSoft,
    required this.ok,
    required this.okSoft,
    required this.ochre,
    required this.rose,
    required this.teal,
    required this.slate,
    required this.mascot,
    required this.mascotShade,
  });

  /// Page background ("paper").
  final Color bg;

  /// Raised surfaces: sheets, cards, inputs.
  final Color surface;

  /// Recessed fills: segmented controls, chips, skeletons.
  final Color sunken;

  /// Hairline separators and outlines.
  final Color line;

  /// Primary text and the dominant UI colour (nav capsule, primary buttons).
  final Color ink;
  final Color inkSoft;
  final Color inkFaint;

  /// Text/icons placed on [ink].
  final Color onInk;

  /// Vault violet: brand moments, links, selection.
  final Color brand;
  final Color brandSoft;

  /// Lime: the one loud accent. Active dots, streaks, "new". Tiny doses.
  final Color acid;

  final Color danger;
  final Color dangerSoft;
  final Color warn;
  final Color warnSoft;
  final Color ok;
  final Color okSoft;

  /// Category hues (used as glyph + small dot colour, never as big fills).
  final Color ochre;
  final Color rose;
  final Color teal;
  final Color slate;

  final Color mascot;
  final Color mascotShade;

  // Text tokens (ink, inkSoft, inkFaint, status and category colours) are
  // tuned to at least 4.5:1 on bg, surface and sunken, and status colours on
  // their soft fills (WCAG AA). Check again when changing any of them.
  static const light = VaultyColors(
    bg: Color(0xFFF6F4EF),
    surface: Color(0xFFFFFFFF),
    sunken: Color(0xFFEFECE5),
    line: Color(0xFFE4E0D8),
    ink: Color(0xFF151419),
    inkSoft: Color(0xFF54525A),
    inkFaint: Color(0xFF6D6974),
    onInk: Color(0xFFF6F4EF),
    brand: Color(0xFF5B44F2),
    brandSoft: Color(0xFFEBE8FF),
    acid: Color(0xFFD4F54A),
    danger: Color(0xFFCC2933),
    dangerSoft: Color(0xFFFBE9E9),
    warn: Color(0xFF985D0E),
    warnSoft: Color(0xFFFAF0DE),
    ok: Color(0xFF277953),
    okSoft: Color(0xFFE3F3EA),
    ochre: Color(0xFF926016),
    rose: Color(0xFFC0345B),
    teal: Color(0xFF18776F),
    slate: Color(0xFF5A6273),
    mascot: Color(0xFF9D89FF),
    mascotShade: Color(0xFF7760F2),
  );

  static const dark = VaultyColors(
    bg: Color(0xFF0D0D0F),
    surface: Color(0xFF17171B),
    sunken: Color(0xFF202026),
    line: Color(0xFF2A2A31),
    ink: Color(0xFFF3F1EC),
    inkSoft: Color(0xFFB4B1BA),
    inkFaint: Color(0xFF8A8690),
    onInk: Color(0xFF111114),
    brand: Color(0xFF9788FF),
    brandSoft: Color(0xFF231F3F),
    acid: Color(0xFFD4F54A),
    danger: Color(0xFFFF6369),
    dangerSoft: Color(0xFF34181B),
    warn: Color(0xFFF2A93B),
    warnSoft: Color(0xFF33260F),
    ok: Color(0xFF4CC38A),
    okSoft: Color(0xFF12291E),
    ochre: Color(0xFFE0A54A),
    rose: Color(0xFFF07397),
    teal: Color(0xFF45C2B6),
    slate: Color(0xFF9AA3B5),
    mascot: Color(0xFF9D89FF),
    mascotShade: Color(0xFF7760F2),
  );

  @override
  VaultyColors copyWith() => this;

  @override
  VaultyColors lerp(ThemeExtension<VaultyColors>? other, double t) {
    if (other is! VaultyColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return VaultyColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      sunken: l(sunken, other.sunken),
      line: l(line, other.line),
      ink: l(ink, other.ink),
      inkSoft: l(inkSoft, other.inkSoft),
      inkFaint: l(inkFaint, other.inkFaint),
      onInk: l(onInk, other.onInk),
      brand: l(brand, other.brand),
      brandSoft: l(brandSoft, other.brandSoft),
      acid: l(acid, other.acid),
      danger: l(danger, other.danger),
      dangerSoft: l(dangerSoft, other.dangerSoft),
      warn: l(warn, other.warn),
      warnSoft: l(warnSoft, other.warnSoft),
      ok: l(ok, other.ok),
      okSoft: l(okSoft, other.okSoft),
      ochre: l(ochre, other.ochre),
      rose: l(rose, other.rose),
      teal: l(teal, other.teal),
      slate: l(slate, other.slate),
      mascot: l(mascot, other.mascot),
      mascotShade: l(mascotShade, other.mascotShade),
    );
  }
}

const _serif = 'InstrumentSerif';
const _sans = 'InstrumentSans';
const _mono = 'DMMono';

/// The type scale. Three families, each with one job:
/// serif = display & big numerals, sans = everything you read/tap,
/// mono = data you'd copy (codes, sizes, prices).
class VType {
  const VType(this.c);
  final VaultyColors c;

  /// Screen hero lines ("Good morning, Sam").
  TextStyle get display => TextStyle(fontFamily: _serif, fontSize: 40, height: 1.02, letterSpacing: -0.6, color: c.ink);

  /// Detail titles, sheet titles.
  TextStyle get headline =>
      TextStyle(fontFamily: _serif, fontSize: 30, height: 1.08, letterSpacing: -0.3, color: c.ink);

  /// Countdown numerals.
  TextStyle numeral(double size, [Color? color]) =>
      TextStyle(fontFamily: _serif, fontSize: size, height: .9, letterSpacing: -1, color: color ?? c.ink);

  /// Italic serif for a single emphasised word inside a headline.
  TextStyle get accent => TextStyle(fontFamily: _serif, fontStyle: FontStyle.italic, color: c.brand);

  /// Section titles.
  TextStyle get title => TextStyle(
    fontFamily: _sans,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.25,
    letterSpacing: -.2,
    color: c.ink,
  );

  /// Row / card titles.
  TextStyle get item => TextStyle(
    fontFamily: _sans,
    fontSize: 15.5,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -.1,
    color: c.ink,
  );

  TextStyle get body => TextStyle(fontFamily: _sans, fontSize: 15, height: 1.45, color: c.ink);
  TextStyle get bodySoft => TextStyle(fontFamily: _sans, fontSize: 14.5, height: 1.45, color: c.inkSoft);
  TextStyle get caption => TextStyle(fontFamily: _sans, fontSize: 12.5, height: 1.35, color: c.inkSoft);

  /// Small caps label above content ("POLICY NUMBER", "THIS WEEK").
  TextStyle get eyebrow => TextStyle(
    fontFamily: _sans,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.2,
    height: 1.2,
    color: c.inkFaint,
  );

  TextStyle get button =>
      const TextStyle(fontFamily: _sans, fontSize: 15.5, fontWeight: FontWeight.w600, letterSpacing: -.1);

  /// Copyable data.
  TextStyle mono([double size = 15, Color? color]) =>
      TextStyle(fontFamily: _mono, fontSize: size, fontWeight: FontWeight.w500, height: 1.2, color: color ?? c.ink);
}

extension VaultyThemeX on BuildContext {
  VaultyColors get vc => Theme.of(this).extension<VaultyColors>()!;
  VType get type => VType(vc);
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  /// True on iOS, where system pieces (dialogs, pickers, menus, sheets) take
  /// the platform's own form. The brand layer looks the same everywhere.
  bool get isCupertino => Theme.of(this).platform == TargetPlatform.iOS;
}

/// Spacing & radius scale. Stick to these.
class Space {
  static const xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 24.0, xxl = 32.0, page = 20.0;
}

class Radii {
  static const s = 10.0, m = 14.0, l = 20.0, xl = 28.0;
}

class AppTheme {
  static ThemeData build(Brightness brightness) {
    final c = brightness == Brightness.dark ? VaultyColors.dark : VaultyColors.light;
    final t = VType(c);
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final scheme = ColorScheme.fromSeed(
      seedColor: c.brand,
      brightness: brightness,
      primary: c.brand,
      onPrimary: Colors.white,
      surface: c.surface,
      onSurface: c.ink,
      error: c.danger,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: _sans,
      scaffoldBackgroundColor: c.bg,
      splashFactory: NoSplash.splashFactory,
      highlightColor: c.ink.withValues(alpha: .04),
      dividerColor: c.line,
      extensions: [c],
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink, fontFamily: _sans),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.brand,
        selectionColor: c.brand.withValues(alpha: .25),
        selectionHandleColor: c.brand,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        foregroundColor: c.ink,
        titleTextStyle: t.item,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        hintStyle: t.body.copyWith(color: c.inkFaint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.m),
          borderSide: BorderSide(color: c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.m),
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.m),
          borderSide: BorderSide(color: c.ink, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.ink,
        elevation: 0,
        contentTextStyle: t.item.copyWith(color: c.onInk, fontSize: 14.5),
        actionTextColor: c.acid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.l)),
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 104),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.bg,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        // iOS: the system grabber (tertiary label, 36x5) and its lighter dim.
        dragHandleColor: !ios
            ? c.line
            : (brightness == Brightness.dark ? const Color(0x4DEBEBF5) : const Color(0x4D3C3C43)),
        dragHandleSize: Size(36, ios ? 5 : 4),
        modalBarrierColor: !ios
            ? null
            : (brightness == Brightness.dark ? const Color(0x7A000000) : const Color(0x33000000)),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: t.headline.copyWith(fontSize: 26),
        contentTextStyle: t.bodySoft,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.ink : c.line),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: c.ink,
        headerForegroundColor: c.onInk,
        dayStyle: t.body,
        todayBorder: BorderSide(color: c.brand),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xl)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: t.body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.l),
          side: BorderSide(color: c.line),
        ),
        elevation: 0,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.ink, linearTrackColor: c.sunken),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
