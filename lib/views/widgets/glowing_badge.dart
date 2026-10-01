import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // 🌟 引入 Provider
import '../../controllers/language_controller.dart'; // 🌟 引入語言控制器

// ==========================================
// 🌟 實時動態霓虹漣漪提示組件 (獨立 API)
// ==========================================
class LiveTrackingBadge extends StatefulWidget {
  const LiveTrackingBadge({super.key});

  @override
  State<LiveTrackingBadge> createState() => _LiveTrackingBadgeState();
}

class _LiveTrackingBadgeState extends State<LiveTrackingBadge> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 設定漣漪擴散速度 (1.5秒一波)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final langCtrl = context.watch<LanguageController>(); // 🌟 監聽語言切換
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 1. 動態發光紅點與波紋
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _MiniRipplePainter(_controller.value),
              child: const SizedBox(width: 14, height: 14), // 預留空間俾波紋擴散
            );
          },
        ),
        const SizedBox(width: 8),
        // 2. 實時動態文字說明 (🌟 動態翻譯)
        Text(
          langCtrl.tr('live_tracking_status'),
          style: TextStyle(
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _MiniRipplePainter extends CustomPainter {
  final double animationValue;
  _MiniRipplePainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // 🔴 核心實體紅點
    final dotPaint = Paint()
      ..color = Colors.redAccent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 3.0, dotPaint);

    // 🌊 霓虹發光漣漪 (雙波紋追趕)
    for (int i = 0; i < 2; i++) {
      final progress = (animationValue + (i * 0.5)) % 1.0;
      final opacity = 1.0 - progress;
      final radius = 3.0 + (progress * 8.0); // 擴散範圍最大推至 11.0

      // 底層柔和光暈
      final glowPaint = Paint()
        ..color = Colors.redAccent.withValues(alpha: opacity * 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

      // 面層清脆光線
      final corePaint = Paint()
        ..color = Colors.redAccent.withValues(alpha: opacity * 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8;

      canvas.drawCircle(center, radius, glowPaint);
      canvas.drawCircle(center, radius, corePaint);
    }
  }

  @override
  bool shouldRepaint(_MiniRipplePainter oldDelegate) => oldDelegate.animationValue != animationValue;
}