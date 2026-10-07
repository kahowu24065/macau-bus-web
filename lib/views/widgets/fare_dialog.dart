import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/language_controller.dart';

void showBusFareDialog(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final langCtrl = context.read<LanguageController>();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.monetization_on, color: Colors.amber, size: 28),
          const SizedBox(width: 8),
          Text(langCtrl.tr('fare_table'), style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fareRow(langCtrl.tr('general_fare'), '\$6.0', isDark),
          const SizedBox(height: 12),
          _fareRow(langCtrl.tr('macau_pass'), '\$3.0', isDark),
          const SizedBox(height: 12),
          _fareRow(langCtrl.tr('student_card'), '\$1.5', isDark),
          const SizedBox(height: 12),
          _fareRow(langCtrl.tr('elderly_disabled'), '\$0.0', isDark),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(langCtrl.tr('btn_close'), style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}

Widget _fareRow(String type, String price, bool isDark) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(type, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 15)),
      Text(price, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
    ],
  );
}
