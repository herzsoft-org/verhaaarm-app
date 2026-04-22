package moe.herz.verhaaarm

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
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
                        } catch (_: Exception) {
                            // Silent path failed immediately -> fall back to the old installer flow.
                            try {
                                installApk(path)
                                result.success(true)
                            } catch (e2: Exception) {
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

        if (intent.action == ACTION_INSTALL_COMMIT) {
            handleInstallCommitResult(intent)
        }
    }

    private fun canInstallUnknownApps(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
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

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                setPackageSource(PackageInstaller.PACKAGE_SOURCE_STORE)
            }
        }

        val sessionId = packageInstaller.createSession(params)
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
        } catch (e: Exception) {
            try {
                session?.abandon()
            } catch (_: Exception) {
            }
            throw e
        } finally {
            try {
                session?.close()
            } catch (_: Exception) {
            }
        }
    }

    private fun handleInstallCommitResult(intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE
        )
        val apkPath = intent.getStringExtra(EXTRA_APK_PATH)

        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmIntent = getParcelableIntentExtra(intent, Intent.EXTRA_INTENT)
                if (confirmIntent != null) {
                    confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(confirmIntent)
                } else if (!apkPath.isNullOrBlank()) {
                    // Missing confirmation intent for some reason -> fall back.
                    installApk(apkPath)
                }
            }

            PackageInstaller.STATUS_SUCCESS -> {
                // Nothing to do.
            }

            else -> {
                // Silent path did not complete -> fall back to the normal installer flow.
                if (!apkPath.isNullOrBlank()) {
                    try {
                        installApk(apkPath)
                    } catch (_: Exception) {
                        // Intentionally ignore to keep this path quiet.
                    }
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