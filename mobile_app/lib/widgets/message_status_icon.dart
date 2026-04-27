import 'dart:math';
import 'package:flutter/material.dart';
import '../models/message.dart';
import 'checkmark_painter.dart';

/// Animated message status icon using the morphing checkmark system.
///
/// State transitions:
///   sending  → rotating arc with tertiary color
///   queued   → single checkmark with glow pulse
///   delivered → double checkmark with primary color
///   failed   → shaking X with error color
class MessageStatusIcon extends StatefulWidget {
  final MessageStatus status;
  final double size;

  const MessageStatusIcon({
    super.key,
    required this.status,
    this.size = 18,
  });

  @override
  State<MessageStatusIcon> createState() => _MessageStatusIconState();
}

class _MessageStatusIconState extends State<MessageStatusIcon>
    with TickerProviderStateMixin {
  late AnimationController _spinController;
  late AnimationController _morphController;
  late AnimationController _secondCheckController;
  late AnimationController _glowController;
  late AnimationController _shakeController;

  late Animation<double> _morphAnimation;
  late Animation<double> _secondCheckAnimation;
  late Animation<double> _shakeAnimation;


  @override
  void initState() {
    super.initState();

    // Spin controller — continuous rotation for "sending" state
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Morph controller — arc → single checkmark
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _morphAnimation = CurvedAnimation(
      parent: _morphController,
      curve: Curves.elasticOut,
    );

    // Second check controller — staggered slide-in
    _secondCheckController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _secondCheckAnimation = CurvedAnimation(
      parent: _secondCheckController,
      curve: Curves.elasticOut,
    );

    // Glow pulse for "queued" state
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Shake for "failed" state
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeController, curve: Curves.elasticIn),
    );

    _applyStatus(widget.status, animate: false);
  }

  @override
  void didUpdateWidget(MessageStatusIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      _applyStatus(widget.status, animate: true);
    }
  }

  void _applyStatus(MessageStatus status, {required bool animate}) {
    _spinController.stop();
    _glowController.stop();

    switch (status) {
      case MessageStatus.sending:
        _spinController.repeat();
        if (!animate) {
          _morphController.value = 0;
          _secondCheckController.value = 0;
        }
        break;

      case MessageStatus.queued:
        _morphController.forward(from: animate ? 0 : 1);
        _secondCheckController.value = 0;
        _glowController.repeat(reverse: true);
        break;

      case MessageStatus.delivered:
        _morphController.value = 1;
        if (animate) {
          // 50ms stagger delay before second check appears
          Future.delayed(const Duration(milliseconds: 50), () {
            if (mounted) _secondCheckController.forward(from: 0);
          });
        } else {
          _secondCheckController.value = 1;
        }
        break;

      case MessageStatus.failed:
        _morphController.value = 0;
        _secondCheckController.value = 0;
        if (animate) {
          _shakeController.forward(from: 0);
        }
        break;
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    _morphController.dispose();
    _secondCheckController.dispose();
    _glowController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _spinController,
          _morphAnimation,
          _secondCheckAnimation,
          _glowController,
          _shakeAnimation,
        ]),
        builder: (context, _) {
          // Dynamic color based on state (Phase 1, Section 2)
          Color iconColor;
          Color? glowColor;

          switch (widget.status) {
            case MessageStatus.sending:
              iconColor = cs.tertiary;
              break;
            case MessageStatus.queued:
              iconColor = cs.tertiary;
              glowColor = cs.tertiaryContainer;
              break;
            case MessageStatus.delivered:
              iconColor = cs.primary;
              break;
            case MessageStatus.failed:
              iconColor = cs.error;
              break;
          }

          return SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: CheckmarkPainter(
                morphProgress: _morphAnimation.value,
                secondCheckProgress: _secondCheckAnimation.value,
                spinAngle: _spinController.value * 2 * pi,
                isError: widget.status == MessageStatus.failed,
                shakeOffset: widget.status == MessageStatus.failed
                    ? sin(_shakeAnimation.value * pi * 4) * 2
                    : 0,
                color: iconColor,
                glowColor: glowColor,
                glowOpacity: widget.status == MessageStatus.queued
                    ? _glowController.value
                    : 0,
              ),
            ),
          );
        },
      ),
    );
  }
}
