import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Staggered fade + slide entrance for cards and panels.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offsetY;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 450),
    this.offsetY = 24,
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _opacity =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: Offset(0, widget.offsetY),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (_, child) => Opacity(
        opacity: _opacity.value,
        child: Transform.translate(offset: _slide.value, child: child),
      ),
    );
  }
}

/// Subtle hover lift + scale for interactive cards.
class HoverLift extends StatefulWidget {
  final Widget child;
  final double scale;
  final double lift;

  const HoverLift({
    super.key,
    required this.child,
    this.scale = 1.02,
    this.lift = -0.02,
  });

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: AnimatedSlide(
          offset: _hovered ? Offset(0, widget.lift) : Offset.zero,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Counts up to a numeric value on first build.
class AnimatedCounter extends StatelessWidget {
  final String value;
  final TextStyle style;
  final Duration duration;

  const AnimatedCounter({
    super.key,
    required this.value,
    required this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    final num? target = num.tryParse(value);
    if (target == null) return Text(value, style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(v.toInt().toString(), style: style),
    );
  }
}

/// Fade + slide transition for switching between portal views.
class AppPageTransition extends StatelessWidget {
  final Widget child;
  final String viewKey;

  const AppPageTransition({
    super.key,
    required this.child,
    required this.viewKey,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 340),
      reverseDuration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.018),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: KeyedSubtree(key: ValueKey(viewKey), child: child),
    );
  }
}

/// Slow, softly drifting brand-colored orbs behind page content.
class AmbientBackdrop extends StatefulWidget {
  const AmbientBackdrop({super.key});

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 26),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _orb(double size, Color color) {
    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(0.06), color.withOpacity(0)],
          ),
        ),
      ),
    );
  }

  late final Widget _blueOrb = _orb(440, const Color(0xFF2563EB));
  late final Widget _goldOrb = _orb(380, const Color(0xFFD4AF37));
  late final Widget _indigoOrb = _orb(320, const Color(0xFF4F46E5));

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          final t = _controller.value * 2 * math.pi;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: -150,
                right: -110,
                child: Transform.translate(
                  offset: Offset(math.sin(t) * 70, math.cos(t * 0.8) * 44),
                  child: _blueOrb,
                ),
              ),
              Positioned(
                bottom: -170,
                left: -90,
                child: Transform.translate(
                  offset: Offset(math.cos(t * 0.7) * 80, math.sin(t) * 48),
                  child: _goldOrb,
                ),
              ),
              Positioned(
                top: 240,
                right: 260,
                child: Transform.translate(
                  offset:
                      Offset(math.sin(t * 1.1) * 60, math.cos(t * 1.2) * 70),
                  child: _indigoOrb,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Small status dot with an expanding, fading halo.
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final double growth;
  final double ringOpacity;
  final Duration period;

  const PulseDot({
    super.key,
    this.color = const Color(0xFF10B981),
    this.size = 7,
    this.growth = 1.6,
    this.ringOpacity = 0.45,
    this.period = const Duration(milliseconds: 1800),
  });

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.period)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          final t = _controller.value;
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1 + widget.growth * t,
                child: Opacity(
                  opacity: (1 - t) * widget.ringOpacity,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color,
                    ),
                  ),
                ),
              ),
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One-shot diagonal light sweep across a surface after it appears.
class SheenSweep extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double radius;

  const SheenSweep({
    super.key,
    required this.child,
    this.delay = const Duration(milliseconds: 300),
    this.radius = 16,
  });

  @override
  State<SheenSweep> createState() => _SheenSweepState();
}

class _SheenSweepState extends State<SheenSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (!mounted) return;
      _controller.forward().whenComplete(() {
        if (mounted) setState(() => _done = true);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: _done
                ? const SizedBox.shrink()
                : ClipRRect(
                    borderRadius: BorderRadius.circular(widget.radius),
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (_, __) {
                        final t = Curves.easeInOut.transform(_controller.value);
                        return LayoutBuilder(
                          builder: (_, constraints) {
                            final width = constraints.maxWidth;
                            return Stack(
                              children: [
                                Positioned(
                                  left: -140 + (width + 280) * t,
                                  top: -60,
                                  bottom: -60,
                                  width: 110,
                                  child: Opacity(
                                    opacity: math.sin(math.pi * t) * 0.45,
                                    child: Transform.rotate(
                                      angle: 0.28,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Colors.white.withOpacity(0),
                                              Colors.white.withOpacity(0.65),
                                              Colors.white.withOpacity(0),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Thin brand gradient line with a slow travelling highlight.
class AnimatedHairline extends StatefulWidget {
  final double height;
  final List<Color> colors;

  const AnimatedHairline({
    super.key,
    this.height = 2,
    this.colors = const [
      Color(0xFF2563EB),
      Color(0xFFD4AF37),
      Color(0xFF0EA5E9),
      Color(0xFF2563EB),
      Color(0xFFD4AF37),
    ],
  });

  @override
  State<AnimatedHairline> createState() => _AnimatedHairlineState();
}

class _AnimatedHairlineState extends State<AnimatedHairline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          final shift = _controller.value * 3;
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-1.5 + shift, 0),
                end: Alignment(1.5 + shift, 0),
                colors: widget.colors,
              ),
            ),
          );
        },
      ),
    );
  }
}
