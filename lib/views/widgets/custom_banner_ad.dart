import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import '../../constants/admob_ids.dart';
import 'package:provider/provider.dart';
import '../../controllers/purchase_controller.dart';
import '../../utils/easy_read_access.dart';

class CustomBannerAd extends StatelessWidget {
  final bool visible;
  final ValueChanged<double>? onOccupiedHeight;

  /// Settings is the only slot that stays up in easy read mode.
  final bool allowInEasyReadMode;

  const CustomBannerAd({
    super.key,
    this.visible = true,
    this.onOccupiedHeight,
    this.allowInEasyReadMode = false,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onOccupiedHeight?.call(0);
      });
      return const SizedBox.shrink();
    }
    final isPro = context.select<PurchaseController, bool>((c) => c.isPro);
    final easyRead = EasyReadAccess.enabled(context);
    final allowed = !easyRead || allowInEasyReadMode;
    return _BannerAdHost(
      show: visible && !isPro && allowed,
      onOccupiedHeight: onOccupiedHeight,
    );
  }
}

class _BannerAdHost extends StatefulWidget {
  final bool show;
  final ValueChanged<double>? onOccupiedHeight;

  const _BannerAdHost({required this.show, this.onOccupiedHeight});

  @override
  State<_BannerAdHost> createState() => _BannerAdHostState();
}

class _BannerAdHostState extends State<_BannerAdHost> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  final GlobalKey _adViewKey = GlobalKey();
  Timer? _retryTimer;
  int _failCount = 0;

  String get _bannerAdUnitId => AdMobIds.bannerAdUnitId;

  bool get _isMobile {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  double get _occupiedHeight {
    if (!widget.show || !_isAdLoaded || _bannerAd == null) return 0;
    return _bannerAd!.size.height.toDouble();
  }

  void _emitOccupiedHeight() {
    widget.onOccupiedHeight?.call(_occupiedHeight);
  }

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _loadBannerAd();
    WidgetsBinding.instance.addPostFrameCallback((_) => _emitOccupiedHeight());
  }

  @override
  void didUpdateWidget(covariant _BannerAdHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Respect the retry back-off; don't reload on every parent rebuild.
    if (widget.show && _bannerAd == null && !(_retryTimer?.isActive ?? false)) {
      _loadBannerAd();
    }
    if (!widget.show) {
      // Pro / hidden: no retries
      _retryTimer?.cancel();
      _retryTimer = null;
    }
    if (oldWidget.show != widget.show) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _emitOccupiedHeight());
    }
  }

  void _loadBannerAd() {
    if (!_isMobile || _bannerAd != null) return;

    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _failCount = 0;
          if (mounted) {
            setState(() => _isAdLoaded = true);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _emitOccupiedHeight();
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('廣告載入失敗: $error (refresh=${_isAdLoaded && identical(ad, _bannerAd)})');
          // Auto-refresh failures also arrive here. Keep showing the banner that
          // already loaded; the SDK tries again at the next refresh.
          if (_isAdLoaded && identical(ad, _bannerAd)) return;
          ad.dispose();
          _scheduleRetry();
          if (mounted) {
            setState(() {
              _bannerAd = null;
              _isAdLoaded = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _emitOccupiedHeight();
            });
          }
        },
      ),
    )..load();
  }

  // First load failed (timeout / no fill): retry 30 s, 60 s, 120 s ... up to 5 min.
  void _scheduleRetry() {
    _retryTimer?.cancel();
    if (!mounted || !widget.show) return; // e.g. active Pro user
    _failCount++;
    final seconds = (30 * (1 << (_failCount - 1).clamp(0, 4))).clamp(30, 300);
    _retryTimer = Timer(Duration(seconds: seconds), () {
      debugPrint('廣告重試 #$_failCount (等咗 ${seconds}s)');
      if (mounted && widget.show && _bannerAd == null) _loadBannerAd();
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.show || !_isAdLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adHeight = _bannerAd!.size.height.toDouble();
    final adWidth = _bannerAd!.size.width.toDouble();

    return Container(
      color: isDark ? Colors.black : Colors.white,
      width: double.infinity,
      height: adHeight,
      alignment: Alignment.center,
      child: SizedBox(
        width: adWidth,
        height: adHeight,
        child: AdWidget(key: _adViewKey, ad: _bannerAd!),
      ),
    );
  }
}
