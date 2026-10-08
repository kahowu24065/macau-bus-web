import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/constants/app_translations.dart';
import 'package:macau_bus_app/services/places_service.dart';
import 'package:macau_bus_app/utils/place_suggestions.dart';

void main() {
  const noisy = [
    {
      'description': '澳门威尼斯人酒店西翼大堂巴士站',
      'place_id': 'bus-stop',
      'structured_formatting': {'main_text': '威尼斯人酒店西翼大堂巴士站', 'secondary_text': '澳门'},
    },
    {
      'description': '澳门望德圣母湾大马路澳门威尼斯人',
      'place_id': PlaceSuggestions.venetianPlaceId,
      'structured_formatting': {'main_text': '澳门威尼斯人', 'secondary_text': '澳门望德圣母湾大马路'},
    },
    {
      'description': '澳门Estrada da Baía de N威尼斯人娛樂場',
      'place_id': 'casino',
      'structured_formatting': {'main_text': '威尼斯人娛樂場', 'secondary_text': '澳门'},
    },
  ];

  test('simplified Venetian queries become one simplified suggestion', () {
    for (final query in ['澳门威尼斯人', '威尼斯人', '澳門威尼斯人', '澳门 威尼斯人']) {
      final out = PlaceSuggestions.refine(query, 'zhHans', noisy);
      expect(out, hasLength(1), reason: query);
      expect(out.single['description'], '澳门威尼斯人', reason: query);
      expect(out.single['structured_formatting']['main_text'], '澳门威尼斯人', reason: query);
      expect(out.single['place_id'], PlaceSuggestions.venetianPlaceId, reason: query);
    }
  });

  test('traditional Venetian queries stay a single traditional name', () {
    for (final query in ['澳門威尼斯人', '威尼斯人', '澳门威尼斯人']) {
      final out = PlaceSuggestions.refine(query, 'zh', noisy);
      expect(out, hasLength(1), reason: query);
      expect(out.single['description'], '澳門威尼斯人', reason: query);
      expect(out.single['structured_formatting']['main_text'], '澳門威尼斯人', reason: query);
    }
  });

  test('other place queries are not collapsed', () {
    final remote = [
      {
        'description': '大三巴牌坊',
        'place_id': 'ruins',
        'structured_formatting': {'main_text': '大三巴牌坊'},
      },
    ];
    expect(PlaceSuggestions.refine('大三巴', 'zhHans', remote), remote);
    expect(PlaceSuggestions.refine('威尼斯人娛樂場', 'zhHans', noisy), noisy);
    expect(PlaceSuggestions.refine('威尼斯人', 'en', noisy), noisy);
  });

  test('place search asks Google for the app language', () {
    expect(PlacesService.googleLanguage('zhHans'), 'zh-CN');
    expect(PlacesService.googleLanguage('zh'), 'zh-TW');
    expect(PlacesService.googleLanguage('en'), 'en');
    expect(PlacesService.googleLanguage('pt'), 'pt');
  });

  test('the empty-route prompt exists in all four languages', () {
    const expected = {
      'zh': '請先搜尋一條路線',
      'zhHans': '请先搜索一条路线',
      'en': 'Search for a route first',
      'pt': 'Procure uma carreira primeiro',
    };
    for (final entry in expected.entries) {
      expect(AppTranslations.data[entry.key]!['please_search_route'], entry.value);
    }
  });
}
