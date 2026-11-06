package com.example.mcri_residents_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.graphics.Color
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createAlertsChannel()
    }

    /**
     * High-importance channel so pushes drop down as heads-up banners (like
     * WhatsApp) instead of arriving silently in the shade. The API only
     * targets this channel for devices that registered with
     * alerts_channel=true, i.e. builds that run this code.
     */
    private fun createAlertsChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(ALERTS_CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            ALERTS_CHANNEL_ID,
            "Messages & alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Chat messages, announcements, polls and request updates"
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 180, 90, 180)
            enableLights(true)
            lightColor = Color.parseColor("#F97316")
            lockscreenVisibility = android.app.Notification.VISIBILITY_PRIVATE
            setShowBadge(true)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION_COMMUNICATION_INSTANT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
        manager.createNotificationChannel(channel)
    }

    companion object {
        const val ALERTS_CHANNEL_ID = "mcri_alerts"
    }
}
