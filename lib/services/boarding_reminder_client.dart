import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class BoardingReminderOutcome {
  final bool started;
  final String? messageKey;

  const BoardingReminderOutcome.started()
      : started = true,
        messageKey = null;

  const BoardingReminderOutcome.failed(this.messageKey) : started = false;

  const BoardingReminderOutcome.cleared()
      : started = false,
        messageKey = null;
}

class BoardingReminderResponse {
  final bool ok;
  final String? code;
  final int? minutes;
  final String? text;
  final int? startedAt;
  final bool pushConfigured;

  const BoardingReminderResponse({
    required this.ok,
    this.code,
    this.minutes,
    this.text,
    this.startedAt,
    this.pushConfigured = false,
  });
}

/// One request to our server. The server estimates arrival and sends the
/// Apple push. This client does not call the transport bureau and does not
/// retry on a timer.
class BoardingReminderClient {
  @visibleForTesting
  static Future<BoardingReminderResponse> Function(Map<String, dynamic> body)?
      debugRegister;

  @visibleForTesting
  static Future<void> Function(String reminderId)? debugCancel;

  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  static Future<BoardingReminderResponse> register(Map<String, dynamic> body) async {
    final override = debugRegister;
    if (override != null) return override(body);
    try {
      final res = await http
          .post(
            Uri.parse('${ApiConfig.api}/boarding-reminder'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));
      if (res.body.trimLeft().startsWith('<')) {
        return const BoardingReminderResponse(ok: false, code: 'bad_response');
      }
      final json = jsonDecode(res.body);
      if (json is! Map) {
        return const BoardingReminderResponse(ok: false, code: 'bad_response');
      }
      final map = Map<String, dynamic>.from(json);
      if (map['success'] == true) {
        return BoardingReminderResponse(
          ok: true,
          minutes: _asInt(map['minutes']),
          text: map['text']?.toString(),
          startedAt: _asInt(map['startedAt']),
          pushConfigured: map['pushConfigured'] == true,
        );
      }
      return BoardingReminderResponse(
        ok: false,
        code: map['code']?.toString() ?? 'failed',
      );
    } catch (e) {
      debugPrint('boarding reminder register: $e');
      return const BoardingReminderResponse(ok: false, code: 'failed');
    }
  }

  static Future<void> cancel(String reminderId) async {
    final override = debugCancel;
    if (override != null) {
      await override(reminderId);
      return;
    }
    try {
      await http
          .post(
            Uri.parse('${ApiConfig.api}/boarding-reminder/cancel'),
            headers: _headers,
            body: jsonEncode({'reminderId': reminderId}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('boarding reminder cancel: $e');
    }
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

String boardingServerMessageKey(String? code) {
  switch (code) {
    case 'passed':
      return 'boarding_passed';
    case 'segment_times_missing':
      return 'boarding_segment_missing';
    default:
      return 'boarding_reminder_failed';
  }
}
