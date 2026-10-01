import 'dart:async';
import 'package:flutter/material.dart';

// ==========================================
// 🌟 1. 警告三角圖示 (透明度漸變呼吸)
// ==========================================
class BlinkingWarningIcon extends StatefulWidget {
  final VoidCallback onTap;
  const BlinkingWarningIcon({super.key, required this.onTap});
  @override State<BlinkingWarningIcon> createState() => _BlinkingWarningIconState();
}
class _BlinkingWarningIconState extends State<BlinkingWarningIcon> {
  Timer? _timer; bool _isRed = true;
  @override void initState() { super.initState(); _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) { if (mounted) setState(() => _isRed = !_isRed); }); }
  @override void dispose() { _timer?.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) { return InkWell(onTap: widget.onTap, child: Padding(padding: const EdgeInsets.all(4.0), child: Icon(Icons.warning_rounded, color: _isRed ? Colors.redAccent : Colors.yellow, size: 22))); }
}

// ==========================================
// 🌟 2. 大聲公通告圖示 (簡約透明度閃爍)
// ==========================================
class BlinkingAlertIcon extends StatefulWidget {
  const BlinkingAlertIcon({super.key});
  
  @override 
  State<BlinkingAlertIcon> createState() => _BlinkingAlertIconState();
}

class _BlinkingAlertIconState extends State<BlinkingAlertIcon> {
  Timer? _timer; 
  bool _isVisible = true;
  
  @override 
  void initState() { 
    super.initState(); 
    _timer = Timer.periodic(const Duration(milliseconds: 600), (timer) { 
      if (mounted) setState(() => _isVisible = !_isVisible); 
    }); 
  }
  
  @override 
  void dispose() { 
    _timer?.cancel(); 
    super.dispose(); 
  }
  
  @override 
  Widget build(BuildContext context) { 
    return Opacity(
      opacity: _isVisible ? 1.0 : 0.3, 
      child: const Icon(Icons.campaign, color: Colors.redAccent, size: 20)
    ); 
  }
}