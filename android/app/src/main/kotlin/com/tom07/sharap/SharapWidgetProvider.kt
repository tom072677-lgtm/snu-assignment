package com.tom07.sharap

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import android.app.PendingIntent
import android.content.Intent
import org.json.JSONArray

class SharapWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    private fun badge(dueDateIso: String): String {
        return try {
            // Dart의 toIso8601String()은 밀리초 포함 가능: "2026-05-24T12:00:00.000Z"
            val pattern = if (dueDateIso.contains('.')) "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
                          else "yyyy-MM-dd'T'HH:mm:ss'Z'"
            val sdf = java.text.SimpleDateFormat(pattern, java.util.Locale.US)
            sdf.timeZone = java.util.TimeZone.getTimeZone("UTC")
            val due = sdf.parse(dueDateIso) ?: return ""
            val totalMins = (due.time - System.currentTimeMillis()) / 60_000
            when {
                totalMins <= 0      -> "만료"
                totalMins < 60      -> "${totalMins}분"
                totalMins < 24 * 60 -> "${totalMins / 60}h"
                else                -> "D-${totalMins / (24 * 60)}"
            }
        } catch (e: Exception) { "" }
    }

    private fun updateAppWidget(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int
    ) {
        val prefs: SharedPreferences =
            context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)

        val assignmentsJson = prefs.getString("widget_assignments", null)
        val views = RemoteViews(context.packageName, R.layout.home_widget)

        // 앱 열기 인텐트
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        if (intent != null) {
            val pendingIntent = PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_header, pendingIntent)
        }

        if (assignmentsJson == null) {
            views.setTextViewText(R.id.widget_title1, "앱을 열어 과제를 불러오세요")
            views.setViewVisibility(R.id.widget_badge1, View.GONE)
            views.setViewVisibility(R.id.widget_row2, View.GONE)
            views.setTextViewText(R.id.widget_updated, "미연동")
        } else {
            try {
                val arr = JSONArray(assignmentsJson)
                if (arr.length() == 0) {
                    views.setTextViewText(R.id.widget_title1, "마감 예정 과제 없음 🎉")
                    views.setViewVisibility(R.id.widget_badge1, View.GONE)
                    views.setViewVisibility(R.id.widget_row2, View.GONE)
                } else {
                    // 첫 번째 과제 — badge 런타임 계산
                    val a1 = arr.getJSONObject(0)
                    val badge1 = badge(a1.optString("dueDate", ""))
                    views.setViewVisibility(R.id.widget_badge1, if (badge1.isNotEmpty()) View.VISIBLE else View.GONE)
                    views.setTextViewText(R.id.widget_badge1, badge1)
                    views.setTextViewText(
                        R.id.widget_title1,
                        "${a1.optString("course", "")}  ${a1.optString("title", "")}"
                    )

                    // 두 번째 과제
                    if (arr.length() >= 2) {
                        val a2 = arr.getJSONObject(1)
                        val badge2 = badge(a2.optString("dueDate", ""))
                        views.setViewVisibility(R.id.widget_row2, View.VISIBLE)
                        views.setTextViewText(R.id.widget_badge2, badge2)
                        views.setTextViewText(
                            R.id.widget_title2,
                            "${a2.optString("course", "")}  ${a2.optString("title", "")}"
                        )
                    } else {
                        views.setViewVisibility(R.id.widget_row2, View.GONE)
                    }
                }

                val now = java.text.SimpleDateFormat("HH:mm", java.util.Locale.KOREA)
                    .format(java.util.Date())
                views.setTextViewText(R.id.widget_updated, "$now 기준")
            } catch (e: Exception) {
                views.setTextViewText(R.id.widget_title1, "데이터 오류")
                views.setViewVisibility(R.id.widget_badge1, View.GONE)
                views.setViewVisibility(R.id.widget_row2, View.GONE)
            }
        }

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }
}
