package uz.savdoyordam.savdoyordam

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingContent: String? = null
    private val exportRequest = 4102
    private var permissionResult: MethodChannel.Result? = null
    private val permissionRequest = 4103

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uz.savdoyordam/notifications")
            .setMethodCallHandler { call, result ->
                val manager = getSystemService(NotificationManager::class.java)
                when (call.method) {
                    "request" -> {
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            if (permissionResult != null) result.success(false) else {
                                permissionResult = result
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), permissionRequest)
                            }
                        } else result.success(manager.areNotificationsEnabled())
                    }
                    "pushToken" -> {
                        val project = getString(R.string.savdo_firebase_project)
                        val app = getString(R.string.savdo_firebase_app)
                        val key = getString(R.string.savdo_firebase_key)
                        val sender = getString(R.string.savdo_firebase_sender)
                        if (project.isEmpty() || app.isEmpty() || key.isEmpty() || sender.isEmpty()) result.success(null)
                        else {
                            if (FirebaseApp.getApps(this).isEmpty()) FirebaseApp.initializeApp(this, FirebaseOptions.Builder().setProjectId(project).setApplicationId(app).setApiKey(key).setGcmSenderId(sender).build())
                            getSharedPreferences("push", MODE_PRIVATE).edit().putBoolean("enabled", true).apply()
                            FirebaseMessaging.getInstance().isAutoInitEnabled = true
                            FirebaseMessaging.getInstance().token.addOnSuccessListener { result.success(it) }.addOnFailureListener { result.error("push_unavailable", "Could not register push token", null) }
                        }
                    }
                    "clear" -> { manager.cancel(1); result.success(null) }
                    "cancel" -> {
                        manager.cancel(1)
                        getSharedPreferences("push", MODE_PRIVATE).edit().putBoolean("enabled", false).apply()
                        if (FirebaseApp.getApps(this).isNotEmpty()) { FirebaseMessaging.getInstance().isAutoInitEnabled = false; FirebaseMessaging.getInstance().deleteToken() }
                        result.success(null)
                    }
                    "show" -> {
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            result.success(null)
                        } else {
                            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel("stock_alerts", "SavdoYordam", NotificationManager.IMPORTANCE_DEFAULT))
                            val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "stock_alerts") else Notification.Builder(this)
                            manager.notify(1, builder.setSmallIcon(uz.savdoyordam.savdoyordam.R.drawable.ic_notification).setContentTitle(call.argument<String>("title")).setContentText(call.argument<String>("body")).setContentIntent(open).setAutoCancel(true).build())
                            result.success(null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "uz.savdoyordam/files")
            .setMethodCallHandler { call, result ->
                if (call.method != "save") {
                    result.notImplemented()
                } else if (pendingResult != null) {
                    result.error("busy", "An export is already open", null)
                } else {
                    val content = call.argument<String>("content")
                    val name = call.argument<String>("name")
                    val mime = call.argument<String>("mime")
                    if (content == null || name == null || content.length > 20_000_000) {
                        result.error("invalid_export", "Export is missing or too large", null)
                    } else {
                        pendingResult = result
                        pendingContent = content
                        try {
                            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = mime ?: "application/json"
                                putExtra(Intent.EXTRA_TITLE, name)
                            }
                            startActivityForResult(intent, exportRequest)
                        } catch (error: Exception) {
                            pendingResult = null
                            pendingContent = null
                            result.error("export_failed", "Could not open document picker", null)
                        }
                    }
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequest) {
            permissionResult?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            permissionResult = null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != exportRequest) return
        val result = pendingResult ?: return
        val content = pendingContent
        pendingResult = null
        pendingContent = null
        if (resultCode != Activity.RESULT_OK || data?.data == null || content == null) {
            result.success(false)
            return
        }
        try {
            val stream = contentResolver.openOutputStream(data.data!!, "wt")
                ?: throw IllegalStateException("No output stream")
            stream.use { it.write(content.toByteArray(Charsets.UTF_8)) }
            result.success(true)
        } catch (error: Exception) {
            result.error("export_failed", "Could not save document", null)
        }
    }
}
