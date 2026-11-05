package uz.savdoyordam.savdoyordam

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class SavdoMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        // The authenticated application registers the current token on resume.
        getSharedPreferences("push", MODE_PRIVATE).edit().putString("token", token).apply()
    }
    override fun onMessageReceived(message: RemoteMessage) {
        if (!getSharedPreferences("push", MODE_PRIVATE).getBoolean("enabled", false)) return
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("stock_alerts", "SavdoYordam", NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "stock_alerts") else Notification.Builder(this)
        manager.notify(1, builder.setSmallIcon(R.drawable.ic_notification).setContentTitle(message.data["title"] ?: "SavdoYordam").setContentText(message.data["body"] ?: "").setContentIntent(open).setAutoCancel(true).build())
    }
}
