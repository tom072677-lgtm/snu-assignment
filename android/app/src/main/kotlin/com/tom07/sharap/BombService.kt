package com.tom07.sharap

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat

/**
 * 마감 임박 과제를 위한 포그라운드 서비스.
 * Android 13+에서는 OS 정책상 FGS 알림도 사용자가 스와이프로 지울 수 있으므로,
 * 지워지면(deleteIntent) 즉시 다시 띄워 사실상 못 지우게 한다.
 * 진행바를 1분마다 갱신해 앱 내 폭탄 배너처럼 24시간(왼쪽)→0시간(오른쪽)으로 채워지게 한다.
 * (설정>강제 종료로는 종료 가능 — OS 정책)
 */
class BombService : Service() {

    companion object {
        const val ACTION_START = "com.tom07.sharap.BOMB_START"
        const val ACTION_STOP = "com.tom07.sharap.BOMB_STOP"
        const val ACTION_REASSERT = "com.tom07.sharap.BOMB_REASSERT"
        const val FGS_NOTIF_ID = 990001
        const val CHANNEL_ID = "sharap_ongoing"
        const val CHANNEL_NAME = "샤랍 마감 임박 알림"
        const val WINDOW_MS = 24L * 3600L * 1000L // 진행바 기준 윈도우 (24시간)
        const val UPDATE_INTERVAL_MS = 60_000L // 1분마다 진행바 갱신
        const val PROGRESS_MAX = 1000
    }

    private val handler = Handler(Looper.getMainLooper())
    private var updateRunnable: Runnable? = null

    private var courseName = ""
    private var title = ""
    private var deadlineMillis = 0L
    private var regularId = 0
    private var stopping = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopBomb()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_REASSERT) {
            // 사용자가 스와이프로 지웠을 때 즉시 다시 표시
            if (!stopping && deadlineMillis > System.currentTimeMillis()) {
                reShow()
            }
            return START_REDELIVER_INTENT
        }

        stopping = false
        courseName = intent?.getStringExtra("courseName") ?: ""
        title = intent?.getStringExtra("title") ?: ""
        deadlineMillis = intent?.getLongExtra("deadlineMillis", 0L) ?: 0L
        regularId = intent?.getIntExtra("regularId", 0) ?: 0

        // 이미 마감 → 종료
        if (deadlineMillis <= System.currentTimeMillis()) {
            stopBomb()
            return START_NOT_STICKY
        }

        ensureChannel()
        try {
            val type = if (Build.VERSION.SDK_INT >= 34) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            } else {
                0
            }
            ServiceCompat.startForeground(this, FGS_NOTIF_ID, buildNotification(), type)
            // FGS 성공 → 기존 일반(밀어서 지워지는) 알림 제거
            if (regularId != 0) {
                NotificationManagerCompat.from(this).cancel(regularId)
            }
        } catch (e: Exception) {
            // FGS 시작 실패 → 최후 폴백으로 일반 알림 발송 후 종료 (알림 없는 상태 방지)
            if (regularId != 0) {
                try {
                    NotificationManagerCompat.from(this).notify(regularId, buildNotification())
                } catch (_: Exception) {
                }
            }
            stopSelf()
            return START_NOT_STICKY
        }

        startUpdates()
        return START_REDELIVER_INTENT
    }

    /** 1분마다 진행바를 갱신해 24h→0h로 채워지게 한다. 마감 시각이 되면 종료. */
    private fun startUpdates() {
        updateRunnable?.let { handler.removeCallbacks(it) }
        val r = object : Runnable {
            override fun run() {
                if (deadlineMillis <= System.currentTimeMillis()) {
                    stopBomb()
                    return
                }
                try {
                    NotificationManagerCompat.from(this@BombService)
                        .notify(FGS_NOTIF_ID, buildNotification())
                } catch (_: Exception) {
                }
                handler.postDelayed(this, UPDATE_INTERVAL_MS)
            }
        }
        updateRunnable = r
        handler.postDelayed(r, UPDATE_INTERVAL_MS)
    }

    /** 스와이프로 지워졌을 때 알림을 즉시 다시 띄운다. */
    private fun reShow() {
        try {
            val type = if (Build.VERSION.SDK_INT >= 34) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            } else {
                0
            }
            ServiceCompat.startForeground(this, FGS_NOTIF_ID, buildNotification(), type)
        } catch (_: Exception) {
        }
    }

    private fun stopBomb() {
        stopping = true
        updateRunnable?.let { handler.removeCallbacks(it) }
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        updateRunnable?.let { handler.removeCallbacks(it) }
        super.onDestroy()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
                ).apply { description = "24시간 이내 마감 과제 고정 알림" }
                mgr.createNotificationChannel(ch)
            }
        }
    }

    private fun buildNotification(): Notification {
        val label = if (courseName.isNotEmpty()) "💣 $courseName  ·  $title" else "💣 $title"
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: Intent()
        val contentPi = PendingIntent.getActivity(
            this, 0, launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        // 스와이프로 지우면(deleteIntent) 서비스가 즉시 다시 띄운다
        val reassertPi = PendingIntent.getService(
            this, 1,
            Intent(this, BombService::class.java).setAction(ACTION_REASSERT),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

        // 진행: 24시간 남으면 0%(왼쪽), 마감이면 100%(오른쪽)
        val remaining = (deadlineMillis - System.currentTimeMillis()).coerceAtLeast(0L)
        val elapsed = (WINDOW_MS - remaining).coerceIn(0L, WINDOW_MS)
        val progress = (elapsed * PROGRESS_MAX / WINDOW_MS).toInt()
        // 평소 주황 그라데이션, 마감 1시간 이내면 빨강 그라데이션 (왼쪽 어둡고 오른쪽 밝음)
        val gradientRes = if (remaining < 3_600_000L) {
            R.drawable.bomb_gradient_red
        } else {
            R.drawable.bomb_gradient
        }
        // 카드 전체를 덮을 기본색 = 그라데이션 시작색 (헤더까지 같은 색으로 채움)
        val baseColor = if (remaining < 3_600_000L) 0xFFB71C1C.toInt() else 0xFFE65100.toInt()

        // 커스텀 레이아웃 — 그라데이션 배경 + 카운트다운 + 진행바 (앱 내 배너와 동일한 느낌)
        val rv = RemoteViews(packageName, R.layout.bomb_notification)
        rv.setInt(R.id.bomb_root, "setBackgroundResource", gradientRes)
        rv.setTextViewText(R.id.bomb_title, label)
        rv.setChronometer(
            R.id.bomb_chrono, SystemClock.elapsedRealtime() + remaining, null, true,
        )
        rv.setChronometerCountDown(R.id.bomb_chrono, true)
        rv.setProgressBar(R.id.bomb_progress, PROGRESS_MAX, progress, false)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_bomb)
            .setColorized(true)
            .setColor(baseColor)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setAutoCancel(false)
            .setContentIntent(contentPi)
            .setDeleteIntent(reassertPi)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setCustomContentView(rv)
            .setCustomBigContentView(rv)
            .build()
    }
}
