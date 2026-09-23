import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import 'mascot.dart';

/// True once the launch intro has finished (the lock screen waits for it
/// before raising the biometric prompt).
final splashDoneProvider = NotifierProvider<SplashDone, bool>(SplashDone.new);

class SplashDone extends Notifier<bool> {
  @override
  bool build() => false;

  void finish() => state = true;
}

/// Picks up exactly where the native splash leaves off (same Vo, same size,
/// same centre, same background) and animates into the app: Vo hops and
/// winks, the wordmark rises in, the lime dot pops, then everything fades.
class SplashIntro extends StatefulWidget {
  const SplashIntro({super.key, required this.onDone});

  /// Must match the Vo size baked into assets/splash/splash_vo.png.
  static const mascotSize = 176.0;

  final VoidCallback onDone;

  @override
  State<SplashIntro> createState() => _SplashIntroState();
}

class _SplashIntroState extends State<SplashIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
  bool _done = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      // Respect "reduce motion": no intro at all.
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    } else {
      _c.forward();
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    widget.onDone();
  }

  void _skip() {
    if (_c.value < .78) _c.animateTo(1, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _span(double t, double from, double to, [Curve curve = Curves.linear]) =>
      curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    // Follow the *system* brightness: that's what the native splash used.
    final brightness = MediaQuery.platformBrightnessOf(context);
    final theme = AppTheme.build(brightness);
    final c = brightness == Brightness.dark ? VaultyColors.dark : VaultyColors.light;
    final type = VType(c);

    return Theme(
      data: theme,
      child: GestureDetector(
        onTap: _skip,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            // Vo: a squash-and-hop, then rises to make room for the wordmark.
            final squash = t < .22 ? 1 - .07 * _span(t, .08, .22, Curves.easeOut) : 1.0;
            final hop = t >= .22 ? 1.0 + .05 * (1 - _span(t, .22, .46, Curves.easeOutBack)) * _span(t, .22, .3) : 1.0;
            final rise = -58 * _span(t, .2, .5, Curves.easeOutCubic);
            final mood = t < .34 ? MascotMood.happy : (t < .62 ? MascotMood.wink : MascotMood.grin);
            // Wordmark and tagline.
            final wordIn = _span(t, .32, .56, Curves.easeOutCubic);
            final dotPop = _span(t, .5, .7, Curves.elasticOut);
            final tagIn = _span(t, .46, .66, Curves.easeOut);
            // Exit: fade + slight zoom so the app feels like it's behind.
            final exit = _span(t, .8, 1, Curves.easeInOutCubic);

            return Opacity(
              opacity: 1 - exit,
              child: Transform.scale(
                scale: 1 + .04 * exit,
                // Material supplies default text styling: this overlay sits
                // above the Navigator, where no Scaffold provides it.
                child: Material(
                  color: c.bg,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.translate(
                        offset: Offset(0, rise),
                        child: Transform.scale(
                          scaleX: 2 - squash * hop,
                          scaleY: squash * hop,
                          alignment: Alignment.bottomCenter,
                          child: Mascot(size: SplashIntro.mascotSize, mood: mood),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(0, 86 + 14 * (1 - wordIn)),
                        child: Opacity(
                          opacity: wordIn,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'vaulty',
                                    style: TextStyle(
                                      fontFamily: 'InstrumentSerif',
                                      fontStyle: FontStyle.italic,
                                      fontSize: 46,
                                      height: 1,
                                      color: c.ink,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 3, bottom: 7),
                                    child: Transform.scale(
                                      scale: dotPop,
                                      child: Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: c.acid,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: c.ink, width: 1.4),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Opacity(
                                opacity: tagIn,
                                child: Text(
                                  'your second brain, locked tight.',
                                  style: type.caption.copyWith(fontSize: 13.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
