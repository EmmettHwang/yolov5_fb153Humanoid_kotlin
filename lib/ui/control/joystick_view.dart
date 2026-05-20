import 'dart:math';
import 'package:flutter/material.dart';

/// 조이스틱 방향
enum JoystickDirection {
  stop,
  forward,
  backward,
  left,
  right,
  forwardLeft,
  forwardRight,
  backwardLeft,
  backwardRight,
}

/// 조이스틱 출력 데이터
class JoystickOutput {
  final JoystickDirection direction;
  final double power; // 0.0 ~ 1.0

  const JoystickOutput({
    required this.direction,
    required this.power,
  });

  static const JoystickOutput stop = JoystickOutput(
    direction: JoystickDirection.stop,
    power: 0.0,
  );

  /// 방향에 따른 기본 모션 번호 매핑
  static const Map<JoystickDirection, int> defaultMotionMap = {
    JoystickDirection.stop: 1,
    JoystickDirection.forward: 2,
    JoystickDirection.backward: 3,
    JoystickDirection.left: 4,
    JoystickDirection.right: 5,
    JoystickDirection.forwardLeft: 6,
    JoystickDirection.forwardRight: 7,
    JoystickDirection.backwardLeft: 8,
    JoystickDirection.backwardRight: 9,
  };

  String get directionLabel {
    switch (direction) {
      case JoystickDirection.stop:
        return '정지';
      case JoystickDirection.forward:
        return '전진';
      case JoystickDirection.backward:
        return '후진';
      case JoystickDirection.left:
        return '좌회전';
      case JoystickDirection.right:
        return '우회전';
      case JoystickDirection.forwardLeft:
        return '전진+좌';
      case JoystickDirection.forwardRight:
        return '전진+우';
      case JoystickDirection.backwardLeft:
        return '후진+좌';
      case JoystickDirection.backwardRight:
        return '후진+우';
    }
  }
}

/// 조이스틱 커스텀 위젯
class JoystickView extends StatefulWidget {
  final void Function(JoystickOutput output)? onJoystickMove;
  final void Function()? onJoystickRelease;
  final double size;

  const JoystickView({
    super.key,
    this.onJoystickMove,
    this.onJoystickRelease,
    this.size = 200,
  });

  @override
  State<JoystickView> createState() => _JoystickViewState();
}

class _JoystickViewState extends State<JoystickView> {
  double _stickX = 0;
  double _stickY = 0;
  bool _isTouching = false;
  JoystickDirection _currentDirection = JoystickDirection.stop;

  double get _baseRadius => widget.size / 2;
  double get _stickRadius => widget.size * 0.18;
  double get _maxDistance => _baseRadius - _stickRadius - 8;

  void _updateStickPosition(Offset localPos) {
    final centerX = _baseRadius;
    final centerY = _baseRadius;
    final dx = localPos.dx - centerX;
    final dy = localPos.dy - centerY;
    final distance = sqrt(dx * dx + dy * dy);

    double sx, sy;
    if (distance > _maxDistance) {
      sx = centerX + dx / distance * _maxDistance;
      sy = centerY + dy / distance * _maxDistance;
    } else {
      sx = localPos.dx;
      sy = localPos.dy;
    }

    final power = (distance / _maxDistance).clamp(0.0, 1.0);
    final direction = _calcDirection(dx, dy, power);

    setState(() {
      _stickX = sx - centerX;
      _stickY = sy - centerY;
      _currentDirection = direction;
    });

    widget.onJoystickMove?.call(JoystickOutput(
      direction: direction,
      power: power,
    ));
  }

  JoystickDirection _calcDirection(double dx, double dy, double power) {
    if (power < 0.15) return JoystickDirection.stop;

    final angle = atan2(dy, dx) * 180 / pi;

    if (angle >= -22.5 && angle < 22.5) return JoystickDirection.right;
    if (angle >= 22.5 && angle < 67.5) return JoystickDirection.backwardRight;
    if (angle >= 67.5 && angle < 112.5) return JoystickDirection.backward;
    if (angle >= 112.5 && angle < 157.5) return JoystickDirection.backwardLeft;
    if (angle >= 157.5 || angle < -157.5) return JoystickDirection.left;
    if (angle >= -157.5 && angle < -112.5) return JoystickDirection.forwardLeft;
    if (angle >= -112.5 && angle < -67.5) return JoystickDirection.forward;
    if (angle >= -67.5 && angle < -22.5) return JoystickDirection.forwardRight;

    return JoystickDirection.stop;
  }

  void _resetToCenter() {
    setState(() {
      _stickX = 0;
      _stickY = 0;
      _currentDirection = JoystickDirection.stop;
      _isTouching = false;
    });
    widget.onJoystickRelease?.call();
    widget.onJoystickMove?.call(JoystickOutput.stop);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        setState(() => _isTouching = true);
        _updateStickPosition(details.localPosition);
      },
      onPanUpdate: (details) {
        _updateStickPosition(details.localPosition);
      },
      onPanEnd: (_) => _resetToCenter(),
      onPanCancel: () => _resetToCenter(),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _JoystickPainter(
            stickX: _stickX,
            stickY: _stickY,
            baseRadius: _baseRadius,
            stickRadius: _stickRadius,
            isTouching: _isTouching,
            direction: _currentDirection,
          ),
        ),
      ),
    );
  }
}

/// 조이스틱 그리기
class _JoystickPainter extends CustomPainter {
  final double stickX;
  final double stickY;
  final double baseRadius;
  final double stickRadius;
  final bool isTouching;
  final JoystickDirection direction;

  const _JoystickPainter({
    required this.stickX,
    required this.stickY,
    required this.baseRadius,
    required this.stickRadius,
    required this.isTouching,
    required this.direction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // 외부 원 (베이스)
    final basePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(centerX, centerY), baseRadius - 4, basePaint);

    // 외부 원 테두리
    final borderPaint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(Offset(centerX, centerY), baseRadius - 4, borderPaint);

    // 방향 가이드 화살표들
    _drawDirectionGuides(canvas, centerX, centerY);

    // 중심선 (십자)
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(centerX - baseRadius * 0.7, centerY),
      Offset(centerX + baseRadius * 0.7, centerY),
      crossPaint,
    );
    canvas.drawLine(
      Offset(centerX, centerY - baseRadius * 0.7),
      Offset(centerX, centerY + baseRadius * 0.7),
      crossPaint,
    );

    // 스틱 그림자
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(
      Offset(centerX + stickX + 2, centerY + stickY + 4),
      stickRadius,
      shadowPaint,
    );

    // 스틱 (이동 핸들)
    final stickColor = isTouching
        ? (direction == JoystickDirection.stop
            ? Colors.cyan
            : Colors.cyanAccent)
        : Colors.cyan.withValues(alpha: 0.8);

    final stickPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          stickColor,
          stickColor.withValues(alpha: 0.7),
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(centerX + stickX, centerY + stickY),
        radius: stickRadius,
      ));
    canvas.drawCircle(
      Offset(centerX + stickX, centerY + stickY),
      stickRadius,
      stickPaint,
    );

    // 스틱 테두리
    final stickBorderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(
      Offset(centerX + stickX, centerY + stickY),
      stickRadius,
      stickBorderPaint,
    );

    // 스틱 중앙 점
    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawCircle(
      Offset(centerX + stickX, centerY + stickY),
      4,
      dotPaint,
    );
  }

  void _drawDirectionGuides(Canvas canvas, double cx, double cy) {
    final arrowPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final r = baseRadius * 0.65;

    // 위 (전진)
    _drawArrow(canvas, Offset(cx, cy - r), 270, arrowPaint);
    // 아래 (후진)
    _drawArrow(canvas, Offset(cx, cy + r), 90, arrowPaint);
    // 왼쪽 (좌회전)
    _drawArrow(canvas, Offset(cx - r, cy), 180, arrowPaint);
    // 오른쪽 (우회전)
    _drawArrow(canvas, Offset(cx + r, cy), 0, arrowPaint);
  }

  void _drawArrow(Canvas canvas, Offset pos, double angleDeg, Paint paint) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angleDeg * pi / 180);
    final path = Path()
      ..moveTo(0, -8)
      ..lineTo(6, 4)
      ..lineTo(-6, 4)
      ..close();
    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_JoystickPainter old) =>
      stickX != old.stickX ||
      stickY != old.stickY ||
      isTouching != old.isTouching ||
      direction != old.direction;
}
