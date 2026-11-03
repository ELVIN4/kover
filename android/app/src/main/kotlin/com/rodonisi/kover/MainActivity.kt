package com.rodonisi.kover

import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var volumeKeySink: EventChannel.EventSink? = null
    private val capturedKeyCodes = mutableSetOf<Int>()

    private val volumeKeyChannel = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            volumeKeySink = events
        }

        override fun onCancel(arguments: Any?) {
            volumeKeySink = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "kover/app_icon").setMethodCallHandler { call, result ->
            val aliases = mapOf("default" to "LauncherDefault", "blue" to "LauncherBlue", "amber" to "LauncherAmber")
            fun component(alias: String) = ComponentName(this, "$packageName.$alias")
            when (call.method) {
                "getIcon" -> {
                    val selected = aliases.entries.firstOrNull { (key, alias) ->
                        val state = packageManager.getComponentEnabledSetting(component(alias))
                        state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                            (key == "default" && state == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT)
                    }?.key ?: "default"
                    result.success(selected)
                }
                "setIcon" -> {
                    val key = call.arguments as? String
                    val target = key?.let { aliases[it] }
                    if (target == null) {
                        result.error("invalid_icon", "Unknown icon", null)
                    } else {
                        val previous = aliases.values.associateWith {
                            packageManager.getComponentEnabledSetting(component(it))
                        }
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                                packageManager.setComponentEnabledSettings(aliases.values.map { alias ->
                                    PackageManager.ComponentEnabledSetting(component(alias),
                                        if (alias == target) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                                        else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                        PackageManager.DONT_KILL_APP)
                                })
                            } else {
                                // Keep a launcher entry available throughout the legacy update.
                                packageManager.setComponentEnabledSetting(component(target),
                                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
                                aliases.values.filter { it != target }.forEach { alias ->
                                    packageManager.setComponentEnabledSetting(component(alias),
                                        PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
                                }
                            }
                            result.success(null)
                        } catch (_: Exception) {
                            previous.forEach { (alias, state) ->
                                runCatching {
                                    packageManager.setComponentEnabledSetting(component(alias), state,
                                        PackageManager.DONT_KILL_APP)
                                }
                            }
                            result.error("icon_failed", "Could not update launcher icon", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "kover/volume_keys").setStreamHandler(volumeKeyChannel)
        MethodChannel(messenger, "kover/volume_key_capture").setMethodCallHandler { call, result ->
            when (call.method) {
                "setCapturedKeys" -> {
                    capturedKeyCodes.clear()
                    (call.arguments as? List<*>)?.filterIsInstance<Int>()
                        ?.let(capturedKeyCodes::addAll)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode in capturedKeyCodes && volumeKeySink != null) {
            volumeKeySink?.success(keyCode)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }
}
