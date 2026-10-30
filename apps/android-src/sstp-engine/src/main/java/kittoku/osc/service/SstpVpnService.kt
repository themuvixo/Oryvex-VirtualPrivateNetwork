package kittoku.osc.service

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.documentfile.provider.DocumentFile
import androidx.preference.PreferenceManager
import kittoku.osc.R
import kittoku.osc.SharedBridge
import kittoku.osc.control.Controller
import kittoku.osc.control.LogWriter
import kittoku.osc.preference.OscPrefKey
import kittoku.osc.preference.accessor.getBooleanPrefValue
import kittoku.osc.preference.accessor.getIntPrefValue
import kittoku.osc.preference.accessor.getStringPrefValue
import kittoku.osc.preference.accessor.getURIPrefValue
import kittoku.osc.preference.accessor.resetReconnectionLife
import kittoku.osc.preference.accessor.setBooleanPrefValue
import kittoku.osc.preference.accessor.setIntPrefValue
import kittoku.osc.preference.accessor.setStringPrefValue
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale


internal const val ACTION_VPN_CONNECT = "kittoku.osc.connect"
internal const val ACTION_VPN_DISCONNECT = "kittoku.osc.disconnect"

internal const val NOTIFICATION_ERROR_CHANNEL = "ERROR"
internal const val NOTIFICATION_CRITICAL_CHANNEL = "CRITICAL"
internal const val NOTIFICATION_RECONNECT_CHANNEL = "RECONNECT"
internal const val NOTIFICATION_DISCONNECT_CHANNEL = "DISCONNECT"
internal const val NOTIFICATION_CERTIFICATE_CHANNEL = "CERTIFICATE"

internal const val NOTIFICATION_ERROR_ID = 1
internal const val NOTIFICATION_CRITICAL_ID = 5
internal const val NOTIFICATION_RECONNECT_ID = 2
internal const val NOTIFICATION_DISCONNECT_ID = 3
internal const val NOTIFICATION_CERTIFICATE_ID = 4


open class SstpVpnService : VpnService() {
    interface TrafficListener {
        fun onSstpTrafficUpdated(snapshot: SstpTrafficSnapshot)
    }

    private lateinit var prefs: SharedPreferences
    private lateinit var listener: SharedPreferences.OnSharedPreferenceChangeListener
    private lateinit var notificationManager: NotificationManagerCompat
    internal lateinit var scope: CoroutineScope

    internal var logWriter: LogWriter? = null
    private var controller: Controller? = null
    private var oryvexMode = false
    private var mWasConnected = false
    private var currentConnectedIp = ""
    private var totalInBytes = 0L
    private var totalOutBytes = 0L
    private var lastPublishedInBytes = 0L
    private var lastPublishedOutBytes = 0L
    private var lastPublishedAtMs = 0L

    private var jobReconnect: Job? = null

    companion object {
        private const val STATS_INTERVAL_MS = 1000L
        private const val TRAFFIC_PREFS_SUFFIX = "_preferences"
        private const val DOWNLOADED_DATA_KEY = "downloaded_data"
        private const val UPLOADED_DATA_KEY = "uploaded_data"

        var notificationTargetActivity: Class<*>? = null
        var currentTrafficSnapshot: SstpTrafficSnapshot = SstpTrafficSnapshot.EMPTY
            private set
        var lastTrafficSnapshot: SstpTrafficSnapshot = SstpTrafficSnapshot.EMPTY
            private set
        var mDisplaySpeed: Boolean = true

        private val trafficListeners = mutableListOf<TrafficListener>()
        private val mainHandler = Handler(Looper.getMainLooper())

        fun addTrafficListener(listener: TrafficListener) {
            if (!trafficListeners.contains(listener)) {
                trafficListeners.add(listener)
                listener.onSstpTrafficUpdated(currentTrafficSnapshot)
            }
        }

        fun removeTrafficListener(listener: TrafficListener) {
            trafficListeners.remove(listener)
        }

        private fun notifyTrafficListeners(snapshot: SstpTrafficSnapshot) {
            currentTrafficSnapshot = snapshot
            if (snapshot.inBytes > 0L || snapshot.outBytes > 0L || snapshot.diffInBytes > 0L || snapshot.diffOutBytes > 0L) {
                lastTrafficSnapshot = snapshot
            }
            mainHandler.post {
                trafficListeners.forEach { it.onSstpTrafficUpdated(snapshot) }
            }
        }
    }

    private fun triggerDisconnectNotification() {
        val channelId = NOTIFICATION_CRITICAL_CHANNEL
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                getString(R.string.sstp_channel_name_critical),
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = getString(R.string.sstp_channel_description_critical)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 250, 250, 250)
                
                // Set sound
                val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                setSound(soundUri, AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .build())
            }
            notificationManager.createNotificationChannel(channel)
        }

        var contentPendingIntent: PendingIntent? = null
        if (notificationTargetActivity != null) {
            val intent = Intent(this, notificationTargetActivity!!)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP

            try {
                val startKeyField = notificationTargetActivity!!.getField("TYPE_START")
                val startValueField = notificationTargetActivity!!.getField("TYPE_FROM_NOTIFY")

                val startKey = startKeyField.get(null).toString()
                val startValue = startValueField.get(null).toString().toInt()

                intent.putExtra(startKey, startValue)
            } catch (e: Exception) {
                Log.e("SstpVpnService", "Failed to set notification intent extras via reflection", e)
            }

            contentPendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
            )
        }

        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.notification_title_disconnected))
            .setContentText(getString(R.string.sstp_notification_disconnected_error))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setDefaults(Notification.DEFAULT_ALL)
            .setVibrate(longArrayOf(0, 250, 250, 250))
            .setAutoCancel(true)
        
        if (contentPendingIntent != null) {
            builder.setContentIntent(contentPendingIntent)
        }

        tryNotify(builder.build(), NOTIFICATION_CRITICAL_ID)
    }

    private fun immutableFlag(): Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

    private fun setRootState(state: Boolean) {
        setBooleanPrefValue(state, OscPrefKey.ROOT_STATE, prefs)
    }


    override fun onCreate() {
        notificationManager = NotificationManagerCompat.from(this)
        createNotificationChannels()

        prefs = PreferenceManager.getDefaultSharedPreferences(this)

        listener = SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == OscPrefKey.ROOT_STATE.name) {
                val newState = getBooleanPrefValue(OscPrefKey.ROOT_STATE, prefs)

                setBooleanPrefValue(newState, OscPrefKey.HOME_CONNECTOR, prefs)
            }
            if (key == OscPrefKey.HOME_CONNECTED_IP.name) {
                val connectedIp = getStringPrefValue(OscPrefKey.HOME_CONNECTED_IP, prefs)
                if (connectedIp != "") {
                    mWasConnected = true
                    currentConnectedIp = connectedIp
                    if (oryvexMode) onSstpEngineState(true, connectedIp)
                    else beForegrounded(connectedIp)
                } else {
                    currentConnectedIp = ""
                }
            }
        }

        prefs.registerOnSharedPreferenceChangeListener(listener)

        scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    }

    open override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Always promote to the foreground first. This service is started via
        // startForegroundService(), and the CONNECT branch returns START_STICKY.
        // If the system kills and restarts it, onStartCommand is re-delivered
        // with a null intent, which would fall through to the else branch below
        // WITHOUT calling startForeground(), throwing
        // ForegroundServiceDidNotStartInTimeException. Calling beForegrounded()
        // up front guarantees startForeground() is invoked within the timeout on
        // every delivery (connect, disconnect, or null-intent restart).
        beForegrounded()
        return when (intent?.action) {
            ACTION_VPN_CONNECT -> {
                controller?.kill(false, null)
                mWasConnected = false
                currentConnectedIp = ""
                resetTrafficTracking()

                cancelNotification(NOTIFICATION_ERROR_ID)
                resetReconnectionLife(prefs)
                if (getBooleanPrefValue(OscPrefKey.LOG_DO_SAVE_LOG, prefs)) {
                    prepareLogWriter()
                }

                logWriter?.write("Establish VPN connection")

                initializeClient()

                setRootState(true)

                Service.START_STICKY
            }

            else -> {
                // ensure that reconnection has been completely canceled or done
                runBlocking { jobReconnect?.cancelAndJoin() }

                controller?.disconnect()
                controller = null

                setStringPrefValue("", OscPrefKey.HOME_CONNECTED_IP, prefs)
                currentConnectedIp = ""
                notifyTrafficListeners(SstpTrafficSnapshot.EMPTY)

                close()

                Service.START_NOT_STICKY
            }
        }
    }

    private fun initializeClient() {
        controller = Controller(SharedBridge(this)).also {
            it.launchJobMain()
        }
    }

    /** Runs the protocol engine on the app's one active VpnService instance. */
    fun connectFromOryvex(host: String, port: Int, username: String, password: String) {
        require(host.matches(Regex("(?i)^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+opengw\\.net$"))) {
            "VPN Gate SSTP requires an opengw.net hostname"
        }
        require(port in 1..65535) { "Invalid SSTP port" }
        oryvexMode = true
        controller?.kill(false, null)
        prefs.edit()
            .putString(OscPrefKey.HOME_HOSTNAME.name, host.lowercase())
            .putInt(OscPrefKey.SSL_PORT.name, port)
            .putString(OscPrefKey.HOME_USERNAME.name, username)
            .putString(OscPrefKey.HOME_PASSWORD.name, password)
            .putBoolean(OscPrefKey.SSL_DO_VERIFY.name, true)
            .putBoolean(OscPrefKey.SSL_DO_SPECIFY_CERT.name, false)
            .putBoolean(OscPrefKey.SSL_DO_USE_CUSTOM_SNI.name, false)
            .putStringSet(OscPrefKey.PPP_AUTH_PROTOCOLS.name, setOf("MSCHAPv2"))
            .putBoolean(OscPrefKey.PPP_IPv4_ENABLED.name, true)
            .putBoolean(OscPrefKey.PPP_IPv6_ENABLED.name, true)
            .putBoolean(OscPrefKey.ROUTE_DO_ADD_DEFAULT_ROUTE.name, true)
            .putBoolean(OscPrefKey.ROUTE_DO_ENABLE_APP_BASED_RULE.name, false)
            .putBoolean(OscPrefKey.RECONNECTION_ENABLED.name, false)
            .putString(OscPrefKey.HOME_CONNECTED_IP.name, "")
            .apply()
        resetReconnectionLife(prefs)
        logWriter?.write("Establish VPN Gate SSTP tunnel to $host:$port")
        initializeClient()
        setRootState(true)
    }

    fun disconnectFromOryvex() {
        controller?.disconnect()
    }

    protected open fun onSstpEngineState(connected: Boolean, detail: String?) { }

    private fun prepareLogWriter() {
        val currentDateTime = SimpleDateFormat("yyyyMMddHHmmss", Locale.getDefault()).format(Date())
        val filename = "log_osc_${currentDateTime}.txt"

        val prefURI = getURIPrefValue(OscPrefKey.LOG_DIR, prefs)
        if (prefURI == null) {
            notifyError("LOG: ERR_NULL_PREFERENCE")
            return
        }

        val dirURI = DocumentFile.fromTreeUri(this, prefURI)
        if (dirURI == null) {
            notifyError("LOG: ERR_NULL_DIRECTORY")
            return
        }

        val fileURI = dirURI.createFile("text/plain", filename)
        if (fileURI == null) {
            notifyError("LOG: ERR_NULL_FILE")
            return
        }

        val stream = contentResolver.openOutputStream(fileURI.uri, "wa")
        if (stream == null) {
            notifyError("LOG: ERR_NULL_STREAM")
            return
        }

        logWriter = LogWriter(stream)
    }

    internal fun launchJobReconnect() {
        jobReconnect = scope.launch {
            try {
                getIntPrefValue(OscPrefKey.RECONNECTION_LIFE, prefs).also {
                    val life = it - 1
                    setIntPrefValue(life, OscPrefKey.RECONNECTION_LIFE, prefs)

                    val message = getString(R.string.reconnecting, life)
                    notifyMessage(message, NOTIFICATION_RECONNECT_ID, NOTIFICATION_RECONNECT_CHANNEL)
                    logWriter?.report(message)
                }

                delay(getIntPrefValue(OscPrefKey.RECONNECTION_INTERVAL, prefs) * 1000L)

                initializeClient()
            } catch (_: CancellationException) { }
            finally {
                cancelNotification(NOTIFICATION_RECONNECT_ID)
            }
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val importance = mapOf(
                NOTIFICATION_ERROR_CHANNEL to NotificationManager.IMPORTANCE_DEFAULT,
                NOTIFICATION_CRITICAL_CHANNEL to NotificationManager.IMPORTANCE_HIGH,
                NOTIFICATION_RECONNECT_CHANNEL to NotificationManager.IMPORTANCE_DEFAULT,
                NOTIFICATION_DISCONNECT_CHANNEL to NotificationManager.IMPORTANCE_LOW,
                NOTIFICATION_CERTIFICATE_CHANNEL to NotificationManager.IMPORTANCE_DEFAULT,
            )
            notificationManager.createNotificationChannels(importance.map { (id, level) ->
                NotificationChannel(id, id, level)
            })
        }
    }

    private fun beForegrounded(connectedIp: String = "") {
        createNotificationChannels()

        val disconnectPendingIntent = PendingIntent.getService(
            this,
            0,
            Intent(this, SstpVpnService::class.java).setAction(ACTION_VPN_DISCONNECT),
            PendingIntent.FLAG_ONE_SHOT or immutableFlag()
        )

        var contentPendingIntent: PendingIntent? = null
        if (notificationTargetActivity != null) {
            val intent = Intent(this, notificationTargetActivity!!)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP

            try {
                val startKeyField = notificationTargetActivity!!.getField("TYPE_START")
                val startValueField = notificationTargetActivity!!.getField("TYPE_FROM_NOTIFY")

                val startKey = startKeyField.get(null).toString()
                val startValue = startValueField.get(null).toString().toInt()

                intent.putExtra(startKey, startValue)
            } catch (e: Exception) {
                Log.e("SstpVpnService", "Failed to set notification intent extras via reflection", e)
            }

            contentPendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
            )
        }

        val builder = NotificationCompat.Builder(this, NOTIFICATION_DISCONNECT_CHANNEL).also {
            it.priority = NotificationCompat.PRIORITY_DEFAULT
            it.setAutoCancel(true)
            val serverName = getStringPrefValue(OscPrefKey.HOME_SERVER_NAME, prefs)
                .ifEmpty { getStringPrefValue(OscPrefKey.HOME_HOSTNAME, prefs) }
            it.setContentTitle(getString(R.string.notification_title, serverName))
            if (connectedIp != "") {
                val contentText = if (mDisplaySpeed && currentTrafficSnapshot != SstpTrafficSnapshot.EMPTY) {
                    formatTrafficSnapshot(currentTrafficSnapshot)
                } else {
                    getString(R.string.connected_notification_content, connectedIp)
                }
                it.setContentText(contentText)
            } else {
                it.setContentText(getString(R.string.connecting_notification_content))
            }
            if (contentPendingIntent != null) {
                it.setContentIntent(contentPendingIntent)
            }
            it.setSmallIcon(R.drawable.ic_notification)
            it.addAction(R.drawable.ic_baseline_close_24, getString(R.string.disconnect), disconnectPendingIntent)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIFICATION_DISCONNECT_ID, builder.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_DISCONNECT_ID, builder.build())
        }
    }

    private fun updateForegroundNotification() {
        if (currentConnectedIp.isEmpty()) return
        tryNotify(buildForegroundNotification(currentConnectedIp), NOTIFICATION_DISCONNECT_ID)
    }

    private fun buildForegroundNotification(connectedIp: String): Notification {
        val disconnectPendingIntent = PendingIntent.getService(
            this,
            0,
            Intent(this, SstpVpnService::class.java).setAction(ACTION_VPN_DISCONNECT),
            PendingIntent.FLAG_ONE_SHOT or immutableFlag()
        )

        var contentPendingIntent: PendingIntent? = null
        if (notificationTargetActivity != null) {
            val intent = Intent(this, notificationTargetActivity!!)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP

            try {
                val startKeyField = notificationTargetActivity!!.getField("TYPE_START")
                val startValueField = notificationTargetActivity!!.getField("TYPE_FROM_NOTIFY")

                val startKey = startKeyField.get(null).toString()
                val startValue = startValueField.get(null).toString().toInt()

                intent.putExtra(startKey, startValue)
            } catch (e: Exception) {
                Log.e("SstpVpnService", "Failed to set notification intent extras via reflection", e)
            }

            contentPendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
            )
        }

        return NotificationCompat.Builder(this, NOTIFICATION_DISCONNECT_CHANNEL).also {
            it.priority = NotificationCompat.PRIORITY_DEFAULT
            it.setAutoCancel(true)
            val serverName = getStringPrefValue(OscPrefKey.HOME_SERVER_NAME, prefs)
                .ifEmpty { getStringPrefValue(OscPrefKey.HOME_HOSTNAME, prefs) }
            it.setContentTitle(getString(R.string.notification_title, serverName))
            it.setContentText(
                if (mDisplaySpeed && currentTrafficSnapshot != SstpTrafficSnapshot.EMPTY) {
                    formatTrafficSnapshot(currentTrafficSnapshot)
                } else {
                    getString(R.string.connected_notification_content, connectedIp)
                }
            )
            if (contentPendingIntent != null) {
                it.setContentIntent(contentPendingIntent)
            }
            it.setSmallIcon(R.drawable.ic_notification)
            it.addAction(R.drawable.ic_baseline_close_24, getString(R.string.disconnect), disconnectPendingIntent)
        }.build()
    }

    internal fun notifyMessage(message: String, id: Int, channel: String) {
        NotificationCompat.Builder(this, channel).also {
            it.setSmallIcon(R.drawable.ic_notification)
            it.setContentText(message)
            it.priority = NotificationCompat.PRIORITY_DEFAULT
            it.setAutoCancel(true)

            tryNotify(it.build(), id)
        }
    }

    internal fun notifyError(message: String) {
        if (oryvexMode) onSstpEngineState(false, message)
        if (mWasConnected) {
            triggerDisconnectNotification()
            mWasConnected = false
        }
        notifyMessage(message, NOTIFICATION_ERROR_ID, NOTIFICATION_ERROR_CHANNEL)
    }

    internal fun tryNotify(notification: Notification, id: Int) {
        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            notificationManager.notify(id, notification)
        }
    }

    private fun cancelNotification(id: Int) {
        notificationManager.cancel(id)
    }

    internal fun close() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    open override fun onDestroy() {
        logWriter?.write("Terminate VPN connection")
        logWriter?.close()
        logWriter = null

        controller?.kill(false, null)
        controller = null

        scope.cancel()

        setRootState(false)
        prefs.unregisterOnSharedPreferenceChangeListener(listener)
    }

    @Synchronized
    internal fun recordTraffic(inDeltaBytes: Long = 0L, outDeltaBytes: Long = 0L) {
        if (inDeltaBytes <= 0L && outDeltaBytes <= 0L) return

        val now = System.currentTimeMillis()
        if (lastPublishedAtMs == 0L) {
            lastPublishedAtMs = now
        }

        totalInBytes += inDeltaBytes
        totalOutBytes += outDeltaBytes
        accumulatePersistedTraffic(inDeltaBytes, outDeltaBytes)

        if (currentTrafficSnapshot == SstpTrafficSnapshot.EMPTY || now - lastPublishedAtMs >= STATS_INTERVAL_MS) {
            publishTrafficSnapshot(now)
        }
    }

    @Synchronized
    private fun resetTrafficTracking() {
        totalInBytes = 0L
        totalOutBytes = 0L
        lastPublishedInBytes = 0L
        lastPublishedOutBytes = 0L
        lastPublishedAtMs = 0L
        lastTrafficSnapshot = SstpTrafficSnapshot.EMPTY
        notifyTrafficListeners(SstpTrafficSnapshot.EMPTY)
    }

    @Synchronized
    private fun publishTrafficSnapshot(now: Long = System.currentTimeMillis()) {
        val interval = (now - lastPublishedAtMs).coerceAtLeast(1L)
        val snapshot = SstpTrafficSnapshot(
            inBytes = totalInBytes,
            outBytes = totalOutBytes,
            diffInBytes = (totalInBytes - lastPublishedInBytes).coerceAtLeast(0L),
            diffOutBytes = (totalOutBytes - lastPublishedOutBytes).coerceAtLeast(0L),
            intervalMs = interval,
            timestampMs = now
        )

        lastPublishedInBytes = totalInBytes
        lastPublishedOutBytes = totalOutBytes
        lastPublishedAtMs = now
        notifyTrafficListeners(snapshot)

        if (mDisplaySpeed && currentConnectedIp.isNotEmpty()) {
            updateForegroundNotification()
        }
    }

    private fun formatTrafficSnapshot(snapshot: SstpTrafficSnapshot): String {
        return getString(
            R.string.sstp_statusline_bytecount,
            humanReadableByteCount(snapshot.inBytes, false),
            humanReadableByteCount(snapshot.inBytesPerSecond(), true),
            humanReadableByteCount(snapshot.outBytes, false),
            humanReadableByteCount(snapshot.outBytesPerSecond(), true)
        )
    }

    private fun accumulatePersistedTraffic(downloadedDelta: Long, uploadedDelta: Long) {
        if (downloadedDelta <= 0L && uploadedDelta <= 0L) return
        val prefs = getTrafficPrefs()
        prefs.edit()
            .putLong(DOWNLOADED_DATA_KEY, prefs.getLong(DOWNLOADED_DATA_KEY, 0L) + downloadedDelta)
            .putLong(UPLOADED_DATA_KEY, prefs.getLong(UPLOADED_DATA_KEY, 0L) + uploadedDelta)
            .apply()
    }

    private fun getTrafficPrefs(): SharedPreferences {
        return applicationContext.getSharedPreferences(
            applicationContext.packageName + TRAFFIC_PREFS_SUFFIX,
            Context.MODE_PRIVATE
        )
    }

    private fun humanReadableByteCount(bytes: Long, speed: Boolean): String {
        val value = if (speed) bytes * 8.0 else bytes.toDouble()
        val unit = if (speed) 1000.0 else 1024.0
        val units = if (speed) {
            arrayOf("bit/s", "kbit/s", "Mbit/s", "Gbit/s")
        } else {
            arrayOf("B", "KB", "MB", "GB")
        }
        if (value <= 0.0) {
            return if (speed) "0 bit/s" else "0 B"
        }
        val exp = kotlin.math.min((kotlin.math.ln(value) / kotlin.math.ln(unit)).toInt(), units.lastIndex)
        val scaled = value / Math.pow(unit, exp.toDouble())
        return String.format(java.util.Locale.US, "%.1f %s", scaled, units[exp])
    }
}
