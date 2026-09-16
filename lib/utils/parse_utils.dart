class ParseUtils {
  static double parseDbl(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    if (value is List && value.isNotEmpty) return parseDbl(value.last);
    return 0.0;
  }
}