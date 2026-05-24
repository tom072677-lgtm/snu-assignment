import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import '../features/assignments/domain/assignment.dart';

class WidgetService {
  static const _appGroupId = 'com.tom07.sharap';

  /// eTL 연동 해제 시 호출 — 위젯을 "미연동" 상태로 초기화
  static Future<void> clearWidget() async {
    try {
      await HomeWidget.saveWidgetData<String?>('widget_assignments', null);
      await HomeWidget.saveWidgetData<String?>('widget_count', null);
      await HomeWidget.updateWidget(
        androidName: 'SharapWidgetProvider',
        qualifiedAndroidName: '$_appGroupId.SharapWidgetProvider',
      );
    } catch (e) {
      debugPrint('[Widget] 초기화 실패: $e');
    }
  }

  static Future<void> updateWidget(
    List<Assignment> assignments, {
    Set<String> completedIds = const {},
  }) async {
    try {
      // 미완료 + 미만료 과제 중 마감 임박순 2개
      final upcoming = assignments
          .where((a) => !a.isOverdue && !completedIds.contains(a.etlId))
          .toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

      // badge는 Kotlin에서 런타임 계산 (시간 경과 반영) — dueDate ISO 저장
      final items = upcoming.take(2).map((a) => {
        'title': a.title,
        'course': a.courseName,
        'dueDate': a.dueDate.toUtc().toIso8601String(),
      }).toList();

      await HomeWidget.saveWidgetData<String>(
          'widget_assignments', jsonEncode(items));
      await HomeWidget.saveWidgetData<String>(
          'widget_count', '${upcoming.length}');
      await HomeWidget.updateWidget(
        androidName: 'SharapWidgetProvider',
        qualifiedAndroidName: '$_appGroupId.SharapWidgetProvider',
      );
    } catch (e) {
      debugPrint('[Widget] 업데이트 실패: $e');
    }
  }
}
