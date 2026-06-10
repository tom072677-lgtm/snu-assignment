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
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat

/**
 * 마감 임박 과제를 위한 포그라운드 서비스.
 * Android 14+에서는 일반 ongoing 알림이 스와이프로 지워지므로,
 * 포그라운드 서비스 알림으로 띄워 사용자가 밀어서 지울 수 없게 한다.
 * (단, 설정 > 강제 종료로는 종료 가능 — 이는 OS 정책상 불가피)
 */
class BombService : Service() {

    companion object {
        const val ACTION_START = "com.tom07.sharap.BOMB_START"
        const val ACTION_STOP = "com.tom07.sharap.BOMB_STOP"
        const val FGS_NOTIF_ID = 990001
        const val CHANNEL_ID = "sharap_ongoing"
        const val CHANNEL_NAME = "샤랍 마감 임박 알림"
    }

    private val handler = Handler(Looper.getMainLooper())
    private var stopRunnable: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopBomb()
            return START_NOT_STICKY
        }

        val courseName = intent?.getStringExtra("courseName") ?: ""
        val title = intent?.getStringExtra("title") ?: ""
        val deadlineMillis = intent?.getLongExtra("deadlineMillis", 0L) ?: 0L
        val regularId = intent?.getIntExtra("regularId", 0) ?: 0

        // 이미 마감 → 서비스 종료
        if (deadlineMillis <= System.currentTimeMillis()) {
            stopBomb()
            return START_NOT_STICKY
        }

        ensureChannel()
        val notif = buildNotification(courseName, title, deadlineMillis)

        try {
            val type = if (Build.VERSION.SDK_INT >= 34) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            } else {
                0
            }
            ServiceCompat.startForeground(this, FGS_NOTIF_ID, notif, type)
            // FGS 성공 → 기존 일반(밀어서 지워지는) 알림 제거, FGS 알림이 대체
            if (regularId != 0) {
                NotificationManagerCompat.from(this).cancel(regularId)
            }
        } catch (e: Exception) {
            // FGS 시작 실패 → 최후 폴백으로 일반 알림 발송 후 종료 (알림 없는 상태 방지)
            if (regularId != 0) {
                try {
                    NotificationManagerCompat.from(this).notify(regularId, notif)
                } catch (_: Exception) {
                }
            }
            stopSelf()
            return START_NOT_STICKY
        }

        scheduleStop(deadlineMillis)
        return START_REDELIVER_INTENT
    }

    /** 마감 시각에 서비스 자동 종료 예약 */
    private fun scheduleStop(deadlineMillis: Long) {
        stopRunnable?.let { handler.removeCallbacks(it) }
        val delay = deadlineMillis - System.currentTimeMillis()
        if (delay <= 0) {
            stopBomb()
            return
        }
        val r = Runnable { stopBomb() }
        stopRunnable = r
        handler.postDelayed(r, delay)
    }

    private fun stopBomb() {
        stopRunnable?.let { handler.removeCallbacks(it) }
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        stopRunnable?.let { handler.removeCallbacks(it) }
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

    private fun buildNotification(
        courseName: String,
        title: String,
        deadlineMillis: Long,
    ): Notification {
        val displayTitle = "💣 " + if (courseName.isNotEmpty()) courseName else title
        val launch = packageManager.getLaunchIntentForPackage(packageName) ?: Intent()
        val contentPi = PendingIntent.getActivity(
            this, 0, launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_bomb)
            .setColor(0xFFD32F2F.toInt())
            .setColorized(true)
            .setContentTitle(displayTitle)
            .setContentText(title)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setAutoCancel(false)
            .setShowWhen(true)
            .setWhen(deadlineMillis)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setContentIntent(contentPi)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .build()
    }
}
