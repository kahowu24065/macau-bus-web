import 'dart:async';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PurchaseController extends ChangeNotifier {
  static const String removeAdsMonthlyId = 'macau_bus_remove_ads_monthly'; // 替換為你的 Store 產品 ID

  final InAppPurchase _iap = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  bool _isPro = false;
  bool get isPro => _isPro;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<ProductDetails> _products = [];
  List<ProductDetails> get products => _products;

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

  Future<void> buySubscription(BuildContext context) async {
    final bool available = await _iap.isAvailable();
    if (!available) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('商店服務暫不可用')));
      return;
    }

    if (_products.isEmpty) {
      await loadProducts();
    }

    final product = _products.firstWhere(
      (p) => p.id == removeAdsMonthlyId,
      orElse: () => throw Exception('找不到此訂閱項目'),
    );

    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    _isLoading = true;
    notifyListeners();

    try {
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('發起訂閱失敗: $e')));
      }
    }
  }

  Future<void> restorePurchases(BuildContext context) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _iap.restorePurchases();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已完成購買紀錄回復請求')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('回復失敗: $e')));
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchaseDetailsList) async {
    for (var purchase in purchaseDetailsList) {
      if (purchase.status == PurchaseStatus.pending) {
        _isLoading = true;
      } else {
        if (purchase.status == PurchaseStatus.error) {
          _isLoading = false;
        } else if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
          await _setProUser(true);
        }
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        _isLoading = false;
      }
    }
    notifyListeners();
  }

  Future<void> _setProUser(bool value) async {
    _isPro = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_pro_user', value);
    notifyListeners();
  }

  // 僅供本機測試免廣告狀態切換使用
  Future<void> toggleDebugProStatus() async {
    await _setProUser(!_isPro);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}