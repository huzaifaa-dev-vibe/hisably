import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'theme_spec.dart';

/// A frosted-glass surface: background blur + translucent gradient fill +
/// hairline border + optional soft shadow.
///
/// Performance contract: [blurred] panels carry a real [BackdropFilter].
/// Use at most a handful per screen (hero cards, chrome). For list items use
/// `blurred: false` (translucent fill only) — visually consistent, far
/// cheaper on mid-range devices.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = AppRadii.card,
    this.padding = EdgeInsets.zero,
    this.blurred = true,
    this.blurSigma = 24,
    this.borderColor,
    this.fill,
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool blurred;
  final double blurSigma;
  final Color? borderColor;
  final Color? fill;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;

    final body = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            (fill ?? s.glassFill).withValues(alpha: 1),
            (fill ?? s.glassFill).withValues(alpha: s.isDark ? 0.72 : 1),
          ],
        ),
      ),
      child: Padding(padding: padding, child: child),
    );

    final decorated = blurred
        ? ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: body,
            ),
          )
        : body;

    final outlined = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? s.glassBorder, width: 1),
        boxShadow: s.isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: decorated,
    );

    if (onTap == null) {
      return Semantics(label: semanticLabel, child: outlined);
    }
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          child: outlined,
        ),
      ),
    );
  }
}

/// Circular translucent icon button used in top bars.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.semanticLabel,
    this.size = 44,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final String? semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final btn = GlassPanel(
      radius: size / 2,
      blurred: false,
      semanticLabel: semanticLabel ?? tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, size: size * 0.5, color: context.spec.textPrimary),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// The Quick Add button — a 52 dp accent-gradient circle with a white plus.
/// Sized to sit fully INSIDE the bottom dock (no overlap with the bar or
/// page content).
class QuickAddButton extends StatelessWidget {
  const QuickAddButton({super.key, required this.onPressed, this.size = 52});

  final VoidCallback onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    return Semantics(
      button: true,
      label: 'Quick Add — record money in or out',
      child: Material(
        color: Colors.transparent,
        child: Ink(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                s.accent,
                Color.lerp(s.accent, s.transfer, 0.55)!,
              ],
            ),
            border: Border.all(
              color: s.isDark
                  ? Colors.white.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.65),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: s.accent.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Icon(Icons.add_rounded, size: size * 0.56, color: s.onAccent),
          ),
        ),
      ),
    );
  }
}
