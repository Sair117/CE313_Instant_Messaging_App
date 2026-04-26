import 'dart:ui';
import 'package:flutter/material.dart';

/// Modern message input bar with frosted glass effect, emoji hint, and animated send button.
class InputBar extends StatefulWidget {
  final void Function(String content) onSend;

  const InputBar({super.key, required this.onSend});

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  late AnimationController _sendBtnController;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _sendBtnController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) {
        setState(() => _hasText = has);
        has ? _sendBtnController.forward() : _sendBtnController.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _sendBtnController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          decoration: BoxDecoration(
            color: cs.surface.withValues(alpha: 0.8),
            border: Border(
              top: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.15),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Text field with modern styling
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _hasText
                            ? cs.primary.withValues(alpha: 0.3)
                            : cs.outlineVariant.withValues(alpha: 0.12),
                        width: _hasText ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Emoji button
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 4),
                          child: IconButton(
                            icon: Icon(
                              Icons.emoji_emotions_outlined,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                              size: 22,
                            ),
                            onPressed: () {},
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        // Text input
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            textCapitalization: TextCapitalization.sentences,
                            maxLines: 5,
                            minLines: 1,
                            style: TextStyle(
                              fontSize: 15,
                              color: cs.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Message...',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 12,
                              ),
                              hintStyle: TextStyle(
                                color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                                fontSize: 15,
                              ),
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        // Attachment button
                        Padding(
                          padding: const EdgeInsets.only(right: 4, bottom: 4),
                          child: IconButton(
                            icon: Icon(
                              Icons.attach_file_rounded,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                              size: 22,
                            ),
                            onPressed: () {},
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Send / Mic button
                AnimatedBuilder(
                  animation: _sendBtnController,
                  builder: (context, _) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: _hasText
                              ? [cs.primary, cs.tertiary]
                              : [cs.surfaceContainerHighest, cs.surfaceContainerHighest],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: _hasText
                            ? [
                                BoxShadow(
                                  color: cs.primary.withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : [],
                      ),
                      child: IconButton(
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, animation) => ScaleTransition(
                            scale: animation,
                            child: child,
                          ),
                          child: Icon(
                            _hasText ? Icons.send_rounded : Icons.mic_rounded,
                            key: ValueKey(_hasText),
                            color: _hasText ? cs.onPrimary : cs.onSurfaceVariant,
                            size: 22,
                          ),
                        ),
                        onPressed: _hasText ? _send : null,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
