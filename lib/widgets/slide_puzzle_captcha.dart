import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

const double _trackWidth = 300;
const double _thumbSize = 44;
const double _tolerancePx = 6;
const int _minDragMs = 350;
const int _minSamplePoints = 6;

double _randomTarget() {
  final min = _trackWidth * 0.45;
  final max = _trackWidth * 0.82;
  return min + Random().nextDouble() * (max - min);
}

String _makeToken(int durationMs, int samples) {
  final payload = jsonEncode({
    'v': 1,
    't': DateTime.now().millisecondsSinceEpoch,
    'd': durationMs,
    's': samples,
  });
  return base64Encode(utf8.encode(payload));
}

class SlidePuzzleCaptcha extends StatefulWidget {
  final void Function(String token) onVerified;
  final VoidCallback? onReset;

  const SlidePuzzleCaptcha({super.key, required this.onVerified, this.onReset});

  @override
  State<SlidePuzzleCaptcha> createState() => _SlidePuzzleCaptchaState();
}

enum _CaptchaStatus { idle, success, fail }

class _SlidePuzzleCaptchaState extends State<SlidePuzzleCaptcha> {
  late double _target;
  double _thumbX = 0;
  _CaptchaStatus _status = _CaptchaStatus.idle;
  DateTime? _dragStart;
  int _samples = 0;

  @override
  void initState() {
    super.initState();
    _target = _randomTarget();
  }

  double _clamp(double x) => x.clamp(0, _trackWidth - _thumbSize);

  void _reset() {
    setState(() {
      _target = _randomTarget();
      _thumbX = 0;
      _status = _CaptchaStatus.idle;
      _samples = 0;
      _dragStart = null;
    });
    widget.onReset?.call();
  }

  void _onPanStart(DragStartDetails details) {
    if (_status == _CaptchaStatus.success) return;
    _dragStart = DateTime.now();
    _samples = 0;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_status == _CaptchaStatus.success) return;
    setState(() {
      _thumbX = _clamp(_thumbX + details.delta.dx);
      _samples++;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_status == _CaptchaStatus.success || _dragStart == null) return;

    final durationMs = DateTime.now().difference(_dragStart!).inMilliseconds;
    final thumbCenter = _thumbX + _thumbSize / 2;
    final withinTolerance = (thumbCenter - _target).abs() <= _tolerancePx;
    final humanLikeTiming = durationMs >= _minDragMs;
    final humanLikeMotion = _samples >= _minSamplePoints;

    if (withinTolerance && humanLikeTiming && humanLikeMotion) {
      setState(() => _status = _CaptchaStatus.success);
      widget.onVerified(_makeToken(durationMs, _samples));
    } else {
      setState(() => _status = _CaptchaStatus.fail);
      Future.delayed(const Duration(milliseconds: 700), _reset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trackColor = switch (_status) {
      _CaptchaStatus.success => const Color(0xFFECFDF5),
      _CaptchaStatus.fail => const Color(0xFFFEF2F2),
      _CaptchaStatus.idle => const Color(0xFFF3F4F6),
    };
    final borderColor = switch (_status) {
      _CaptchaStatus.success => const Color(0xFFA7F3D0),
      _CaptchaStatus.fail => const Color(0xFFFECACA),
      _CaptchaStatus.idle => const Color(0xFFE5E7EB),
    };
    final thumbColor = switch (_status) {
      _CaptchaStatus.success => const Color(0xFF10B981),
      _CaptchaStatus.fail => const Color(0xFFEF4444),
      _CaptchaStatus.idle => const Color(0xFF0A0A0A),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Drag the slider to line up with the marker',
          style: TextStyle(fontSize: 11.5, color: Color(0xFF9CA3AF)),
        ),
        const SizedBox(height: 8),
        Container(
          width: _trackWidth,
          height: 48,
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
          ),
          child: Stack(
            children: [
              // target notch
              Positioned(
                left: _target - 10,
                top: 8,
                child: Container(
                  width: 20,
                  height: 32,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _status == _CaptchaStatus.success
                          ? const Color(0xFF34D399)
                          : const Color(0xFF9CA3AF),
                      width: 2,
                    ),
                  ),
                ),
              ),
              // fill behind the thumb
              Container(
                width: _thumbX + _thumbSize / 2,
                height: 48,
                decoration: BoxDecoration(
                  color: _status == _CaptchaStatus.success
                      ? const Color(0xFFA7F3D0)
                      : const Color(0xFF3355FF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              // draggable thumb
              Positioned(
                left: _thumbX,
                child: GestureDetector(
                  onPanStart: _onPanStart,
                  onPanUpdate: _onPanUpdate,
                  onPanEnd: _onPanEnd,
                  child: Container(
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      color: thumbColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      _status == _CaptchaStatus.success
                          ? Icons.check
                          : Icons.drag_indicator,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              switch (_status) {
                _CaptchaStatus.success => 'Verified — thanks!',
                _CaptchaStatus.fail => 'Not quite — try again',
                _CaptchaStatus.idle => 'Slide and release on the marker',
              },
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: _status == _CaptchaStatus.idle
                    ? FontWeight.normal
                    : FontWeight.w600,
                color: switch (_status) {
                  _CaptchaStatus.success => const Color(0xFF059669),
                  _CaptchaStatus.fail => const Color(0xFFEF4444),
                  _CaptchaStatus.idle => const Color(0xFF9CA3AF),
                },
              ),
            ),
            if (_status != _CaptchaStatus.success)
              IconButton(
                onPressed: _reset,
                icon: const Icon(
                  Icons.refresh,
                  size: 15,
                  color: Color(0xFF9CA3AF),
                ),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
      ],
    );
  }
}
