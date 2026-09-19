#!/usr/bin/env bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path

activity = Path("app/src/main/java/com/poco/wallpaper/WallpaperControlsActivity.kt")
service = Path("app/src/main/java/com/poco/wallpaper/PocoLiveWallpaperService.kt")

a = activity.read_text()

old = '''        root.addView(row("Save Selected Media", "Copy it to your Gallery", "↓") { saveSelectedMedia() })

        root.addView(section("Motion"))'''
new = '''        root.addView(row("Save Selected Media", "Copy it to your Gallery", "↓") { saveSelectedMedia() })
        root.addView(Space(this), LinearLayout.LayoutParams(1, dp(8)))
        root.addView(row("Orientation", orientationLabel(), "↻") { showOrientation() })

        root.addView(section("Motion"))'''
if old not in a:
    raise SystemExit("UI media section anchor not found")
a = a.replace(old, new, 1)

old = '''        val image = requestCode == 11
        val target = File(filesDir, if(image) "selected_image" else "selected_video")
        try {
            contentResolver.openInputStream(uri)?.use { input -> FileOutputStream(target).use { output -> input.copyTo(output) } } ?: throw Exception()
            val old = File(filesDir, if(image) "selected_video" else "selected_image"); if(old.exists()) old.delete()
            prefs.edit().putString("media_uri", uri.toString()).putString("media_path", target.absolutePath)
                .putString("media_type", if(image) "image" else "video").putBoolean("kill_switch", false).commit()
            Toast.makeText(this, "Media selected", Toast.LENGTH_SHORT).show(); showMain()
        } catch (_: Exception) { Toast.makeText(this, "Could not read that file", Toast.LENGTH_LONG).show() }'''
new = '''        val image = requestCode == 11
        val mediaKind = if(image) "image" else "video"
        val target = File(filesDir, if(image) "selected_image" else "selected_video")
        try {
            contentResolver.openInputStream(uri)?.use { input -> FileOutputStream(target).use { output -> input.copyTo(output) } } ?: throw Exception()
            val old = File(filesDir, if(image) "selected_video" else "selected_image"); if(old.exists()) old.delete()
            val savedOrientation = prefs.getInt("${mediaKind}_orientation", 0)
            prefs.edit().putString("media_uri", uri.toString()).putString("media_path", target.absolutePath)
                .putString("media_type", mediaKind).putInt("media_orientation", savedOrientation)
                .putBoolean("kill_switch", false).commit()
            Toast.makeText(this, "Media selected", Toast.LENGTH_SHORT).show(); showMain()
        } catch (_: Exception) { Toast.makeText(this, "Could not read that file", Toast.LENGTH_LONG).show() }'''
if old not in a:
    raise SystemExit("media selection anchor not found")
a = a.replace(old, new, 1)

anchor = '''    private fun showSettings() {'''
insert = '''    private fun orientationLabel(): String = when (prefs.getInt("media_orientation", 0)) {
        90 -> "Rotated 90°"
        180 -> "Rotated 180°"
        270 -> "Rotated 270°"
        else -> "Original"
    }

    private fun showOrientation() {
        val options = arrayOf("Original (0°)", "Rotate 90°", "Rotate 180°", "Rotate 270°")
        val selected = (prefs.getInt("media_orientation", 0) / 90).coerceIn(0, 3)
        android.app.AlertDialog.Builder(this)
            .setTitle("Media Orientation")
            .setSingleChoiceItems(options, selected) { dialog, which ->
                val degrees = which * 90
                val kind = prefs.getString("media_type", null)
                prefs.edit()
                    .putInt("media_orientation", degrees)
                    .apply { if (kind != null) putInt("__DOLLAR__{kind}_orientation", degrees) }
                    .commit()
                dialog.dismiss()
                showMain()
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun showSettings() {'''
if anchor not in a:
    raise SystemExit("settings anchor not found")
a = a.replace(anchor, insert, 1)
activity.write_text(a)

s = service.read_text()

old = '''import android.opengl.EGL14
import android.opengl.GLES11Ext
import android.opengl.GLES20'''
new = '''import android.opengl.EGL14
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.Matrix'''
if old not in s:
    raise SystemExit("OpenGL import anchor not found")
s = s.replace(old, new, 1)

old = '''        private val texMatrix = FloatArray(16)
        private val handler = Handler(mainLooper)

        override fun onCreate(surfaceHolder: SurfaceHolder) {'''
new = '''        private val texMatrix = FloatArray(16)
        private val rotatedTexMatrix = FloatArray(16)
        private val rotationMatrix = FloatArray(16)
        private val handler = Handler(mainLooper)
        private val prefListener = android.content.SharedPreferences.OnSharedPreferenceChangeListener { _, key ->
            if (key == "media_orientation") {
                handler.post {
                    if (player != null) renderVideo() else drawImage()
                }
            }
        }

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            prefs.registerOnSharedPreferenceChangeListener(prefListener)'''
if old not in s:
    raise SystemExit("service field anchor not found")
s = s.replace(old, new, 1)

old = '''        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            handler.removeCallbacksAndMessages(null)
            unregisterSensors()'''
new = '''        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            prefs.unregisterOnSharedPreferenceChangeListener(prefListener)
            handler.removeCallbacksAndMessages(null)
            unregisterSensors()'''
if old not in s:
    raise SystemExit("surface destroy anchor not found")
s = s.replace(old, new, 1)

old = '''            try {
                videoTexture?.updateTexImage()
                videoTexture?.getTransformMatrix(texMatrix)
            } catch (_: Exception) {
                return
            }

            val width = wallpaperWidth.coerceAtLeast(1)'''
new = '''            try {
                videoTexture?.updateTexImage()
                videoTexture?.getTransformMatrix(texMatrix)
            } catch (_: Exception) {
                return
            }

            val orientation = mediaOrientation()
            Matrix.setIdentityM(rotationMatrix, 0)
            Matrix.translateM(rotationMatrix, 0, 0.5f, 0.5f, 0f)
            Matrix.rotateM(rotationMatrix, 0, orientation.toFloat(), 0f, 0f, 1f)
            Matrix.translateM(rotationMatrix, 0, -0.5f, -0.5f, 0f)
            Matrix.multiplyMM(rotatedTexMatrix, 0, texMatrix, 0, rotationMatrix, 0)

            val width = wallpaperWidth.coerceAtLeast(1)'''
if old not in s:
    raise SystemExit("video texture transform anchor not found")
s = s.replace(old, new, 1)

old = '''            val vw = videoWidth.takeIf { it > 0 } ?: width
            val vh = videoHeight.takeIf { it > 0 } ?: height
            val videoAspect = vw.toFloat() / vh.toFloat()'''
new = '''            val vw = videoWidth.takeIf { it > 0 } ?: width
            val vh = videoHeight.takeIf { it > 0 } ?: height
            val rawAspect = vw.toFloat() / vh.toFloat()
            val videoAspect = if (orientation == 90 || orientation == 270) 1f / rawAspect else rawAspect'''
if old not in s:
    raise SystemExit("video aspect anchor not found")
s = s.replace(old, new, 1)

old = '''            GLES20.glUniformMatrix4fv(glMvp, 1, false, identityMatrix, 0)
            GLES20.glUniformMatrix4fv(glTexMatrix, 1, false, texMatrix, 0)'''
new = '''            GLES20.glUniformMatrix4fv(glMvp, 1, false, identityMatrix, 0)
            GLES20.glUniformMatrix4fv(glTexMatrix, 1, false, rotatedTexMatrix, 0)'''
if old not in s:
    raise SystemExit("texture matrix upload anchor not found")
s = s.replace(old, new, 1)

anchor = '''        private fun drawImage() {'''
insert = '''        private fun mediaOrientation(): Int = when (prefs.getInt("media_orientation", 0)) {
            90, 180, 270 -> prefs.getInt("media_orientation", 0)
            else -> 0
        }

        private fun drawImage() {'''
if anchor not in s:
    raise SystemExit("drawImage helper anchor not found")
s = s.replace(anchor, insert, 1)

old = '''        private fun drawImage() {
            val h = holderRef ?: return
            val canvas: Canvas = try { h.lockCanvas() } catch (_: Exception) { null } ?: return
            try {
                canvas.drawColor(Color.BLACK)
                val b = bitmap
                if (b != null) {
                    val scale = max(canvas.width.toFloat() / b.width, canvas.height.toFloat() / b.height) * 1.15f
                    val w = b.width * scale
                    val ht = b.height * scale
                    val left = (canvas.width - w) / 2f + offsetX
                    val top = (canvas.height - ht) / 2f + offsetY
                    canvas.drawBitmap(
                        b, null, RectF(left, top, left + w, top + ht),
                        Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
                    )
                }
                drawInteractiveIsland(canvas)
            } finally {'''
new = '''        private fun drawImage() {
            val h = holderRef ?: return
            val canvas: Canvas = try { h.lockCanvas() } catch (_: Exception) { null } ?: return
            try {
                canvas.drawColor(Color.BLACK)
                val b = bitmap
                if (b != null) {
                    val orientation = mediaOrientation()
                    val rotatedWidth = if (orientation == 90 || orientation == 270) b.height.toFloat() else b.width.toFloat()
                    val rotatedHeight = if (orientation == 90 || orientation == 270) b.width.toFloat() else b.height.toFloat()
                    val scale = max(canvas.width.toFloat() / rotatedWidth, canvas.height.toFloat() / rotatedHeight) * 1.15f
                    val w = b.width * scale
                    val ht = b.height * scale
                    val left = (canvas.width - w) / 2f + offsetX
                    val top = (canvas.height - ht) / 2f + offsetY
                    canvas.save()
                    canvas.rotate(orientation.toFloat(), canvas.width / 2f, canvas.height / 2f)
                    canvas.drawBitmap(
                        b, null, RectF(left, top, left + w, top + ht),
                        Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
                    )
                    canvas.restore()
                }
                drawInteractiveIsland(canvas)
            } finally {'''
if old not in s:
    raise SystemExit("photo draw anchor not found")
s = s.replace(old, new, 1)

service.write_text(s)
PY

echo "Media orientation feature applied."
