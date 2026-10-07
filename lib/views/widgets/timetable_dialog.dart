import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/language_controller.dart';
import '../../utils/easy_read_access.dart';
import '../../services/dsat_timetable.dart';
import '../../utils/service_label_i18n.dart';

const Color _gold = Color(0xFFFFC107);
const Color _bandColor = Color(0xFF2A2A2A);

final RegExp _dateToken = RegExp(
  r'(?:(\d{4})\s*年)?'
  r'\s*(?:(\d{1,2})\s*月)?'
  r'\s*(\d{1,2})\s*(?:日|號|号)?'
  r'\s*(?:(?:-|－|–|至|到)\s*(?:(\d{1,2})\s*月)?\s*(\d{1,2})\s*(?:日|號|号))?',
);

/// Index of the day-type section that covers [day].
///
/// A dated section that contains [day] wins, and a shorter date list wins
/// over a longer one. Otherwise the narrowest weekday coverage wins
/// (Monday–Friday over Monday–Sunday, Sunday over Saturday-and-Sunday).
/// Returns 0 when [sections] is empty or none of the titles match.
int timetableSectionIndexFor(
  List<DsatTimetableSection> sections,
  DateTime day,
) {
  if (sections.isEmpty) return 0;
  var best = 0;
  var bestScore = -1;
  for (var i = 0; i < sections.length; i++) {
    final score = _sectionScore(sections[i].title, day);
    if (score > bestScore) {
      bestScore = score;
      best = i;
    }
  }
  return bestScore > 0 ? best : 0;
}

int _sectionScore(String title, DateTime day) {
  final dates = _datesIn(title);
  if (dates != null &&
      dates.any(
        (d) => d.year == day.year && d.month == day.month && d.day == day.day,
      )) {
    return 4000 - dates.length;
  }
  final days = _weekdaysInTitle(title);
  if (days.contains(day.weekday)) return 1000 - days.length;
  return -1;
}

/// Calendar days named by a pure date title, or null when [title] is not one.
List<DateTime>? _datesIn(String title) {
  if (RegExp(r'星期|週|周').hasMatch(title)) return null;
  if (!RegExp(r'\d{4}\s*年').hasMatch(title)) return null;
  final rest = title.trim().replaceAll(
    RegExp(r'\s*(?:、|，|,|及|和|與|与|;|；)\s*'),
    '|',
  );
  final out = <DateTime>[];
  int? year;
  int? month;
  var pos = 0;
  while (pos < rest.length) {
    if (rest[pos] == '|') {
      pos++;
      continue;
    }
    final match = _dateToken.matchAsPrefix(rest, pos);
    if (match == null ||
        match.end == pos ||
        !match.group(0)!.contains(RegExp(r'[日號号]'))) {
      return null;
    }
    final startYear = match.group(1) != null
        ? int.parse(match.group(1)!)
        : year;
    final startMonth = match.group(2) != null
        ? int.parse(match.group(2)!)
        : month;
    if (startYear == null || startMonth == null) return null;
    final startDay = int.parse(match.group(3)!);
    final endMonth = match.group(4) != null
        ? int.parse(match.group(4)!)
        : startMonth;
    final endDay = match.group(5) != null
        ? int.parse(match.group(5)!)
        : startDay;
    final endYear =
        (endMonth < startMonth || (endMonth == startMonth && endDay < startDay))
        ? startYear + 1
        : startYear;
    if (!_appendDays(
      out,
      startYear,
      startMonth,
      startDay,
      endYear,
      endMonth,
      endDay,
    )) {
      return null;
    }
    year = endYear;
    month = endMonth;
    pos = match.end;
  }
  return out.isEmpty ? null : out;
}

bool _appendDays(
  List<DateTime> out,
  int y1,
  int m1,
  int d1,
  int y2,
  int m2,
  int d2,
) {
  if (!_validDate(y1, m1, d1) || !_validDate(y2, m2, d2)) return false;
  var cursor = DateTime(y1, m1, d1);
  final end = DateTime(y2, m2, d2);
  if (end.isBefore(cursor)) return false;
  for (var n = 0; n < 63; n++) {
    out.add(DateTime(cursor.year, cursor.month, cursor.day));
    if (cursor.year == end.year &&
        cursor.month == end.month &&
        cursor.day == end.day) {
      return true;
    }
    cursor = cursor.add(const Duration(days: 1));
  }
  return false;
}

bool _validDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  final date = DateTime(year, month, day);
  return date.year == year && date.month == month && date.day == day;
}

Set<int> _weekdaysInTitle(String title) {
  final stripped = title.replaceAll(RegExp(r'[（(][^（）()]*[)）]'), '');
  if (RegExp(r'每日|每天').hasMatch(stripped)) return {1, 2, 3, 4, 5, 6, 7};
  if (!RegExp(r'星期|週|周').hasMatch(stripped)) {
    if (stripped.contains('平日')) return {1, 2, 3, 4, 5};
    return {};
  }
  const days = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '日': 7, '天': 7};
  final covered = <int>{};
  var inWeek = false;
  for (final raw in stripped.split(RegExp(r'\s*(?:、|，|,|及|和|與|与|以及)\s*'))) {
    var token = raw.trim();
    if (token.isEmpty) continue;
    if (RegExp(r'^(星期|週|周)').hasMatch(token)) {
      inWeek = true;
      token = token.replaceFirst(RegExp(r'^(星期|週|周)'), '');
    }
    if (!inWeek || token.isEmpty) continue;
    final range = RegExp(r'^([一二三四五六日天])\s*(?:至|到|-|－)\s*([一二三四五六日天])')
        .firstMatch(token);
    if (range != null) {
      final start = days[range.group(1)!]!;
      final end = days[range.group(2)!]!;
      if (start <= end) {
        for (var day = start; day <= end; day++) {
          covered.add(day);
        }
      }
      continue;
    }
    if (token.length == 1 && days.containsKey(token)) covered.add(days[token]!);
  }
  return covered;
}

String _formatBandTime(String raw, String lang) {
  final shown = ServiceLabelI18n.translate(raw, lang).trim();
  final match = RegExp(r'^(\d{1,2}):(\d{2})\s*[-–－~～]\s*(\d{1,2}):(\d{2})$')
      .firstMatch(shown);
  if (match == null) return ServiceLabelI18n.translate(raw, lang);
  String hhmm(String hour, String minute) => '${hour.padLeft(2, '0')}:$minute';
  return '${hhmm(match.group(1)!, match.group(2)!)} - ${hhmm(match.group(3)!, match.group(4)!)}';
}

/// Published route timetable. Gold bus header, a day-type pill that opens on
/// today's section, and one dark card per frequency band. Routes with no
/// bundled bands show the empty-state copy instead of failing.
class TimetableDialog extends StatefulWidget {
  final String route;
  final int direction;

  /// Clock used to choose the initial day type. Defaults to [DateTime.now].
  final DateTime? today;

  const TimetableDialog({
    super.key,
    required this.route,
    required this.direction,
    this.today,
  });

  static Future<void> show(
    BuildContext context, {
    required String route,
    required int direction,
    DateTime? today,
  }) async {
    await DsatTimetable.ensureLoaded();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) =>
          TimetableDialog(route: route, direction: direction, today: today),
    );
  }

  @override
  State<TimetableDialog> createState() => _TimetableDialogState();
}

class _TimetableDialogState extends State<TimetableDialog> {
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = _initialIndex();
  }

  @override
  void didUpdateWidget(TimetableDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route ||
        oldWidget.direction != widget.direction ||
        oldWidget.today != widget.today) {
      _index = _initialIndex();
    }
  }

  int _initialIndex() {
    final sections = DsatTimetable.sectionsFor(widget.route, widget.direction);
    if (sections.isEmpty) return 0;
    return timetableSectionIndexFor(
      sections,
      widget.today ?? DateTime.now(),
    ).clamp(0, sections.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final langCtrl = context.watch<LanguageController>();
    final lang = langCtrl.currentLanguage;
    final sections = DsatTimetable.sectionsFor(widget.route, widget.direction);
    final titleColor = isDark ? Colors.white : Colors.black;
    final selected = sections.isEmpty
        ? 0
        : _index.clamp(0, sections.length - 1);

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      contentPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actionsAlignment: MainAxisAlignment.end,
      title: Row(
        children: [
          Container(
            key: const Key('timetable-bus-ring'),
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _gold, width: 1.6),
            ),
            child: const Icon(Icons.directions_bus, color: _gold, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${widget.route} ${langCtrl.tr('timetable')}',
              style: TextStyle(
                color: titleColor,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: sections.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(30),
                child: Center(
                  child: Text(
                    langCtrl.tr('no_timetable'),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DaySelector(
                      labels: [
                        for (final section in sections)
                          ServiceLabelI18n.translate(section.title, lang),
                      ],
                      selected: selected,
                      isDark: isDark,
                      onSelected: (index) => setState(() => _index = index),
                    ),
                    const SizedBox(height: 14),
                    Flexible(
                      child: SingleChildScrollView(
                        child: _BandList(
                          items: sections[selected].items,
                          lang: lang,
                          serviceLabel: langCtrl.tr('service_hours'),
                          freqLabel: langCtrl.tr('frequency_mins'),
                        ),
                      ),
                    ),
                    if (!EasyReadAccess.enabled(context))
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 10, 0, 4),
                        child: Text(
                          langCtrl.tr('timetable_source_note'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
      actions: [
        FilledButton(
          key: const Key('timetable-close'),
          style: FilledButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: Colors.black,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          onPressed: () => Navigator.pop(context),
          child: Text(langCtrl.tr('btn_close')),
        ),
      ],
    );
  }
}

class _DaySelector extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final bool isDark;
  final ValueChanged<int> onSelected;

  const _DaySelector({
    required this.labels,
    required this.selected,
    required this.isDark,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('timetable-day-selector'),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : const Color(0xFFF6F1DE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _gold, width: 1.2),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) Expanded(child: _segment(i)),
        ],
      ),
    );
  }

  Widget _segment(int index) {
    final on = index == selected;
    return Material(
      key: ValueKey(on ? 'timetable-day-selected' : 'timetable-day-$index'),
      elevation: 0,
      color: on ? _gold : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => onSelected(index),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Center(
            child: Text(
              labels[index],
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: on
                    ? Colors.black
                    : (isDark ? Colors.white70 : Colors.black87),
                fontSize: 12,
                height: 1.25,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BandList extends StatelessWidget {
  final List<DsatFrequencyBand> items;
  final String lang;
  final String serviceLabel;
  final String freqLabel;

  const _BandList({
    required this.items,
    required this.lang,
    required this.serviceLabel,
    required this.freqLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _BandCard(
            key: ValueKey('timetable-band-$i'),
            serviceLabel: serviceLabel,
            time: _formatBandTime(items[i].time, lang),
            freqLabel: freqLabel,
            freq: ServiceLabelI18n.translate(items[i].freq, lang),
          ),
          if (i != items.length - 1)
            Center(
              child: Container(
                key: ValueKey('timetable-connector-$i'),
                width: 1.5,
                height: 12,
                color: _gold,
              ),
            ),
        ],
      ],
    );
  }
}

class _BandCard extends StatelessWidget {
  final String serviceLabel;
  final String time;
  final String freqLabel;
  final String freq;

  const _BandCard({
    super.key,
    required this.serviceLabel,
    required this.time,
    required this.freqLabel,
    required this.freq,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bandColor,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  serviceLabel,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  time,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(Icons.schedule, color: _gold, size: 15),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        freqLabel,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  freq,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
