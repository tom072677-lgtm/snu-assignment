package com.tom07.sharap

import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.tom07.sharap/settings"
    private val BOMB_CHANNEL = "com.tom07.sharap/bomb"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openChannelSettings" -> {
                        val channelId = call.argument<String>("channelId") ?: ""
                        val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
                        }
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BOMB_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startBomb" -> {
                        val intent = Intent(this, BombService::class.java).apply {
                            action = BombService.ACTION_START
                            putExtra("courseName", call.argument<String>("courseName") ?: "")
                            putExtra("title", call.argument<String>("title") ?: "")
                            putExtra("deadlineMillis", call.argument<Long>("deadlineMillis") ?: 0L)
                            putExtra("regularId", call.argument<Int>("regularId") ?: 0)
                        }
                        try {
                            ContextCompat.startForegroundService(this, intent)
                            result.success(true)
                        } catch (e: Exception) {
                            // 백그라운드 시작 제한(ForegroundServiceStartNotAllowedException) 등 → Dart가 폴백
                            android.util.Log.w("BombService", "startForegroundService 실패: ${e.message}")
                            result.success(false)
                        }
                    }
                    "stopBomb" -> {
                        val intent = Intent(this, BombService::class.java).apply {
                            action = BombService.ACTION_STOP
                        }
                        try {
                            startService(intent)
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
