#!/usr/bin/env bash
set -euo pipefail

mkdir -p app/src/main/java/com/poco/wallpaper
mkdir -p app/src/main/res/xml

cat > app/src/main/java/com/poco/wallpaper/WallpaperControlsActivity.kt <<'KOTLIN'
package com.poco.wallpaper

import android.app.Activity
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.Gravity
import android.widget.*
import java.io.File
import java.io.FileOutputStream

class WallpaperControlsActivity : Activity() {
    private val prefs by lazy { getSharedPreferences("wallpaper", MODE_PRIVATE) }
    private val component by lazy { ComponentName(this, PocoLiveWallpaperService::class.java) }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setTheme(android.R.style.Theme_Material_NoActionBar)
        showMain()
    }

    private fun showMain() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(40, 48, 40, 40)
        }
        root.addView(TextView(this).apply {
            text = "POCO Live Wallpaper Engine"
            textSize = 25f
            gravity = Gravity.CENTER
        })
        root.addView(TextView(this).apply {
            text = currentMediaText()
            textSize = 16f
            setPadding(0, 24, 0, 24)
        })
        root.addView(Button(this).apply { text = "Choose Video"; setOnClickListener { choose("video/*", 10) } })
        root.addView(Button(this).apply { text = "Choose Photo"; setOnClickListener { choose("image/*", 11) } })
        root.addView(Button(this).apply { text = "Save Selected Media"; setOnClickListener { saveSelectedMedia() } })
        root.addView(Button(this).apply { text = "Settings"; setOnClickListener { showSettings() } })
        root.addView(Button(this).apply { text = "Play as Background"; setOnClickListener { applyWallpaper() } })
        root.addView(Button(this).apply {
            text = if (prefs.getBoolean("kill_switch", false)) "Enable Wallpaper Engine" else "Kill Switch"
            setOnClickListener { toggleKillSwitch() }
        })
        setContentView(root)
    }

    private fun currentMediaText(): String = when (prefs.getString("media_type", null)) {
        "image" -> "Photo ready"
        "video" -> "Video ready"
        else -> "No media selected"
    }

    private fun choose(type: String, request: Int) {
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            this.type = type
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }, request)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK) return
        val uri = data?.data ?: return
        try { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) {}
        val isImage = requestCode == 11
        val target = File(filesDir, if (isImage) "selected_image" else "selected_video")
        try {
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(target).use { output -> input.copyTo(output) }
            } ?: throw Exception("Cannot open media")
            val old = if (isImage) File(filesDir, "selected_video") else File(filesDir, "selected_image")
            if (old.exists()) old.delete()
            prefs.edit()
                .putString("media_uri", uri.toString())
                .putString("media_path", target.absolutePath)
                .putString("media_type", if (isImage) "image" else "video")
                .putBoolean("kill_switch", false)
                .apply()
            Toast.makeText(this, "Media selected", Toast.LENGTH_SHORT).show()
            showMain()
        } catch (_: Exception) {
            Toast.makeText(this, "Could not read that file", Toast.LENGTH_LONG).show()
        }
    }

    private fun saveSelectedMedia() {
        val path = prefs.getString("media_path", null)?.let(::File)
        val type = prefs.getString("media_type", null)
        if (path == null || type == null || !path.exists()) {
            Toast.makeText(this, "Choose a photo or video first", Toast.LENGTH_SHORT).show(); return
        }
        val image = type == "image"
        val mime = if (image) "image/jpeg" else "video/mp4"
        val name = if (image) "POCO_Wallpaper.jpg" else "POCO_Wallpaper.mp4"
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            if (Build.VERSION.SDK_INT >= 29) put(
                MediaStore.MediaColumns.RELATIVE_PATH,
                if (image) Environment.DIRECTORY_PICTURES + "/POCO Live Wallpaper"
                else Environment.DIRECTORY_MOVIES + "/POCO Live Wallpaper"
            )
        }
        try {
            val collection = if (image) MediaStore.Images.Media.EXTERNAL_CONTENT_URI else MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            val out = contentResolver.insert(collection, values) ?: throw Exception("MediaStore insert failed")
            try {
                contentResolver.openOutputStream(out)?.use { output -> path.inputStream().use { it.copyTo(output) } }
                    ?: throw Exception("Output stream unavailable")
            } catch (e: Exception) {
                contentResolver.delete(out, null, null)
                throw e
            }
            Toast.makeText(this, "Saved to Gallery", Toast.LENGTH_SHORT).show()
        } catch (_: Exception) {
            Toast.makeText(this, "Could not save media", Toast.LENGTH_LONG).show()
        }
    }

    private fun applyWallpaper() {
        if (prefs.getString("media_path", null) == null) {
            Toast.makeText(this, "Choose a photo or video first", Toast.LENGTH_SHORT).show(); return
        }
        prefs.edit().putBoolean("kill_switch", false).apply()
        try {
            startActivity(Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, component))
        } catch (_: Exception) {
            try { startActivity(Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER)) }
            catch (_: Exception) { Toast.makeText(this, "Live wallpaper picker is not available", Toast.LENGTH_LONG).show() }
        }
    }

    private fun toggleKillSwitch() {
        val enabled = !prefs.getBoolean("kill_switch", false)
        prefs.edit().putBoolean("kill_switch", enabled).apply()
        Toast.makeText(this, if (enabled) "Wallpaper engine stopped" else "Wallpaper engine enabled", Toast.LENGTH_SHORT).show()
        if (!enabled) applyWallpaper() else showMain()
    }

    private fun showSettings() {
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(40, 48, 40, 40) }
        val title = TextView(this).apply { text = "Settings"; textSize = 25f }
        val gyro = Switch(this).apply { text = "Gyro Parallax"; isChecked = prefs.getBoolean("gyro_enabled", true) }
        val label = TextView(this).apply { text = "Gyro sensitivity: ${prefs.getInt("gyro_sensitivity", 50)}%"; textSize = 16f }
        val seek = SeekBar(this).apply {
            max = 100; progress = prefs.getInt("gyro_sensitivity", 50)
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: SeekBar?, p: Int, fromUser: Boolean) { label.text = "Gyro sensitivity: $p%" }
                override fun onStartTrackingTouch(s: SeekBar?) {}
                override fun onStopTrackingTouch(s: SeekBar?) {}
            })
        }
        root.addView(title); root.addView(gyro); root.addView(label); root.addView(seek)
        root.addView(Button(this).apply {
            text = "Save"
            setOnClickListener {
                prefs.edit().putBoolean("gyro_enabled", gyro.isChecked).putInt("gyro_sensitivity", seek.progress).apply(); showMain()
            }
        })
        setContentView(root)
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

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import java.io.File

class PocoLiveWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = PocoEngine()

    inner class PocoEngine : Engine(), SensorEventListener {
        private val prefs get() = getSharedPreferences("wallpaper", MODE_PRIVATE)
        private var player: ExoPlayer? = null
        private var bitmap: Bitmap? = null
        private var holderRef: SurfaceHolder? = null
        private var sensors: SensorManager? = null
        private var offsetX = 0f
        private var offsetY = 0f

        override fun onSurfaceCreated(holder: SurfaceHolder) {
            super.onSurfaceCreated(holder)
            holderRef = holder
            if (!prefs.getBoolean("kill_switch", false)) loadMedia(holder)
            registerSensors()
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            if (player == null) drawImage()
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            unregisterSensors(); releasePlayer(); bitmap?.recycle(); bitmap = null; holderRef = null
            super.onSurfaceDestroyed(holder)
        }

        override fun onVisibilityChanged(visible: Boolean) {
            if (visible) {
                if (prefs.getBoolean("kill_switch", false)) { releasePlayer(); return }
                if (player == null && bitmap == null) holderRef?.let { loadMedia(it) } else player?.play()
                registerSensors()
            } else {
                player?.pause(); unregisterSensors()
            }
        }

        private fun loadMedia(holder: SurfaceHolder) {
            releasePlayer(); bitmap?.recycle(); bitmap = null
            val path = prefs.getString("media_path", null)?.let(::File) ?: return
            val type = prefs.getString("media_type", null) ?: return
            if (!path.exists()) return
            if (type == "image") {
                bitmap = try { BitmapFactory.decodeFile(path.absolutePath) } catch (_: Exception) { null }
                drawImage()
            } else {
                player = try {
                    ExoPlayer.Builder(this@PocoLiveWallpaperService).build().apply {
                        setMediaItem(MediaItem.fromUri(path.toURI().toString()))
                        repeatMode = Player.REPEAT_MODE_ONE
                        volume = 0f
                        setVideoSurfaceHolder(holder)
                        prepare()
                        playWhenReady = true
                    }
                } catch (_: Exception) { null }
            }
        }

        private fun releasePlayer() {
            player?.clearVideoSurface(); player?.release(); player = null
        }

        private fun registerSensors() {
            if (!prefs.getBoolean("gyro_enabled", true) || sensors != null) return
            sensors = getSystemService(SENSOR_SERVICE) as SensorManager
            sensors?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)?.let {
                sensors?.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
            }
        }

        private fun unregisterSensors() { sensors?.unregisterListener(this); sensors = null }

        override fun onSensorChanged(event: SensorEvent) {
            val matrix = FloatArray(9)
            SensorManager.getRotationMatrixFromVector(matrix, event.values)
            val sensitivity = prefs.getInt("gyro_sensitivity", 50) / 100f
            val tx = matrix[2].coerceIn(-1f, 1f) * -55f * sensitivity
            val ty = matrix[5].coerceIn(-1f, 1f) * -55f * sensitivity
            offsetX += (tx - offsetX) * 0.10f; offsetY += (ty - offsetY) * 0.10f
            if (player == null) drawImage()
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

        private fun drawImage() {
            val b = bitmap ?: return
            val h = holderRef ?: return
            val canvas: Canvas = try { h.lockCanvas() } catch (_: Exception) { null } ?: return
            try {
                canvas.drawColor(Color.BLACK)
                val scale = maxOf(canvas.width.toFloat() / b.width, canvas.height.toFloat() / b.height)
                val w = b.width * scale; val ht = b.height * scale
                val left = (canvas.width - w) / 2f + offsetX; val top = (canvas.height - ht) / 2f + offsetY
                canvas.drawBitmap(b, null, RectF(left, top, left + w, top + ht), Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG))
            } finally { h.unlockCanvasAndPost(canvas) }
        }
    }
}
KOTLIN

cat > app/src/main/res/xml/wallpaper.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<wallpaper xmlns:android="http://schemas.android.com/apk/res/android"
    android:description="@string/app_name" />
XML

cat > app/src/main/AndroidManifest.xml <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-feature android:name="android.software.live_wallpaper" android:required="false" />
    <application android:label="POCO Live Wallpaper Engine" android:theme="@android:style/Theme.Material.NoActionBar">
        <activity android:name=".WallpaperControlsActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
        <service android:name=".PocoLiveWallpaperService" android:exported="true" android:permission="android.permission.BIND_WALLPAPER">
            <intent-filter><action android:name="android.service.wallpaper.WallpaperService" /></intent-filter>
            <meta-data android:name="android.service.wallpaper" android:resource="@xml/wallpaper" />
        </service>
    </application>
</manifest>
XML

python3 - <<'PY'
from pathlib import Path
p=Path('app/build.gradle.kts')
s=p.read_text()
if 'androidx.media3:media3-exoplayer' not in s:
    s=s.replace('dependencies {', 'dependencies {\n    implementation("androidx.media3:media3-exoplayer:1.11.1")', 1)
p.write_text(s)
PY

python3 - <<'PY'
from pathlib import Path
import re
replacements = {
    "ic_launcher.xml": '<path android:fillColor="#FF000000" android:pathData="M82,18 C86.418,18 90,21.582 90,26 C90,30.418 86.418,34 82,34 C77.582,34 74,30.418 74,26 C74,21.582 77.582,18 82,18 Z"/>',
    "preview_thumbnail.xml": '<path android:fillColor="#FF000000" android:pathData="M201,38 C212.046,38 221,46.954 221,58 C221,69.046 212.046,78 201,78 C189.954,78 181,69.046 181,58 C181,46.954 189.954,38 201,38 Z"/>'
}
for name, replacement in replacements.items():
    p = Path("app/src/main/res/drawable") / name
    if p.exists():
        t = p.read_text()
        if "<circle" in t:
            p.write_text(re.sub(r'<circle[^>]*/>', replacement, t))
PY
