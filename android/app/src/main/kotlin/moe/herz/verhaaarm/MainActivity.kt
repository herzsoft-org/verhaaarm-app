package moe.herz.verhaaarm

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

class MainActivity : FlutterActivity() {
    private val channelName = "verhaaarm.ota"

    companion object {
        private const val ACTION_INSTALL_COMMIT =
            "moe.herz.verhaaarm.ACTION_INSTALL_COMMIT"

        private const val EXTRA_APK_PATH = "apk_path"
        private const val EXTRA_SESSION_ID = "session_id"
        private const val TAG = "VerhaaarmInstaller"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleInstallCommitIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstallUnknownApps" -> {
                        result.success(canInstallUnknownApps())
                    }

                    "openUnknownAppsSettings" -> {
                        openUnknownAppsSettings()
                        result.success(true)
                    }

                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("BAD_ARGS", "path missing", null)
                            return@setMethodCallHandler
                        }
                        try {
                            installApk(path)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.toString(), null)
                        }
                    }

                    "installApkPreferSilent" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("BAD_ARGS", "path missing", null)
                            return@setMethodCallHandler
                        }
                        try {
                            installApkPreferSilent(path)
                            result.success(true)
                        } catch (e: Exception) {
                            // Silent path failed immediately -> fall back to the old installer flow.
                            Log.e(TAG, "Session install failed before commit; using legacy installer", e)
                            try {
                                installApk(path)
                                result.success(true)
                            } catch (e2: Exception) {
                                Log.e(TAG, "Legacy installer fallback also failed", e2)
                                result.error("INSTALL_FAILED", e2.toString(), null)
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleInstallCommitIntent(intent)
    }

    private fun canInstallUnknownApps(): Boolean {
        val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
        Log.i(TAG, "Unknown-app install permission allowed=$allowed sdk=${Build.VERSION.SDK_INT}")
        return allowed
    }

    private fun openUnknownAppsSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        }
    }

    private fun installApk(filePath: String) {
        val file = File(filePath)
        Log.i(TAG, "Launching legacy installer for ${file.name} (${file.length()} bytes)")
        val uri = FileProvider.getUriForFile(
            this,
            "$packageName.fileprovider",
            file
        )

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        startActivity(intent)
    }

    private fun installApkPreferSilent(filePath: String) {
        val apkFile = File(filePath)
        require(apkFile.exists()) { "APK file does not exist: $filePath" }

        val packageInstaller = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
            setAppPackageName(packageName)
            setSize(apkFile.length())

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                setInstallReason(PackageManager.INSTALL_REASON_USER)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                setPackageSource(PackageInstaller.PACKAGE_SOURCE_STORE)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                setRequestUpdateOwnership(true)
            }
        }

        val sessionId = packageInstaller.createSession(params)
        Log.i(
            TAG,
            "Created install session id=$sessionId file=${apkFile.name} " +
                "size=${apkFile.length()} sdk=${Build.VERSION.SDK_INT} " +
                "userActionNotRequired=${Build.VERSION.SDK_INT >= Build.VERSION_CODES.S} " +
                "requestUpdateOwnership=${Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE}"
        )
        var session: PackageInstaller.Session? = null

        try {
            session = packageInstaller.openSession(sessionId)

            FileInputStream(apkFile).use { input ->
                session.openWrite("base.apk", 0, apkFile.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }

            val callbackIntent = Intent(this, MainActivity::class.java).apply {
                action = ACTION_INSTALL_COMMIT
                putExtra(EXTRA_APK_PATH, filePath)
                putExtra(EXTRA_SESSION_ID, sessionId)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }

            val pendingFlags = when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ->
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                else ->
                    PendingIntent.FLAG_UPDATE_CURRENT
            }

            val pendingIntent = PendingIntent.getActivity(
                this,
                sessionId,
                callbackIntent,
                pendingFlags
            )

            session.commit(pendingIntent.intentSender)
            Log.i(TAG, "Committed install session id=$sessionId")
        } catch (e: Exception) {
            Log.e(TAG, "Install session id=$sessionId failed", e)
            try {
                session?.abandon()
            } catch (abandonError: Exception) {
                Log.w(TAG, "Could not abandon failed install session id=$sessionId", abandonError)
            }
            throw e
        } finally {
            try {
                session?.close()
            } catch (closeError: Exception) {
                Log.w(TAG, "Could not close install session id=$sessionId", closeError)
            }
        }
    }

    private fun handleInstallCommitIntent(intent: Intent?) {
        if (intent?.action != ACTION_INSTALL_COMMIT) return

        // Avoid processing the same PackageInstaller callback again after recreation.
        intent.action = null
        handleInstallCommitResult(intent)
    }

    private fun handleInstallCommitResult(intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE
        )
        val apkPath = intent.getStringExtra(EXTRA_APK_PATH)
        val sessionId = intent.getIntExtra(EXTRA_SESSION_ID, -1)
        val statusMessage = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)

        Log.i(
            TAG,
            "Install session result id=$sessionId status=$status " +
                "message=${statusMessage ?: "<none>"}"
        )

        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmIntent = getParcelableIntentExtra(intent, Intent.EXTRA_INTENT)
                if (confirmIntent != null) {
                    Log.i(TAG, "Session id=$sessionId requires user action; opening confirmation")
                    confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(confirmIntent)
                } else if (!apkPath.isNullOrBlank()) {
                    // Missing confirmation intent for some reason -> fall back.
                    Log.w(TAG, "Session id=$sessionId requires user action but supplied no confirmation intent; using legacy installer")
                    installApk(apkPath)
                } else {
                    Log.e(TAG, "Session id=$sessionId requires user action but supplied neither confirmation intent nor APK path")
                }
            }

            PackageInstaller.STATUS_SUCCESS -> {
                Log.i(TAG, "Install session id=$sessionId completed successfully")
            }

            else -> {
                // Silent path did not complete -> fall back to the normal installer flow.
                if (!apkPath.isNullOrBlank()) {
                    Log.w(TAG, "Install session id=$sessionId failed with status=$status; using legacy installer")
                    try {
                        installApk(apkPath)
                    } catch (fallbackError: Exception) {
                        Log.e(TAG, "Legacy installer fallback failed for session id=$sessionId", fallbackError)
                    }
                } else {
                    Log.e(TAG, "Install session id=$sessionId failed with status=$status and no APK path is available for fallback")
                }
            }
        }
    }

    private fun getParcelableIntentExtra(intent: Intent, key: String): Intent? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(key, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(key) as? Intent
        }
    }
}
