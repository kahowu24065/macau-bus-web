import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
// 🌟 引入字典檔
import '../constants/app_translations.dart'; 

class LanguageController extends ChangeNotifier {
  String currentLanguage = 'zh'; 

  LanguageController() {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    // 🌟 統一使用 'language_code' 作為 Key
    currentLanguage = prefs.getString('language_code') ?? 'zh';
    notifyListeners();
  }

  Future<void> changeLanguage(String langCode) async {
    currentLanguage = langCode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    // 🌟 統一使用 'language_code' 作為 Key，確保背景程式讀得返
    await prefs.setString('language_code', langCode);
  }

  // 🌟 核心翻譯函數：傳入 Key，自動回傳對應語言嘅字眼
  String tr(String key) {
    return AppTranslations.data[currentLanguage]?[key] ?? 
           AppTranslations.data['zh']?[key] ?? 
           key; 
  }
}