import 'package:flutter/material.dart';

class KeyboardController extends ChangeNotifier {
  final TextEditingController routeController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();
  
  bool _isOpen = false;
  bool get isOpen => _isOpen;

  void openKeyboard() {
    if (!_isOpen) {
      _isOpen = true;
      notifyListeners();
    }
  }

  void closeKeyboard() {
    if (_isOpen) {
      _isOpen = false;
      searchFocusNode.unfocus();
      notifyListeners();
    }
  }

  void typeChar(String char) {
    final newText = routeController.text + char;
    // 🌟 核心修復：使用 TextEditingValue 直接更新文字及游標位置 (collapsed 即係取消反白)
    // 並且移除 requestFocus()，防止系統自動全選
    routeController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    notifyListeners();
  }

  void backspace() {
    if (routeController.text.isNotEmpty) {
      final newText = routeController.text.substring(0, routeController.text.length - 1);
      // 🌟 同樣使用 collapsed 取消反白
      routeController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
      notifyListeners();
    }
  }

  void clearText() {
    routeController.clear();
    notifyListeners();
  }
  
  @override
  void dispose() {
    routeController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }
}