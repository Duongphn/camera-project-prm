import 'dart:async';

import 'package:flutter/material.dart';

/// Thẻ thông báo của AI (kiểu Doka Cam): pill nền tối viền gradient nhẹ,
/// tự thu gọn thành nút ↩ sau [autoHideAfter]; bấm nút để đọc lại.
/// Đổi [message] → tự hiện lại từ đầu.
class AiToastCard extends StatefulWidget {
  const AiToastCard({
    super.key,
    required this.message,
    this.autoHideAfter = const Duration(seconds: 5),
  });

  final String message;
  final Duration autoHideAfter;

  @override
  State<AiToastCard> createState() => _AiToastCardState();
}

class _AiToastCardState extends State<AiToastCard> {
  bool _expanded = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant AiToastCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message) {
      setState(() => _expanded = true);
      _scheduleHide();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.autoHideAfter, () {
      if (mounted) setState(() => _expanded = false);
    });
  }

  void _show() {
    setState(() => _expanded = true);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: _expanded ? _buildCard() : _buildReopenButton(),
    );
  }

  Widget _buildCard() {
    return Container(
      key: const ValueKey('card'),
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [
            Color(0x88FF9E9E),
            Color(0x88FFE29E),
            Color(0x889EDCFF),
            Color(0x88D3B4FF),
          ],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          widget.message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            height: 1.35,
          ),
        ),
      ),
    );
  }

  Widget _buildReopenButton() {
    return Align(
      key: const ValueKey('reopen'),
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _show,
          child: const Padding(
            padding: EdgeInsets.all(7),
            child: Icon(Icons.u_turn_left, color: Colors.white70, size: 17),
          ),
        ),
      ),
    );
  }
}
