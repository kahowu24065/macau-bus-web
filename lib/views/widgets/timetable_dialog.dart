import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/language_controller.dart';
import '../../services/dsat_timetable.dart';
import '../../utils/service_label_i18n.dart';

/// Published route timetable. Dark modal (the app default), green column
/// headers, and DSAT frequency bands. Routes with no bundled bands show the
/// empty-state copy instead of failing.
class TimetableDialog extends StatelessWidget {
  final String route;
  final int direction;

  const TimetableDialog({
    super.key,
    required this.route,
    required this.direction,
  });

  static Future<void> show(
    BuildContext context, {
    required String route,
    required int direction,
  }) async {
    await DsatTimetable.ensureLoaded();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => TimetableDialog(route: route, direction: direction),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final langCtrl = context.watch<LanguageController>();
    final lang = langCtrl.currentLanguage;
    final sections = DsatTimetable.sectionsFor(route, direction);
    final titleColor = isDark ? Colors.white : Colors.black;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      contentPadding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          const Icon(Icons.schedule, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$route ${langCtrl.tr('timetable')}',
              style: TextStyle(color: titleColor, fontWeight: FontWeight.bold, fontSize: 18),
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
                  child: Text(langCtrl.tr('no_timetable'), style: const TextStyle(color: Colors.grey)),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    color: Colors.green[700],
                    child: Row(
                      children: [
                        Expanded(child: Center(child: Text(langCtrl.tr('service_hours'), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)))),
                        Expanded(child: Center(child: Text(langCtrl.tr('frequency_mins'), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)))),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final sec in sections)
                            _section(
                              ServiceLabelI18n.translate(sec.title, lang),
                              sec.items,
                              isDark,
                              lang,
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Text(
                      langCtrl.tr('timetable_source_note'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 11, height: 1.35),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(langCtrl.tr('btn_close'), style: const TextStyle(color: Colors.amber)),
        ),
      ],
    );
  }

  Widget _section(String title, List<DsatFrequencyBand> items, bool isDark, String lang) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[300],
          child: Text(
            title,
            textAlign: TextAlign.center,
            softWrap: true,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              height: 1.35,
            ),
          ),
        ),
        for (var i = 0; i < items.length; i++)
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              border: i == items.length - 1
                  ? null
                  : Border(bottom: BorderSide(color: isDark ? const Color(0xFF333333) : Colors.grey.shade300)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      ServiceLabelI18n.translate(items[i].time, lang),
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      ServiceLabelI18n.translate(items[i].freq, lang),
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
