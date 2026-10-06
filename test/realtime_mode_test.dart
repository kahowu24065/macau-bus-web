import 'package:flutter_test/flutter_test.dart';
import 'package:macau_bus_app/constants/app_translations.dart';
import 'package:macau_bus_app/models/bus.dart';
import 'package:macau_bus_app/services/open_data_config.dart';
import 'package:macau_bus_app/utils/bus_eta_estimate.dart';

void main() {
  test('config off hides live arrivals and route notices', () {
    expect(
      RealtimeGate.showLive(configRealtime: false, etaRealtime: null),
      isFalse,
    );
    expect(
      RealtimeGate.showRouteNotices(
        configRealtime: false,
        configRouteNotices: false,
        noticesRealtime: null,
      ),
      isFalse,
    );
  });

  test('a response flag overrides a cached config value', () {
    expect(
      RealtimeGate.showLive(configRealtime: false, etaRealtime: true),
      isTrue,
    );
    expect(
      RealtimeGate.showLive(configRealtime: true, etaRealtime: false),
      isFalse,
    );
    expect(
      RealtimeGate.showRouteNotices(
        configRealtime: false,
        configRouteNotices: false,
        noticesRealtime: true,
      ),
      isTrue,
    );
  });

  test('unknown config falls back to the response, then to live UI', () {
    expect(RealtimeGate.showLive(configRealtime: null, etaRealtime: false), isFalse);
    expect(RealtimeGate.showLive(configRealtime: null, etaRealtime: true), isTrue);
    expect(RealtimeGate.showLive(configRealtime: null, etaRealtime: null), isTrue);
    expect(
      RealtimeGate.showRouteNotices(
        configRealtime: null,
        configRouteNotices: null,
        noticesRealtime: null,
      ),
      isTrue,
    );
  });

  test('attribution names the platform and the date obtained', () {
    const block = RealtimeGate.attributionBlock;
    expect(
      block(
        lang: 'zh',
        attribution: '資料來源：澳門特別行政區政府數據開放平台',
        attributionEn: null,
        attributionPt: null,
        dataDate: '2026-10-06',
      ),
      '資料來源：澳門特別行政區政府數據開放平台\n取得日期：2026-10-06',
    );
    expect(
      block(
        lang: 'en',
        attribution: null,
        attributionEn: 'Source: Macao SAR Government Open Data Platform (data.gov.mo)',
        attributionPt: null,
        dataDate: '2026-10-06',
      ),
      'Source: Macao SAR Government Open Data Platform (data.gov.mo)\nDate obtained: 2026-10-06',
    );
    expect(
      block(
        lang: 'pt',
        attribution: null,
        attributionEn: null,
        attributionPt: 'Fonte: Plataforma de Dados Abertos do Governo da RAEM (data.gov.mo)',
        dataDate: '2026-10-06',
      ),
      contains('Data obtida: 2026-10-06'),
    );
    expect(
      block(
        lang: 'en',
        attribution: null,
        attributionEn: null,
        attributionPt: null,
        dataDate: null,
      ),
      RealtimeGate.fallbackAttribution,
    );
  });

  test('placeholder copy and the traditional privacy title stay in place', () {
    expect(AppTranslations.data['zh']!['realtime_pending'], '實時到站：申請中');
    expect(AppTranslations.data['zhHans']!['realtime_pending'], '实时到站：申请中');
    expect(AppTranslations.data['en']!['realtime_pending'], 'Live arrivals: pending approval');
    expect(AppTranslations.data['pt']!['realtime_pending'], 'Tempo real: pedido pendente');
    expect(AppTranslations.data['zh']!['privacy_policy'], '私隱權政策');
  });

  test('later buses use their own etaMinutes', () {
    expect(
      approachingEtaMinutes(
        busEtaMinutes: 11,
        isFirst: false,
        stopsAway: 6,
        firstStopsAway: 2,
        firstStatusMinutes: 4,
      ),
      11,
    );
    expect(
      approachingEtaMinutes(
        busEtaMinutes: null,
        isFirst: false,
        stopsAway: 6,
        firstStopsAway: 2,
        firstStatusMinutes: 4,
      ),
      12,
    );
    expect(
      approachingEtaMinutes(
        busEtaMinutes: 9,
        isFirst: true,
        stopsAway: 2,
        firstStopsAway: 2,
        firstStatusMinutes: 4,
      ),
      4,
    );
  });

  test('bus json reads etaMinutes', () {
    final bus = Bus.fromJson({
      'busLicense': 'MB-1',
      'lat': 22.2,
      'lng': 113.5,
      'speed': 20,
      'currentStopSeq': 3,
      'etaMinutes': 7,
    });
    expect(bus.etaMinutes, 7);
    expect(Bus.fromJson({'etaMinutes': null}).etaMinutes, isNull);
  });
}
