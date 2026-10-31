import 'package:flutter/material.dart';

import 'theme_spec.dart';

/// The layered app background: vertical gradient + three fixed "aurora"
/// blobs drawn as radial gradients (no blur filters — cheap enough for
/// low-end devices and always static). Colours come from the active
/// [AppThemeSpec] so every theme gets its own atmosphere.
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.spec;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [s.bgTop, s.bgBottom],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -140,
            left: -90,
            child: _Blob(size: 340, color: s.aurora1),
          ),
          Positioned(
            top: 60,
            right: -120,
            child: _Blob(size: 320, color: s.aurora2),
          ),
          Positioned(
            bottom: -160,
            left: 40,
            child: _Blob(size: 380, color: s.aurora3),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
          ),
        ),
      ),
    );
  }
}
