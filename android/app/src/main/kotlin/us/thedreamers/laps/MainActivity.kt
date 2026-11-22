package us.thedreamers.laps

import android.Manifest.permission.WRITE_SECURE_SETTINGS
import android.content.Intent
import android.content.pm.PackageManager.PERMISSION_GRANTED
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var bell: AudioTrack? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val power = getSystemService(PowerManager::class.java)
        MethodChannel(engine.dartExecutor.binaryMessenger, "laps").setMethodCallHandler { call, result ->
            when (call.method) {
                "bell" -> result.success(ring(call.arguments as ByteArray))
                "canSave" -> result.success(canSave())
                "saver" -> result.success(saver(power, call.arguments as Boolean))
                "unrestrict" -> {
                    if (!power.isIgnoringBatteryOptimizations(packageName)) {
                        startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // 16-bit mono PCM at 44.1 kHz, mixed over any music (no audio focus taken)
    private fun ring(pcm: ByteArray): Boolean {
        bell?.release()
        bell = AudioTrack.Builder()
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
            .setAudioFormat(AudioFormat.Builder().setEncoding(AudioFormat.ENCODING_PCM_16BIT).setSampleRate(44100)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(pcm.size)
            .build()
            .apply { write(pcm, 0, pcm.size); play() }
        return true
    }

    // Battery saver needs WRITE_SECURE_SETTINGS: adb shell pm grant us.thedreamers.laps android.permission.WRITE_SECURE_SETTINGS
    private fun canSave() = checkSelfPermission(WRITE_SECURE_SETTINGS) == PERMISSION_GRANTED

    private fun saver(power: PowerManager, on: Boolean): Boolean {
        if (!canSave() || power.isPowerSaveMode == on) return false
        Settings.Global.putInt(contentResolver, "low_power", if (on) 1 else 0)
        // where battery saver turns GPS off with the screen off, laps would stop counting: undo it
        if (on && Build.VERSION.SDK_INT >= 28) Handler(mainLooper).postDelayed({
            val mode = power.locationPowerSaveMode
            if (mode == PowerManager.LOCATION_MODE_GPS_DISABLED_WHEN_SCREEN_OFF ||
                mode == PowerManager.LOCATION_MODE_ALL_DISABLED_WHEN_SCREEN_OFF) {
                Settings.Global.putInt(contentResolver, "low_power", 0)
            }
        }, 1000)
        return true
    }

    override fun onDestroy() {
        bell?.release()
        super.onDestroy()
    }
}
