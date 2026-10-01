import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../views/widgets/route_liquid_glass_nav.dart';
import 'language_controller.dart';

class PurchaseController extends ChangeNotifier {
  static const String removeAdsMonthlyId = 'macau_bus_remove_ads_monthly';

  final InAppPurchase _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  bool _isPro = false;
  bool get isPro => _isPro;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<ProductDetails> _products = [];
  List<ProductDetails> get products => _products;

  /// 商店回傳嘅本地化價錢。未載入到產品時係 null。
  String? get removeAdsPrice {
    for (final product in _products) {
      if (product.id == removeAdsMonthlyId && product.price.isNotEmpty) {
        return product.price;
      }
    }
    return null;
  }

  PurchaseController() {
    _initIAP();
  }

  Future<void> _initIAP() async {
    final prefs = await SharedPreferences.getInstance();
    _isPro = prefs.getBool('is_pro_user') ?? false;
    notifyListeners();

    final Stream<List<PurchaseDetails>> purchaseUpdated = _iap.purchaseStream;
    _subscription = purchaseUpdated.listen(_listenToPurchaseUpdated, onDone: () {
      _subscription.cancel();
    }, onError: (error) {
      debugPrint('IAP Stream Error: $error');
    });

    await loadProducts();
    await _syncEntitlement();
  }

  Future<void> loadProducts() async {
    final bool available = await _iap.isAvailable();
    if (!available) return;

    final Set<String> kIds = <String>{removeAdsMonthlyId};
    final ProductDetailsResponse response = await _iap.queryProductDetails(kIds);

    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('未找到產品 ID: ${response.notFoundIDs}');
    }
    _products = response.productDetails;
    notifyListeners();
  }

  bool _grantsPro(PurchaseDetails purchase) {
    return purchase.productID == removeAdsMonthlyId &&
        (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored);
  }

  /// 問商店呢個訂閱係咪仲有效。
  /// true = 有效，false = 商店確認冇，null = 問唔到（保留本機紀錄）。
  Future<bool?> _activeEntitlement() async {
    if (kIsWeb) return null;
    try {
      final available = await _iap.isAvailable();
      if (!available) return null;

      if (defaultTargetPlatform == TargetPlatform.android) {
        final addition = _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
        final response = await addition.queryPastPurchases();
        if (response.error != null) return null;
        var active = false;
        for (final purchase in response.pastPurchases) {
          if (!_grantsPro(purchase)) continue;
          active = true;
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        }
        return active;
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final transactions = await SK2Transaction.transactions();
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final tx in transactions) {
          if (tx.productId != removeAdsMonthlyId || tx.error != null) continue;
          final expiresAt = int.tryParse(tx.expirationDate ?? '');
          if (expiresAt == null || expiresAt > now) return true;
        }
        return false;
      }
    } catch (e) {
      debugPrint('entitlement check failed: $e');
    }
    return null;
  }

  Future<void> _syncEntitlement() async {
    final active = await _activeEntitlement();
    if (active == null) return;
    await _setProUser(active);
  }

  Future<void> buySubscription(BuildContext context) async {
    final lang = context.read<LanguageController>();
    final bool available = await _iap.isAvailable();
    if (!available) {
      if (!context.mounted) return;
      _snack(context, lang.tr('store_unavailable'));
      return;
    }

    if (_products.isEmpty) {
      await loadProducts();
    }

    ProductDetails? product;
    for (final item in _products) {
      if (item.id == removeAdsMonthlyId) {
        product = item;
        break;
      }
    }
    if (product == null) {
      if (context.mounted) {
        _snack(context, lang.tr('subscribe_failed'));
      }
      return;
    }

    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    _isLoading = true;
    notifyListeners();

    try {
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      if (context.mounted) {
        _snack(context, lang.tr('subscribe_failed'));
      }
    }
  }

  Future<void> restorePurchases(BuildContext context) async {
    final lang = context.read<LanguageController>();
    _isLoading = true;
    notifyListeners();
    try {
      final available = await _iap.isAvailable();
      if (!available) {
        if (context.mounted) _snack(context, lang.tr('store_unavailable'));
        return;
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await _iap.restorePurchases();
      }
      final active = await _activeEntitlement();
      if (!context.mounted) return;
      if (active == null) {
        _snack(context, lang.tr('restore_failed'));
        return;
      }
      await _setProUser(active);
      if (!context.mounted) return;
      _snack(context, active ? lang.tr('restore_opened') : lang.tr('restore_not_found'));
    } catch (e) {
      if (context.mounted) _snack(context, lang.tr('restore_failed'));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    if (purchaseDetailsList.isEmpty) {
      _isLoading = false;
      notifyListeners();
      return;
    }
    for (final purchase in purchaseDetailsList) {
      if (purchase.status == PurchaseStatus.pending) {
        _isLoading = true;
        continue;
      }
      _isLoading = false;
      if (purchase.status == PurchaseStatus.canceled) {
        continue;
      }
      if (_grantsPro(purchase)) {
        await _setProUser(true);
      }
      if (purchase.pendingCompletePurchase &&
          (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored)) {
        await _iap.completePurchase(purchase);
      }
    }
    notifyListeners();
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      RouteLiquidGlassNavStyle.snackBar(context: context, content: Text(message)),
    );
  }

  Future<void> _setProUser(bool value) async {
    _isPro = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_pro_user', value);
    notifyListeners();
  }

  // 僅供本機測試免廣告狀態切換使用
  Future<void> toggleDebugProStatus() async {
    if (!kDebugMode) return;
    await _setProUser(!_isPro);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
