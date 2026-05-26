import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import '../domain/timetable_models.dart';
import 'ical_session_parser.dart';

class IcsImportService {
  /// .ics 파일 선택 → ClassSession 목록 반환.
  /// 취소 시 null 반환, 오류 시 예외 throw.
  static Future<List<ClassSession>?> pickAndParse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['ics'],
      allowMultiple: false,
      withData: true, // 바이트를 즉시 읽음 (경로 의존 없이 모든 플랫폼 호환)
    );
    if (result == null || result.files.isEmpty) return null;

    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('파일을 읽을 수 없습니다.');
    }

    // UTF-8 디코딩 (한국어 과목명/장소 보존). 실패 시 Latin-1 폴백.
    String text;
    try {
      text = utf8.decode(bytes);
    } catch (_) {
      try {
        text = latin1.decode(bytes);
      } catch (_) {
        throw const FormatException('파일 인코딩을 읽을 수 없습니다.');
      }
    }

    if (!text.contains('BEGIN:VCALENDAR')) {
      throw const FormatException('유효한 ICS(iCalendar) 파일이 아닙니다.');
    }

    final sessions = IcalSessionParser.parse(text);
    debugPrint('[IcsImport] 파싱 결과: ${sessions.length}개 수업');
    return sessions;
  }
}
