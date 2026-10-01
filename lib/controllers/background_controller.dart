import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

class BackgroundController extends ChangeNotifier {
  String? _backgroundImagePath;
  double _bgBlur = 0.0; // 🌟 新增：預設模糊度為 0 (無模糊)

  String? get backgroundImagePath => _backgroundImagePath;
  double get bgBlur => _bgBlur;

  BackgroundController() {
    _loadBackground();
  }

  Future<void> _loadBackground() async {
    final prefs = await SharedPreferences.getInstance();
    _backgroundImagePath = prefs.getString('custom_background');
    _bgBlur = prefs.getDouble('custom_background_blur') ?? 0.0; // 讀取模糊度
    notifyListeners();
  }

  Future<void> pickAndSaveBackground() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery, 
      imageQuality: 80, 
      maxWidth: 1080, 
      maxHeight: 1920
    );

    if (image != null) {
      final directory = await getApplicationDocumentsDirectory();
      final fileName = path.basename(image.path);
      final savedImage = await File(image.path).copy('${directory.path}/$fileName');

      _backgroundImagePath = savedImage.path;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_background', _backgroundImagePath!);
      notifyListeners();
    }
  }
  
  // 🌟 新增：調節並儲存模糊度的方法
  Future<void> setBlur(double value) async {
    _bgBlur = value;
    notifyListeners(); // 實時更新畫面
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('custom_background_blur', value);
  }

  Future<void> clearBackground() async {
    _backgroundImagePath = null;
    _bgBlur = 0.0; // 重置模糊度
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('custom_background');
    await prefs.remove('custom_background_blur');
    notifyListeners();
  }
}