import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
// 🌟 引入 kReleaseMode 用於判斷是否為正式發布版本
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:provider/provider.dart';
import '../../controllers/purchase_controller.dart';

class CustomBannerAd extends StatefulWidget {
  const CustomBannerAd({super.key});

  @override
  State<CustomBannerAd> createState() => _CustomBannerAdState();
}

class _CustomBannerAdState extends State<CustomBannerAd> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  // 🌟 新增：智能獲取廣告 ID 嘅函數
  String get _bannerAdUnitId {
    if (kReleaseMode) {
      // 🚨 正式上線環境：請喺度填入你真實嘅「廣告單元 ID (Ad Unit ID)」
      if (Platform.isAndroid) {
        return 'ca-app-pub-6616126137620427/7395875873'; // 👈 替換為真實 Android 廣告單元 ID
      } else if (Platform.isIOS) {
        return 'ca-app-pub-xxxxxxxxxxxxxxxx/wwwwwwwwww'; // 👈 替換為真實 iOS 廣告單元 ID
      }
    } else {
      // 🛠️ 開發除錯環境：繼續使用 Google 官方的測試 ID，保證帳號安全
      if (Platform.isAndroid) {
        return 'ca-app-pub-3940256099942544/6300978111';
      } else if (Platform.isIOS) {
        return 'ca-app-pub-3940256099942544/2934735716';
      }
    }
    throw UnsupportedError("Unsupported platform");
  }

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
  }

  void _loadBannerAd() {
    // 🛡️ Web 及平台防護機制
    if (kIsWeb) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId, // 🌟 自動根據環境派發測試或真實 ID
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isAdLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('廣告載入失敗: $error');
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose(); // 🛡️ 確保離開頁面時釋放記憶體
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPro = context.watch<PurchaseController>().isPro;
    // 🌟 若已訂閱 Pro，直接返回空組件，不載入亦不佔用螢幕空間
    if (isPro) {
      return const SizedBox.shrink();
    }
    // 若廣告未載入，回傳 SizedBox.shrink() 隱藏自己，不佔空間
    if (!_isAdLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 🛡️ 防白屏/崩潰嘅安全外殼
    return Container(
      color: isDark ? Colors.black : Colors.white,
      width: double.infinity,
      height: _bannerAd!.size.height.toDouble(),
      alignment: Alignment.center,
      child: SizedBox(
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      ),
    );
  }
}