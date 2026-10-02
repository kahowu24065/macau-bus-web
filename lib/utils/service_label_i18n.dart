/// Translates DSAT timetable section headers (always Chinese in the source
/// data, e.g. 「星期一至五（公眾假期除外）」, 「2026年10月1-7日」) and the
/// 不設服務 cell text into zhHans / en / pt. Rule based (phrase dictionary +
/// date formatting) so new monthly data keeps working; anything it cannot
/// fully parse is returned unchanged. zh is always returned as-is.
class ServiceLabelI18n {
  static const _days = {
    '一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7,
  };
  static const _dayEn = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dayPt = ['', 'Seg.', 'Ter.', 'Qua.', 'Qui.', 'Sex.', 'Sáb.', 'Dom.'];
  static const _monEn = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _monPt = ['', 'jan.', 'fev.', 'mar.', 'abr.', 'mai.', 'jun.', 'jul.', 'ago.', 'set.', 'out.', 'nov.', 'dez.'];

  /// Phrases (longest first) -> [en, pt].
  static const _phrases = <String, List<String>>{
    '澳門大學休假日': ['UM vacation days', 'dias de férias da UM'],
    '澳大休假日': ['UM vacation days', 'dias de férias da UM'],
    '強制性假日': ['mandatory holidays', 'feriados obrigatórios'],
    '公眾假期': ['public holidays', 'feriados públicos'],
    '公眾假日': ['public holidays', 'feriados públicos'],
    '假期': ['holidays', 'feriados'],
    '其餘日子': ['Other days', 'Restantes dias'],
    '其他日子': ['Other days', 'Restantes dias'],
    '每日': ['Daily', 'Diariamente'],
    '每天': ['Daily', 'Diariamente'],
    '平日': ['Weekdays', 'Dias úteis'],
    '不設服務': ['No service', 'Sem serviço'],
    '暫停服務': ['Service suspended', 'Serviço suspenso'],
    '全日': ['All day', 'Todo o dia'],
    '通宵': ['Overnight', 'Noturno'],
  };

  /// Traditional -> simplified for the words that occur in these labels.
  static const _hans = <String, String>{
    '澳門大學': '澳门大学', '強制性': '强制性', '公眾': '公众', '其餘': '其余',
    '不設服務': '不设服务', '暫停服務': '暂停服务', '服務': '服务', '學': '学',
    '門': '门', '眾': '众', '餘': '余', '設': '设', '暫': '暂', '務': '务',
    '強': '强', '時': '时', '間': '间', '節': '节', '點': '点', '鐘': '钟',
    '從': '从', '開': '开', '關': '关', '過': '过', '來': '来', '個': '个',
  };

  static final _cjk = RegExp(r'[\u3400-\u9fff]');

  /// Max characters per header line before a long exception goes on its own
  /// line (CJK chars are ~2x as wide as Latin ones).
  static const int _maxCjkLine = 14;
  static const int _maxLatinLine = 36;

  static String translate(String raw, String lang) {
    final s = raw.trim();
    if (s.isEmpty || !_cjk.hasMatch(s)) return raw;
    if (lang == 'zh' || lang == 'zhHans') {
      var out = _wrapZh(s);
      if (lang == 'zhHans') {
        for (final e in _hans.entries) {
          out = out.replaceAll(e.key, e.value);
        }
      }
      return out;
    }
    final en = lang != 'pt';
    try {
      final out = _label(s, en);
      if (out == null || _cjk.hasMatch(out)) return raw;
      return out;
    } catch (_) {
      return raw;
    }
  }

  /// Line breaks for the raw Chinese label: a new line where a new year or
  /// month group starts ("…25日2026年10月1日…", "…25日、10月1日…"), and
  /// before a long （…除外） part.
  static String _wrapZh(String s) {
    var out = s
        // "…日2026年…" or "…日、2026年…": new year group.
        .replaceAllMapped(RegExp(r'(日|號|号)\s*(?:、|，|,|及|和)?\s*(?=\d{4}\s*年)'), (m) => '${m[1]}\n')
        // "…日、10月…": new month group in the same year.
        .replaceAllMapped(RegExp(r'(日|號|号)\s*(?:、|，|,|及|和)\s*(?=\d{1,2}\s*月)'), (m) => '${m[1]}\n');
    final ex = RegExp(r'^(.+?)\s*([（(].+除外\s*[)）])$').firstMatch(out);
    if (!out.contains('\n') && ex != null && out.length > _maxCjkLine) {
      out = '${ex[1]}\n${ex[2]}';
    }
    return out;
  }

  static String _wrapLatin(String head, String tail) =>
      head.length + tail.length + 1 > _maxLatinLine ? '$head\n$tail' : '$head $tail';

  static String? _label(String s, bool en) {
    // "X（Y除外）" / "X(Y除外)"
    final ex = RegExp(r'^(.*?)\s*[（(]\s*(.+?)\s*除外\s*[)）]\s*$').firstMatch(s);
    if (ex != null) {
      final head = _list(ex.group(1)!, en, capitalize: true);
      final exc = _list(ex.group(2)!, en);
      if (head == null || exc == null) return null;
      return _wrapLatin(head, en ? '(except $exc)' : '(exceto $exc)');
    }
    // "Y除外" without brackets
    final ex2 = RegExp(r'^(.*?)\s*[，,]?\s*(.+?)除外$').firstMatch(s);
    if (ex2 != null && ex2.group(1)!.isNotEmpty) {
      final head = _list(ex2.group(1)!, en, capitalize: true);
      final exc = _list(ex2.group(2)!, en);
      if (head == null || exc == null) return null;
      return _wrapLatin(head, en ? '(except $exc)' : '(exceto $exc)');
    }
    final dates = _dates(s, en);
    if (dates != null) return dates;
    return _list(s, en, capitalize: true);
  }

  /// "星期六、日及公眾假期" -> "Sat, Sun & public holidays".
  static String? _list(String s, bool en, {bool capitalize = false}) {
    final dates = _dates(s, en);
    if (dates != null) return dates;
    final parts = <String>[];
    // Day expressions may use 、 inside ("星期六、日"), so walk tokens.
    final tokens = s.split(RegExp(r'\s*(?:、|，|,|及|和|與|与|以及|&)\s*')).where((t) => t.isNotEmpty).toList();
    var inWeekday = false;
    for (var t in tokens) {
      if (t.startsWith('星期') || t.startsWith('週') || t.startsWith('周')) {
        inWeekday = true;
        t = t.replaceFirst(RegExp(r'^(星期|週|周)'), '');
      }
      final range = RegExp(r'^([一二三四五六日天])\s*(?:至|到|-|－)\s*([一二三四五六日天])$').firstMatch(t);
      if (inWeekday && range != null) {
        final a = _days[range.group(1)!]!, b = _days[range.group(2)!]!;
        parts.add(en ? '${_dayEn[a]}–${_dayEn[b]}' : '${_dayPt[a]} a ${_dayPt[b]}');
        continue;
      }
      if (inWeekday && t.length == 1 && _days.containsKey(t)) {
        final d = _days[t]!;
        parts.add(en ? _dayEn[d] : _dayPt[d]);
        continue;
      }
      final p = _phrases[t];
      if (p != null) {
        parts.add(en ? p[0] : p[1]);
        inWeekday = false;
        continue;
      }
      return null;
    }
    if (parts.isEmpty) return null;
    var out = parts.length == 1
        ? parts.first
        : '${parts.sublist(0, parts.length - 1).join(', ')}${en ? ' & ' : ' e '}${parts.last}';
    if (capitalize && out.isNotEmpty) out = out[0].toUpperCase() + out.substring(1);
    return out;
  }

  /// "2026年10月1-7日", "2026年9月12日、19日、25日2026年10月1日及4日".
  static String? _dates(String s, bool en) {
    final tok = RegExp(r'(?:(\d{4})\s*年)?\s*(?:(\d{1,2})\s*月)?\s*(\d{1,2})\s*(?:日|號|号)?\s*(?:(?:-|－|–|至|到)\s*(?:(\d{1,2})\s*月)?\s*(\d{1,2})\s*(?:日|號|号))?');
    final rest = s.replaceAll(RegExp(r'\s*(?:、|，|,|及|和|與|与|;|；)\s*'), '|');
    final items = <List<int>>[]; // y, m, d1, m2, d2
    int? y, m;
    var pos = 0;
    while (pos < rest.length) {
      if (rest[pos] == '|') { pos++; continue; }
      final mt = tok.matchAsPrefix(rest, pos);
      if (mt == null || mt.end == pos) return null;
      if (mt.group(1) != null) y = int.parse(mt.group(1)!);
      if (mt.group(2) != null) m = int.parse(mt.group(2)!);
      if (m == null || !mt.group(0)!.contains(RegExp(r'[日號号]'))) return null;
      final d1 = int.parse(mt.group(3)!);
      final m2 = mt.group(4) != null ? int.parse(mt.group(4)!) : m;
      final d2 = mt.group(5) != null ? int.parse(mt.group(5)!) : 0;
      items.add([y ?? 0, m, d1, m2, d2]);
      if (mt.group(4) != null) m = m2;
      pos = mt.end;
    }
    if (items.isEmpty) return null;
    final mon = en ? _monEn : _monPt;
    final and = en ? ' & ' : ' e ';
    String day(List<int> it) {
      if (it[4] == 0) return '${it[2]}';
      if (it[3] != it[1]) return '${it[2]} ${mon[it[1]]} – ${it[4]}';
      return '${it[2]}–${it[4]}';
    }
    String joinList(List<String> l) => l.length == 1
        ? l.first
        : '${l.sublist(0, l.length - 1).join(', ')}$and${l.last}';
    // Group by (year, month of the end of the item).
    final groups = <String>[];
    var i = 0;
    while (i < items.length) {
      final gy = items[i][0], gm = items[i][3];
      final ds = <String>[];
      while (i < items.length && items[i][0] == gy && items[i][3] == gm) {
        ds.add(day(items[i]));
        i++;
      }
      var g = '${joinList(ds)} ${mon[gm]}';
      if (gy > 0) g += ' $gy';
      groups.add(g);
    }
    // One line per month/year group.
    return groups.join('\n');
  }
}
