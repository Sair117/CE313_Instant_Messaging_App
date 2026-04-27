import 'package:flutter/material.dart';

/// A smooth, high-refresh-rate page transition using shared axis (vertical slide + fade).
/// Uses a fast 250ms duration with easeOutCubic for buttery-smooth feel.
class SmoothPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  SmoothPageRoute({required this.page, RouteSettings? routeSettings})
      : super(
          settings: routeSettings,
          transitionDuration: const Duration(milliseconds: 250),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Primary transition: slide up + fade in
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            // Secondary transition (outgoing page): slight scale down + fade
            final secondaryCurve = CurvedAnimation(
              parent: secondaryAnimation,
              curve: Curves.easeOutCubic,
            );

            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.06),
                end: Offset.zero,
              ).animate(curvedAnimation),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnimation),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 1.0, end: 0.96).animate(secondaryCurve),
                  child: child,
                ),
              ),
            );
          },
        );
}
