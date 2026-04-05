package com.example.campusmytra

import android.content.ComponentName
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.campusmytra/app_icon"

    private val allAliases = listOf(
        "Default", "Christmas", "Diwali", "Holi",
        "NewYear2027", "NewYear2028", "NewYear2029", "NewYear2030", "NewYear2031",
        "Rakhi", "RamNavami", "Spring", "Summers", "Winters"
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "changeIcon" -> {
                        val iconName = call.argument<String>("iconName") ?: "Default"
                        changeAppIcon(iconName, result)
                    }
                    "getCurrentIcon" -> {
                        result.success(getCurrentIcon())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun changeAppIcon(iconName: String, result: MethodChannel.Result) {
        try {
            allAliases.forEach { alias ->
                val component = ComponentName(packageName, "$packageName.MainActivityIcon$alias")
                val state = if (alias == iconName)
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                else
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                packageManager.setComponentEnabledSetting(
                    component, state, PackageManager.DONT_KILL_APP
                )
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("CHANGE_ICON_FAILED", e.message, null)
        }
    }

    private fun getCurrentIcon(): String {
        allAliases.forEach { alias ->
            val component = ComponentName(packageName, "$packageName.MainActivityIcon$alias")
            val state = packageManager.getComponentEnabledSetting(component)
            if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) {
                return alias
            }
        }
        return "Default"
    }
}
