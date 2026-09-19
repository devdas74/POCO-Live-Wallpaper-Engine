#!/usr/bin/env bash
set -euo pipefail
cat > app/src/main/java/com/poco/wallpaper/WallpaperControlsActivity.kt <<'KOTLIN'
package com.poco.wallpaper

import android.app.Activity
import android.app.WallpaperManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Intent
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.Gravity
import android.view.View
import android.widget.*
import java.io.File
import java.io.FileOutputStream

class WallpaperControlsActivity : Activity() {
    private val prefs by lazy { getSharedPreferences("wallpaper", MODE_PRIVATE) }
    private val component by lazy { ComponentName(this, PocoLiveWallpaperService::class.java) }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()
    private fun bg(c: Int, r: Float = 20f) = GradientDrawable().apply { setColor(c); cornerRadius = dp(r.toInt()).toFloat() }
    private fun label(s: String, z: Float, c: Int = Color.WHITE, b: Boolean = false) =
        TextView(this).apply { text = s; textSize = z; setTextColor(c); typeface = if (b) Typeface.DEFAULT_BOLD else Typeface.DEFAULT }

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        setTheme(android.R.style.Theme_Material_NoActionBar)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        showMain()
    }

    private fun section(s: String) = label(s.uppercase(), 11f, Color.rgb(145,145,154), true).apply {
        letterSpacing = .08f
        setPadding(dp(3), dp(22), dp(3), dp(9))
    }

    private fun row(title: String, sub: String, glyph: String, click: () -> Unit) = LinearLayout(this).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
        minimumHeight = dp(72)
        setPadding(dp(15), dp(10), dp(14), dp(10))
        background = bg(Color.rgb(29,29,33), 20f)
        isClickable = true
        setOnClickListener { click() }

        addView(TextView(this@WallpaperControlsActivity).apply {
            text = glyph; textSize = 18f; gravity = Gravity.CENTER; setTextColor(Color.WHITE); background = bg(Color.rgb(47,47,53), 15f)
        }, LinearLayout.LayoutParams(dp(44), dp(44)).apply { marginEnd = dp(14) })

        addView(LinearLayout(this@WallpaperControlsActivity).apply {
            orientation = LinearLayout.VERTICAL
            addView(label(title, 15.5f, Color.WHITE, true))
            addView(label(sub, 12f, Color.rgb(150,150,158)).apply { setPadding(0, dp(4), 0, 0) })
        }, LinearLayout.LayoutParams(0, -2, 1f))
        addView(label("›", 27f, Color.rgb(140,140,148)))
    }

    private fun mainButton(s: String, click: () -> Unit) = label(s, 15f, Color.WHITE, true).apply {
        gravity = Gravity.CENTER
        minimumHeight = dp(56)
        background = bg(Color.rgb(78,78,86), 20f)
        isClickable = true
        setOnClickListener { click() }
    }

    private fun showMain() {
        val scroll = ScrollView(this).apply { setBackgroundColor(Color.rgb(11,11,13)) }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(22), dp(54), dp(22), dp(28))
        }
        scroll.addView(root)

        root.addView(label("POCO Live Wallpaper", 29f, Color.WHITE, true))
        root.addView(label("Make your screen move.", 14f, Color.rgb(158,158,166)).apply { setPadding(0, dp(6), 0, dp(20)) })

        val type = prefs.getString("media_type", null)
        val media = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(17), dp(18), dp(17))
            background = bg(Color.rgb(23,23,27), 24f)
        }
        media.addView(label(when(type) { "image" -> "PHOTO READY"; "video" -> "VIDEO READY"; else -> "NO MEDIA SELECTED" }, 10.5f, Color.rgb(165,165,173), true))
        media.addView(label(when(type) { "image" -> "Photo wallpaper"; "video" -> "Video wallpaper"; else -> "Nothing selected" }, 20f, Color.WHITE, true).apply { setPadding(0, dp(7), 0, dp(3)) })
        media.addView(label(if (type == null) "Choose a photo or video to get started." else "Media is stored locally and ready.", 12f, Color.rgb(148,148,156)))
        root.addView(media)

        root.addView(section("Media"))
        root.addView(row("Choose Photo", "Use an image as your wallpaper", "▣") { choose("image/*", 11) })
        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(8)))
        root.addView(row("Choose Video", "Use a looping video", "▶") { choose("video/*", 10) })
        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(8)))
        root.addView(row("Save Selected Media", "Copy it to your Gallery", "↓") { saveSelectedMedia() })

        root.addView(section("Motion"))
        val motion = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(18), dp(15), dp(18), dp(14))
            background = bg(Color.rgb(23,23,27), 22f)
        }
        val gyro = Switch(this).apply {
            text = "Gyro Parallax"; textSize = 16f; setTextColor(Color.WHITE); isChecked = prefs.getBoolean("gyro_enabled", true)
            setOnCheckedChangeListener { _, checked -> prefs.edit().putBoolean("gyro_enabled", checked).apply() }
        }
        motion.addView(gyro)
        motion.addView(label("Sensitivity  " + prefs.getInt("gyro_sensitivity", 50) + "%", 12f, Color.rgb(160,160,168)))
        val seek = SeekBar(this).apply {
            max = 100; progress = prefs.getInt("gyro_sensitivity", 50)
            setOnSeekBarChangeListener(object: SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: SeekBar?, p: Int, fromUser: Boolean) { prefs.edit().putInt("gyro_sensitivity", p).apply() }
                override fun onStartTrackingTouch(s: SeekBar?) {}
                override fun onStopTrackingTouch(s: SeekBar?) {}
            })
        }
        motion.addView(seek)
        root.addView(motion)

        root.addView(section("Engine"))
        root.addView(mainButton("Play as Background") { applyWallpaper() })
        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(10)))
        root.addView(row("Settings", "Fine-tune motion controls", "⚙") { showSettings() })
        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(8)))
        val killed = prefs.getBoolean("kill_switch", false)
        root.addView(row(if(killed) "Enable Wallpaper Engine" else "Kill Switch",
            if(killed) "Wallpaper engine is stopped" else "Immediately stop the active engine",
            if(killed) "▶" else "■") { toggleKillSwitch() })
        setContentView(scroll)
    }

    private fun choose(type: String, request: Int) {
        startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE); this.type = type
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }, request)
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (resultCode != RESULT_OK) return
        val uri = data?.data ?: return
        try { contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) } catch (_: Exception) {}
        val image = requestCode == 11
        val target = File(filesDir, if(image) "selected_image" else "selected_video")
        try {
            contentResolver.openInputStream(uri)?.use { input -> FileOutputStream(target).use { output -> input.copyTo(output) } } ?: throw Exception()
            val old = File(filesDir, if(image) "selected_video" else "selected_image"); if(old.exists()) old.delete()
            prefs.edit().putString("media_uri", uri.toString()).putString("media_path", target.absolutePath)
                .putString("media_type", if(image) "image" else "video").putBoolean("kill_switch", false).commit()
            Toast.makeText(this, "Media selected", Toast.LENGTH_SHORT).show(); showMain()
        } catch (_: Exception) { Toast.makeText(this, "Could not read that file", Toast.LENGTH_LONG).show() }
    }

    private fun saveSelectedMedia() {
        val path = prefs.getString("media_path", null)?.let(::File)
        val type = prefs.getString("media_type", null)
        if(path == null || type == null || !path.exists()) { Toast.makeText(this, "Choose a photo or video first", Toast.LENGTH_SHORT).show(); return }
        val image = type == "image"
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, if(image) "POCO_Wallpaper.jpg" else "POCO_Wallpaper.mp4")
            put(MediaStore.MediaColumns.MIME_TYPE, if(image) "image/jpeg" else "video/mp4")
            if(Build.VERSION.SDK_INT >= 29) put(MediaStore.MediaColumns.RELATIVE_PATH, if(image) Environment.DIRECTORY_PICTURES + "/POCO Live Wallpaper" else Environment.DIRECTORY_MOVIES + "/POCO Live Wallpaper")
        }
        try {
            val collection = if(image) MediaStore.Images.Media.EXTERNAL_CONTENT_URI else MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            val out = contentResolver.insert(collection, values) ?: throw Exception()
            try { contentResolver.openOutputStream(out)?.use { o -> path.inputStream().use { it.copyTo(o) } } ?: throw Exception() }
            catch(e: Exception) { contentResolver.delete(out, null, null); throw e }
            Toast.makeText(this, "Saved to Gallery", Toast.LENGTH_SHORT).show()
        } catch (_: Exception) { Toast.makeText(this, "Could not save media", Toast.LENGTH_LONG).show() }
    }

    private fun applyWallpaper() {
        if(prefs.getString("media_path", null) == null) { Toast.makeText(this, "Choose a photo or video first", Toast.LENGTH_SHORT).show(); return }
        prefs.edit().putBoolean("kill_switch", false).commit()
        try { startActivity(Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, component)) }
        catch(_: Exception) { try { startActivity(Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER)) } catch(_: Exception) { Toast.makeText(this, "Live wallpaper picker is not available", Toast.LENGTH_LONG).show() } }
    }

    private fun toggleKillSwitch() {
        val enabled = !prefs.getBoolean("kill_switch", false); prefs.edit().putBoolean("kill_switch", enabled).commit()
        if(enabled) try { val wm=WallpaperManager.getInstance(this); if(wm.wallpaperInfo?.component == component) wm.clear(WallpaperManager.FLAG_SYSTEM) } catch(_: Exception) {}
        Toast.makeText(this, if(enabled) "Wallpaper engine stopped" else "Wallpaper engine enabled", Toast.LENGTH_SHORT).show(); showMain()
    }

    private fun showSettings() {
        val root=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL; setPadding(dp(22),dp(54),dp(22),dp(28)); setBackgroundColor(Color.rgb(11,11,13)) }
        root.addView(label("Motion Settings",28f,Color.WHITE,true))
        root.addView(label("Tune how strongly the wallpaper responds to movement.",13f,Color.rgb(155,155,164)).apply { setPadding(0,dp(7),0,dp(24)) })
        val card=LinearLayout(this).apply { orientation=LinearLayout.VERTICAL; setPadding(dp(18),dp(18),dp(18),dp(18)); background=bg(Color.rgb(23,23,27),22f) }
        val gyro=Switch(this).apply { text="Gyro Parallax"; textSize=16f; setTextColor(Color.WHITE); isChecked=prefs.getBoolean("gyro_enabled",true) }
        card.addView(gyro)
        val value=label("Sensitivity: "+prefs.getInt("gyro_sensitivity",50)+"%",13f,Color.rgb(165,165,172)).apply { setPadding(0,dp(18),0,0) }
        card.addView(value)
        val seek=SeekBar(this).apply { max=100; progress=prefs.getInt("gyro_sensitivity",50); setOnSeekBarChangeListener(object:SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(s:SeekBar?,p:Int,fromUser:Boolean){ value.text="Sensitivity: "+p+"%" }
            override fun onStartTrackingTouch(s:SeekBar?){}
            override fun onStopTrackingTouch(s:SeekBar?){}
        }) }
        card.addView(seek); root.addView(card); root.addView(Space(this),LinearLayout.LayoutParams(1,dp(16)))
        root.addView(mainButton("Save & Return"){ prefs.edit().putBoolean("gyro_enabled",gyro.isChecked).putInt("gyro_sensitivity",seek.progress).apply(); showMain() })
        setContentView(root)
    }
}
KOTLIN
