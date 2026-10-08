/// Place-search cleanup for names Google returns in the wrong script, or as
/// several nearby points for one venue.
class PlaceSuggestions {
  /// Google place id for The Venetian Macao hotel, not the bus stop or casino.
  static const venetianPlaceId = 'ChIJt7JweQVwATQRr242E0IBxVM';

  static List<dynamic> refine(String query, String lang, List<dynamic> remote) {
    final name = _venetianName(query, lang);
    if (name == null) return remote;
    return [
      {
        'description': name,
        'place_id': venetianPlaceId,
        'structured_formatting': {
          'main_text': name,
          'secondary_text': '',
        },
      },
    ];
  }

  /// 威尼斯人 / 澳門威尼斯人, in either script. Anything longer stays a normal search.
  static String? _venetianName(String query, String lang) {
    if (lang != 'zh' && lang != 'zhHans') return null;
    final folded = query
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll('门', '門');
    if (folded != '威尼斯人' && folded != '澳門威尼斯人') return null;
    return lang == 'zhHans' ? '澳门威尼斯人' : '澳門威尼斯人';
  }
}
