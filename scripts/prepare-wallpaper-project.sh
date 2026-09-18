#!/usr/bin/env bash
set -euo pipefail

# Generate the complete wallpaper controls and repair known vector resources.
mkdir -p app/src/main/java/com/poco/wallpaper

mkdir -p app/src/main/java/com/poco/wallpaper

cat > app/src/main/java/com/poco/wallpaper/WallpaperControlsActivity.kt <<'KOTLIN'
package com.poco.wallpaper

import android.app.Activity
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.view.Gravity
import android.widget.Button
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.Switch
import android.widget.TextView
import android.widget.Toast

class WallpaperControlsActivity : Activity() {
    private val prefs by lazy { getSharedPreferences("wallpaper", MODE_PRIVATE) }
    private val component by lazy { ComponentName(this, PocoLiveWallpaperService::class.java) }

    override fun onCreate(savedInstanceState: Bundle?) {
        setTheme(android.R.style.Theme_Material_Light_NoActionBar)
        super.onCreate(savedInstanceState)
        window.setBackgroundDrawableResource(android.R.color.white)
        showMain()
    }

    private fun showMain() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(40, 48, 40, 40)
        }
        val title = TextView(this).apply {
            text = "POCO Live Wallpaper Engine"
            textSize = 25f
            gravity = Gravity.CENTER
        }
        val status = TextView(this).apply {
            text = currentMediaText()
            textSize = 16f
            setPadding(0, 24, 0, 24)
        }
        val video = Button(this).apply {
            text = "Choose Video"
            setOnClickListener { choose("video/*", 10) }
        }
        val photo = Button(this).apply {
            text = "Choose Photo"
            setOnClickListener { choose("image/*", 11) }
        }
        val settings = Button(this).apply {
            text = "Settings"
            setOnClickListener { showSettings() }
        }
        val apply = Button(this).apply {
            text = "Apply Live Wallpaper"
            setOnClickListener { openWallpaperPicker() }
        }
        val kill = Button(this).apply {
            text = if (prefs.getBoolean("kill_switch", false)) "Restart Wallpaper Engine" else "Kill Switch"
            setOnClickListener {
                if (prefs.getBoolean("kill_switch", false)) restartEngine()
                else killEngine()
            }
        }
        root.addView(title)
        root.addView(status)
        root.addView(video)
        root.addView(photo)
        root.addView(settings)
        root.addView(apply)
        root.addView(kill)
        setContentView(root)
    }

    private fun currentMediaText(): String {
        val uri = prefs.getString("media_uri", null)
        return if (uri == null) "No media selected" else "Selected: " + if (prefs.getString("media_type", "video") == "image") "Photo" else "Video"
    }

    private fun choose(type: String, request: Int) {
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            this.type = type
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf(type.removeSuffix("/*") + "/*"))
        }, request)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK || data?.data == null) return
        val uri = data.data!!
        try { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) {}
        val isImage = requestCode == 11
        prefs.edit()
            .putString("media_uri", uri.toString())
            .putString("media_type", if (isImage) "image" else "video")
            .putBoolean("kill_switch", false)
            .apply()
        Toast.makeText(this, "Media selected — open Apply to set it", Toast.LENGTH_SHORT).show()
        openWallpaperPicker()
    }

    private fun showSettings() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(40, 48, 40, 40)
        }
        val title = TextView(this).apply { text = "Settings"; textSize = 25f }
        val gyro = Switch(this).apply {
            text = "Gyro Parallax"
            isChecked = prefs.getBoolean("gyro_enabled", true)
        }
        val label = TextView(this).apply {
            text = "Gyro sensitivity: ${prefs.getInt("gyro_sensitivity", 50)}%"
            textSize = 16f
        }
        val seek = SeekBar(this).apply {
            max = 100
            progress = prefs.getInt("gyro_sensitivity", 50)
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: SeekBar?, p: Int, fromUser: Boolean) { label.text = "Gyro sensitivity: $p%" }
                override fun onStartTrackingTouch(s: SeekBar?) {}
                override fun onStopTrackingTouch(s: SeekBar?) {}
            })
        }
        val save = Button(this).apply {
            text = "Save"
            setOnClickListener {
                prefs.edit().putBoolean("gyro_enabled", gyro.isChecked).putInt("gyro_sensitivity", seek.progress).apply()
                showMain()
            }
        }
        root.addView(title); root.addView(gyro); root.addView(label); root.addView(seek); root.addView(save)
        setContentView(root)
    }

    private fun openWallpaperPicker() {
        startActivity(Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).apply {
            putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, component)
        })
    }

    private fun killEngine() {
        prefs.edit().putBoolean("kill_switch", true).apply()
        try { WallpaperManager.getInstance(this).clear() } catch (_: Exception) {}
        finishAndRemoveTask()
    }

    private fun restartEngine() {
        prefs.edit().putBoolean("kill_switch", false).apply()
        Toast.makeText(this, "Wallpaper engine enabled", Toast.LENGTH_SHORT).show()
        openWallpaperPicker()
    }
}
KOTLIN

cat > app/src/main/java/com/poco/wallpaper/SettingsActivity.kt <<'KOTLIN'
package com.poco.wallpaper
import android.app.Activity
class SettingsActivity : Activity()
KOTLIN

cat > app/src/main/java/com/poco/wallpaper/PocoLiveWallpaperService.kt <<'KOTLIN'
package com.poco.wallpaper

import android.graphics.*
import android.hardware.*
import android.net.Uri
import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer

class PocoLiveWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = PocoEngine()

    inner class PocoEngine : Engine(), SensorEventListener {
        private val prefs get() = getSharedPreferences("wallpaper", MODE_PRIVATE)
        private var player: ExoPlayer? = null
        private var bitmap: Bitmap? = null
        private var holderRef: SurfaceHolder? = null
        private var sensors: SensorManager? = null
        private var sensor: Sensor? = null
        private var offsetX = 0f
        private var offsetY = 0f

        override fun onSurfaceCreated(holder: SurfaceHolder) {
            super.onSurfaceCreated(holder)
            holderRef = holder
            if (!prefs.getBoolean("kill_switch", false)) loadMedia(holder)
            registerSensors()
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            unregisterSensors()
            releasePlayer()
            bitmap?.recycle()
            bitmap = null
            holderRef = null
            super.onSurfaceDestroyed(holder)
        }

        override fun onVisibilityChanged(visible: Boolean) {
            if (visible) {
                if (!prefs.getBoolean("kill_switch", false)) player?.play()
                registerSensors()
            } else {
                player?.pause()
                unregisterSensors()
            }
        }

        private fun loadMedia(holder: SurfaceHolder) {
            val value = prefs.getString("media_uri", null) ?: return
            val uri = Uri.parse(value)
            if (prefs.getString("media_type", "video") == "image") {
                bitmap = try {
                    contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) }
                } catch (_: Exception) { null }
                drawImage()
            } else {
                player = ExoPlayer.Builder(this@PocoLiveWallpaperService).build().apply {
                    setMediaItem(MediaItem.fromUri(uri))
                    repeatMode = Player.REPEAT_MODE_ONE
                    volume = 0f
                    setVideoSurfaceHolder(holder)
                    prepare()
                    playWhenReady = true
                }
            }
        }

        private fun releasePlayer() {
            player?.clearVideoSurface()
            player?.release()
            player = null
        }

        private fun registerSensors() {
            if (!prefs.getBoolean("gyro_enabled", true)) return
            sensors = getSystemService(SENSOR_SERVICE) as SensorManager
            sensor = sensors?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            sensor?.let { sensors?.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
        }

        private fun unregisterSensors() {
            sensors?.unregisterListener(this)
            sensors = null
        }

        override fun onSensorChanged(event: SensorEvent) {
            val matrix = FloatArray(9)
            SensorManager.getRotationMatrixFromVector(matrix, event.values)
            val sensitivity = prefs.getInt("gyro_sensitivity", 50) / 100f
            val tx = matrix[2].coerceIn(-1f, 1f) * -55f * sensitivity
            val ty = matrix[5].coerceIn(-1f, 1f) * -55f * sensitivity
            offsetX += (tx - offsetX) * 0.10f
            offsetY += (ty - offsetY) * 0.10f
            if (player == null) drawImage()
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

        private fun drawImage() {
            val b = bitmap ?: return
            val h = holderRef ?: return
            val canvas = try { h.lockCanvas() } catch (_: Exception) { null } ?: return
            try {
                canvas.drawColor(Color.BLACK)
                val scale = maxOf(canvas.width.toFloat() / b.width, canvas.height.toFloat() / b.height)
                val w = b.width * scale
                val ht = b.height * scale
                val left = (canvas.width - w) / 2f + offsetX
                val top = (canvas.height - ht) / 2f + offsetY
                canvas.drawBitmap(b, null, RectF(left, top, left + w, top + ht), Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
            } finally {
                h.unlockCanvasAndPost(canvas)
            }
        }
    }
}
KOTLIN

python3 - <<'PY'
from pathlib import Path
import re
manifest = Path("app/src/main/AndroidManifest.xml")
text = manifest.read_text()
if "android.permission.READ_MEDIA_IMAGES" not in text:
    text = text.replace("<manifest", '<manifest')
activity = '''
    <activity android:name=".WallpaperControlsActivity" android:exported="true" android:label="POCO Live Wallpaper Engine">
        <intent-filter>
            <action android:name="android.intent.action.MAIN"/>
            <category android:name="android.intent.category.LAUNCHER"/>
        </intent-filter>
    </activity>
    <activity android:name=".SettingsActivity" android:exported="false" android:label="Settings"/>
'''
if "WallpaperControlsActivity" not in text:
    text = text.replace("</application>", activity + "\n    </application>")
manifest.write_text(text)

gradle = Path("app/build.gradle.kts")
if gradle.exists():
    g = gradle.read_text()
    if "androidx.media3:media3-exoplayer" not in g:
        g = g.replace("dependencies {", 'dependencies {\n    implementation("androidx.media3:media3-exoplayer:1.11.1")', 1)
        gradle.write_text(g)
PY



python3 - <<'PY'
from pathlib import Path
import re
replacements = {
    "ic_launcher.xml": '<path android:fillColor="#FF000000" android:pathData="M82,18 C86.418,18 90,21.582 90,26 C90,30.418 86.418,34 82,34 C77.582,34 74,30.418 74,26 C74,21.582 77.582,18 77.582,18 Z"/>',
    "preview_thumbnail.xml": '<path android:fillColor="#FF000000" android:pathData="M201,38 C212.046,38 221,46.954 221,58 C221,69.046 212.046,78 201,78 C189.954,78 181,69.046 181,58 C181,46.954 189.954,38 189.954,38 Z"/>'
}
for name, replacement in replacements.items():
    p = Path("app/src/main/res/drawable") / name
    if p.exists():
        t = p.read_text()
        if "<circle" in t:
            t = re.sub(r'<circle[^>]*/>', replacement, t)
            p.write_text(t)
PY


