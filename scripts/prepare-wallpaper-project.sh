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
                .commit()
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
        prefs.edit().putBoolean("kill_switch", false).commit()
        try {
            startActivity(Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, component))
        } catch (_: Exception) {
            try { startActivity(Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER)) }
            catch (_: Exception) { Toast.makeText(this, "Live wallpaper picker is not available", Toast.LENGTH_LONG).show() }
        }
    }

    private fun toggleKillSwitch() {
        val enabled = !prefs.getBoolean("kill_switch", false)
        prefs.edit().putBoolean("kill_switch", enabled).commit()
        if (enabled) {
            try {
                val wm = WallpaperManager.getInstance(this)
                if (wm.wallpaperInfo?.component == component) {
                    wm.clear(WallpaperManager.FLAG_SYSTEM)
                }
            } catch (_: Exception) {}
            Toast.makeText(this, "Wallpaper engine stopped", Toast.LENGTH_SHORT).show()
        } else {
            Toast.makeText(this, "Wallpaper engine enabled", Toast.LENGTH_SHORT).show()
        }
        showMain()
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

import android.app.WallpaperManager
import android.content.ComponentName
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.SurfaceTexture
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.opengl.EGL14
import android.opengl.EGLExt
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.Handler
import android.os.Process
import android.service.wallpaper.WallpaperService
import android.view.MotionEvent
import android.view.Surface
import android.view.SurfaceHolder
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import java.io.File
import kotlin.math.max

class PocoLiveWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = PocoEngine()

    inner class PocoEngine : Engine(), SensorEventListener, SurfaceTexture.OnFrameAvailableListener {
        private val prefs get() = getSharedPreferences("wallpaper", MODE_PRIVATE)
        private var player: ExoPlayer? = null
        private var bitmap: Bitmap? = null
        private var holderRef: SurfaceHolder? = null
        private var sensors: SensorManager? = null
        private var sensor: Sensor? = null
        private var offsetX = 0f
        private var offsetY = 0f
        private var basePitch = 0f
        private var baseRoll = 0f
        private var calibrated = false
        private var touchEnabled = true
        private var reverseLoop = false
        private var batteryMode = false
        private var targetFps = 60
        private var islandOpen = false
        private var islandLeft = -1f
        private var islandTop = -1f
        private var draggingIsland = false
        private var dragMoved = false
        private var dragStartX = 0f
        private var dragStartY = 0f
        private var islandStartLeft = 0f
        private var islandStartTop = 0f

        // Video is decoded by ExoPlayer into this private SurfaceTexture.
        // The wallpaper Surface remains owned by our GL renderer, so gyro
        // transforms can be applied without Canvas/MediaPlayer surface conflicts.
        private var videoTextureId = 0
        private var videoTexture: SurfaceTexture? = null
        private var videoInputSurface: Surface? = null
        private var eglDisplay = EGL14.EGL_NO_DISPLAY
        private var eglContext = EGL14.EGL_NO_CONTEXT
        private var eglSurface = EGL14.EGL_NO_SURFACE
        private var glProgram = 0
        private var glPosition = 0
        private var glTexCoord = 0
        private var glMvp = 0
        private var glTexMatrix = 0
        private var videoWidth = 0
        private var videoHeight = 0
        private var wallpaperWidth = 0
        private var wallpaperHeight = 0
        private val texMatrix = FloatArray(16)
        private val handler = Handler(mainLooper)

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            setTouchEventsEnabled(true)
        }

        override fun onSurfaceCreated(holder: SurfaceHolder) {
            super.onSurfaceCreated(holder)
            holderRef = holder
            wallpaperWidth = holder.surfaceFrame.width()
            wallpaperHeight = holder.surfaceFrame.height()
            if (!prefs.getBoolean("kill_switch", false)) {
                loadMedia(holder)
                handler.postDelayed({
                    if (!prefs.getBoolean("kill_switch", false)) {
                        loadMedia(holder)
                        if (player == null) drawImage()
                    }
                }, 300L)
            }
            registerSensors()
            if (player == null) drawImage()
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            wallpaperWidth = width
            wallpaperHeight = height
            if (player == null) drawImage()
            handler.postDelayed({
                if (!prefs.getBoolean("kill_switch", false)) {
                    val wasVideo = prefs.getString("media_type", null) == "video"
                    loadMedia(holder)
                    if (!wasVideo && player == null) drawImage()
                }
            }, 150L)
            if (player != null) renderVideo()
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            handler.removeCallbacksAndMessages(null)
            unregisterSensors()
            releasePlayer()
            releaseVideoGl()
            bitmap?.recycle()
            bitmap = null
            holderRef = null
            super.onSurfaceDestroyed(holder)
        }

        override fun onVisibilityChanged(visible: Boolean) {
            if (visible) {
                if (prefs.getBoolean("kill_switch", false)) {
                    releasePlayer()
                    return
                }
                if (player == null && bitmap == null) {
                    holderRef?.let {
                        loadMedia(it)
                        if (player == null) drawImage()
                    }
                } else {
                    player?.play()
                    if (player == null) drawImage()
                }
                registerSensors()
            } else {
                player?.pause()
                unregisterSensors()
            }
        }

        private fun loadMedia(holder: SurfaceHolder) {
            releasePlayer()
            bitmap?.recycle()
            bitmap = null
            releaseVideoGl()

            val storedPath = prefs.getString("media_path", null)
            val storedUri = prefs.getString("media_uri", null)
            val type = prefs.getString("media_type", null)

            if (type == null) {
                drawImage()
                return
            }

            if (type == "image") {
                bitmap = try {
                    val path = storedPath?.let(::File)
                    if (path != null && path.exists()) {
                        BitmapFactory.decodeFile(path.absolutePath)
                    } else if (!storedUri.isNullOrEmpty()) {
                        contentResolver.openInputStream(android.net.Uri.parse(storedUri))?.use {
                            BitmapFactory.decodeStream(it)
                        }
                    } else null
                } catch (_: Exception) {
                    null
                }
                drawImage()
                return
            }

            if (type == "video") {
                val mediaUri = when {
                    !storedPath.isNullOrEmpty() && File(storedPath).exists() ->
                        android.net.Uri.fromFile(File(storedPath))
                    !storedUri.isNullOrEmpty() ->
                        android.net.Uri.parse(storedUri)
                    else -> null
                }

                if (mediaUri == null) {
                    drawImage()
                    return
                }

                try {
                    setupVideoGl(holder)
                    player = ExoPlayer.Builder(this@PocoLiveWallpaperService).build().apply {
                        setMediaItem(MediaItem.fromUri(mediaUri))
                        repeatMode = Player.REPEAT_MODE_ONE
                        volume = 0f
                        setVideoSurface(videoInputSurface)
                        addListener(object : Player.Listener {
                            override fun onVideoSizeChanged(videoSize: androidx.media3.common.VideoSize) {
                                videoWidth = videoSize.width
                                videoHeight = videoSize.height
                                renderVideo()
                            }
                        })
                        prepare()
                        playWhenReady = true
                    }
                } catch (_: Exception) {
                    releasePlayer()
                    releaseVideoGl()
                    drawImage()
                }
            }
        }

        private fun setupVideoGl(holder: SurfaceHolder) {
            if (eglDisplay != EGL14.EGL_NO_DISPLAY) return

            eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (eglDisplay == EGL14.EGL_NO_DISPLAY) throw RuntimeException("No EGL display")

            val version = IntArray(2)
            if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) {
                throw RuntimeException("EGL init failed")
            }

            val configs = arrayOfNulls<android.opengl.EGLConfig>(1)
            val num = IntArray(1)
            val attrs = intArrayOf(
                EGL14.EGL_RENDERABLE_TYPE, EGLExt.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
                EGL14.EGL_RED_SIZE, 8,
                EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_ALPHA_SIZE, 8,
                EGL14.EGL_NONE
            )
            if (!EGL14.eglChooseConfig(eglDisplay, attrs, 0, configs, 0, 1, num, 0)) {
                throw RuntimeException("EGL config failed")
            }

            val contextAttrs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
            eglContext = EGL14.eglCreateContext(
                eglDisplay, configs[0], EGL14.EGL_NO_CONTEXT, contextAttrs, 0
            )
            if (eglContext == EGL14.EGL_NO_CONTEXT) throw RuntimeException("EGL context failed")

            val surfaceAttrs = intArrayOf(EGL14.EGL_NONE)
            eglSurface = EGL14.eglCreateWindowSurface(
                eglDisplay, configs[0], holder.surface, surfaceAttrs, 0
            )
            if (eglSurface == EGL14.EGL_NO_SURFACE) throw RuntimeException("EGL wallpaper surface failed")

            if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
                throw RuntimeException("EGL make current failed")
            }

            glProgram = createVideoProgram()
            videoTextureId = createExternalTexture()
            videoTexture = SurfaceTexture(videoTextureId).also {
                it.setOnFrameAvailableListener(this)
            }
            videoInputSurface = Surface(videoTexture)
        }

        private fun createExternalTexture(): Int {
            val ids = IntArray(1)
            GLES20.glGenTextures(1, ids, 0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, ids[0])
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
            return ids[0]
        }

        private fun createVideoProgram(): Int {
            val vertex = """
                attribute vec2 aPosition;
                attribute vec2 aTexCoord;
                uniform mat4 uMvp;
                uniform mat4 uTexMatrix;
                varying vec2 vTexCoord;
                void main() {
                    gl_Position = uMvp * vec4(aPosition, 0.0, 1.0);
                    vec4 tc = uTexMatrix * vec4(aTexCoord, 0.0, 1.0);
                    vTexCoord = tc.xy;
                }
            """.trimIndent()
            val fragment = """
                #extension GL_OES_EGL_image_external : require
                precision mediump float;
                uniform samplerExternalOES uTexture;
                varying vec2 vTexCoord;
                void main() {
                    gl_FragColor = texture2D(uTexture, vTexCoord);
                }
            """.trimIndent()

            fun compile(type: Int, source: String): Int {
                val shader = GLES20.glCreateShader(type)
                GLES20.glShaderSource(shader, source)
                GLES20.glCompileShader(shader)
                val ok = IntArray(1)
                GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, ok, 0)
                if (ok[0] == 0) {
                    val log = GLES20.glGetShaderInfoLog(shader)
                    GLES20.glDeleteShader(shader)
                    throw RuntimeException("Shader compile failed: $log")
                }
                return shader
            }

            val vs = compile(GLES20.GL_VERTEX_SHADER, vertex)
            val fs = compile(GLES20.GL_FRAGMENT_SHADER, fragment)
            val program = GLES20.glCreateProgram()
            GLES20.glAttachShader(program, vs)
            GLES20.glAttachShader(program, fs)
            GLES20.glLinkProgram(program)
            GLES20.glDeleteShader(vs)
            GLES20.glDeleteShader(fs)
            val ok = IntArray(1)
            GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, ok, 0)
            if (ok[0] == 0) {
                val log = GLES20.glGetProgramInfoLog(program)
                GLES20.glDeleteProgram(program)
                throw RuntimeException("Program link failed: $log")
            }
            glPosition = GLES20.glGetAttribLocation(program, "aPosition")
            glTexCoord = GLES20.glGetAttribLocation(program, "aTexCoord")
            glMvp = GLES20.glGetUniformLocation(program, "uMvp")
            glTexMatrix = GLES20.glGetUniformLocation(program, "uTexMatrix")
            return program
        }

        private fun renderVideo() {
            if (player == null || videoTexture == null || eglDisplay == EGL14.EGL_NO_DISPLAY) return
            if (eglContext == EGL14.EGL_NO_CONTEXT || eglSurface == EGL14.EGL_NO_SURFACE) return
            if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) return

            try {
                videoTexture?.updateTexImage()
                videoTexture?.getTransformMatrix(texMatrix)
            } catch (_: Exception) {
                return
            }

            val width = wallpaperWidth.coerceAtLeast(1)
            val height = wallpaperHeight.coerceAtLeast(1)
            GLES20.glViewport(0, 0, width, height)
            GLES20.glClearColor(0f, 0f, 0f, 1f)
            GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
            GLES20.glUseProgram(glProgram)

            val vw = videoWidth.takeIf { it > 0 } ?: width
            val vh = videoHeight.takeIf { it > 0 } ?: height
            val videoAspect = vw.toFloat() / vh.toFloat()
            val screenAspect = width.toFloat() / height.toFloat()

            val scaleX: Float
            val scaleY: Float
            if (videoAspect > screenAspect) {
                scaleX = videoAspect / screenAspect
                scaleY = 1f
            } else {
                scaleX = 1f
                scaleY = screenAspect / videoAspect
            }

            val sensitivity = prefs.getInt("gyro_sensitivity", 50) / 50f
            val parallaxX = (offsetX / width.toFloat()) * 2.0f * sensitivity
            val parallaxY = (offsetY / height.toFloat()) * 2.0f * sensitivity

            // Extra crop is intentionally used so the frame can move equally
            // left/right and up/down without exposing empty wallpaper edges.
            val vertices = floatArrayOf(
                -scaleX + parallaxX, -scaleY + parallaxY,
                 scaleX + parallaxX, -scaleY + parallaxY,
                -scaleX + parallaxX,  scaleY + parallaxY,
                 scaleX + parallaxX,  scaleY + parallaxY
            )
            val coords = floatArrayOf(
                0f, 1f, 1f, 1f,
                0f, 0f, 1f, 0f
            )

            val vb = java.nio.ByteBuffer.allocateDirect(vertices.size * 4)
                .order(java.nio.ByteOrder.nativeOrder()).asFloatBuffer()
            vb.put(vertices).position(0)
            val cb = java.nio.ByteBuffer.allocateDirect(coords.size * 4)
                .order(java.nio.ByteOrder.nativeOrder()).asFloatBuffer()
            cb.put(coords).position(0)

            GLES20.glEnableVertexAttribArray(glPosition)
            GLES20.glVertexAttribPointer(glPosition, 2, GLES20.GL_FLOAT, false, 0, vb)
            GLES20.glEnableVertexAttribArray(glTexCoord)
            GLES20.glVertexAttribPointer(glTexCoord, 2, GLES20.GL_FLOAT, false, 0, cb)
            GLES20.glUniformMatrix4fv(glMvp, 1, false, IDENTITY, 0)
            GLES20.glUniformMatrix4fv(glTexMatrix, 1, false, texMatrix, 0)
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, videoTextureId)
            GLES20.glUniform1i(GLES20.glGetUniformLocation(glProgram, "uTexture"), 0)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GLES20.glDisableVertexAttribArray(glPosition)
            GLES20.glDisableVertexAttribArray(glTexCoord)
            EGL14.eglSwapBuffers(eglDisplay, eglSurface)
        }

        override fun onFrameAvailable(surfaceTexture: SurfaceTexture) {
            handler.post { renderVideo() }
        }

        private fun releasePlayer() {
            player?.clearVideoSurface()
            player?.release()
            player = null
        }

        private fun releaseVideoGl() {
            videoInputSurface?.release()
            videoInputSurface = null
            videoTexture?.setOnFrameAvailableListener(null)
            videoTexture?.release()
            videoTexture = null

            if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
                if (eglContext != EGL14.EGL_NO_CONTEXT) {
                    EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                }
                if (eglSurface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(eglDisplay, eglSurface)
                if (eglContext != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(eglDisplay, eglContext)
                EGL14.eglTerminate(eglDisplay)
            }

            eglDisplay = EGL14.EGL_NO_DISPLAY
            eglContext = EGL14.EGL_NO_CONTEXT
            eglSurface = EGL14.EGL_NO_SURFACE
            glProgram = 0
            videoTextureId = 0
        }

        private fun registerSensors() {
            if (!prefs.getBoolean("gyro_enabled", true) || sensors != null) return
            sensors = getSystemService(SENSOR_SERVICE) as SensorManager
            sensor = sensors?.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
                ?: sensors?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
            sensor?.let { sensors?.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME) }
        }

        private fun unregisterSensors() {
            sensors?.unregisterListener(this)
            sensors = null
            sensor = null
            calibrated = false
        }

        override fun onSensorChanged(event: SensorEvent) {
            val matrix = FloatArray(9)
            SensorManager.getRotationMatrixFromVector(matrix, event.values)
            val orientation = FloatArray(3)
            SensorManager.getOrientation(matrix, orientation)
            val pitch = orientation[1]
            val roll = orientation[2]

            if (!calibrated) {
                basePitch = pitch
                baseRoll = roll
                calibrated = true
                return
            }

            var dPitch = pitch - basePitch
            var dRoll = roll - baseRoll
            val pi = Math.PI.toFloat()
            val twoPi = (Math.PI * 2.0).toFloat()
            while (dPitch > pi) dPitch -= twoPi
            while (dPitch < -pi) dPitch += twoPi
            while (dRoll > pi) dRoll -= twoPi
            while (dRoll < -pi) dRoll += twoPi

            val sensitivity = prefs.getInt("gyro_sensitivity", 50) / 50f
            val maxOffsetX = 70f * sensitivity
            val maxOffsetY = 70f * sensitivity
            val tx = (dRoll * 220f).coerceIn(-maxOffsetX, maxOffsetX)
            val ty = (dPitch * 220f).coerceIn(-maxOffsetY, maxOffsetY)

            offsetX += (tx - offsetX) * 0.16f
            offsetY += (ty - offsetY) * 0.16f

            if (player != null) {
                renderVideo()
            } else {
                drawImage()
            }
        }

        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

        override fun onTouchEvent(event: MotionEvent) {
            if (!touchEnabled) return
            val w = holderRef?.surfaceFrame?.width() ?: return
            val h = holderRef?.surfaceFrame?.height() ?: return

            if (islandLeft < 0f) {
                islandLeft = w - 66f
                islandTop = 18f
            }

            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    val hitRight = islandLeft + if (islandOpen) 76f else 52f
                    val hitBottom = islandTop + if (islandOpen) 430f else 38f
                    if (event.x < islandLeft || event.x > hitRight || event.y < islandTop || event.y > hitBottom) return
                    draggingIsland = true
                    dragMoved = false
                    dragStartX = event.x
                    dragStartY = event.y
                    islandStartLeft = islandLeft
                    islandStartTop = islandTop
                }
                MotionEvent.ACTION_MOVE -> {
                    if (!draggingIsland) return
                    val dx = event.x - dragStartX
                    val dy = event.y - dragStartY
                    if (kotlin.math.abs(dx) + kotlin.math.abs(dy) > 8f) dragMoved = true
                    if (dragMoved) {
                        islandLeft = (islandStartLeft + dx).coerceIn(4f, (w - 80f).coerceAtLeast(4f))
                        islandTop = (islandStartTop + dy).coerceIn(4f, (h - 50f).coerceAtLeast(4f))
                        if (player == null) drawImage()
                    }
                }
                MotionEvent.ACTION_UP -> {
                    if (!draggingIsland) return
                    draggingIsland = false
                    if (dragMoved) {
                        prefs.edit().putFloat("island_left", islandLeft).putFloat("island_top", islandTop).apply()
                        return
                    }

                    val pillRight = islandLeft + if (islandOpen) 76f else 52f
                    val pillBottom = islandTop + 38f
                    if (event.x >= islandLeft && event.x <= pillRight && event.y >= islandTop && event.y <= pillBottom) {
                        islandOpen = !islandOpen
                        if (player == null) drawImage()
                        return
                    }

                    if (!islandOpen) return
                    val panelTop = islandTop + 46f
                    val panelBottom = panelTop + 348f
                    val panelLeft = islandLeft + 52f - 250f
                    val panelRight = islandLeft + 52f
                    if (event.x < panelLeft || event.x > panelRight || event.y < panelTop || event.y > panelBottom) return

                    val row = ((event.y - panelTop - 28f) / 48f).toInt()
                    when (row) {
                        0 -> killEngine()
                        1 -> restartEngine()
                        2 -> touchEnabled = !touchEnabled
                        3 -> reverseLoop = !reverseLoop
                        4 -> batteryMode = !batteryMode
                        5 -> targetFps = if (targetFps == 60) 30 else 60
                    }
                    if (player == null) drawImage()
                }
            }
        }

        private fun killEngine() {
            prefs.edit().putBoolean("kill_switch", true).commit()
            releasePlayer()
            bitmap?.recycle()
            bitmap = null
            releaseVideoGl()
            try {
                val wm = WallpaperManager.getInstance(this@PocoLiveWallpaperService)
                if (wm.wallpaperInfo?.component == ComponentName(this@PocoLiveWallpaperService, PocoLiveWallpaperService::class.java)) {
                    wm.clear(WallpaperManager.FLAG_SYSTEM)
                }
            } catch (_: Exception) {}
            Process.killProcess(Process.myPid())
        }

        private fun restartEngine() {
            prefs.edit().putBoolean("kill_switch", false).apply()
            calibrated = false
            holderRef?.let { loadMedia(it) }
            if (player == null) drawImage()
        }

        private fun drawImage() {
            val h = holderRef ?: return
            val canvas: Canvas = try { h.lockCanvas() } catch (_: Exception) { null } ?: return
            try {
                canvas.drawColor(Color.BLACK)
                val b = bitmap
                if (b != null) {
                    val scale = max(canvas.width.toFloat() / b.width, canvas.height.toFloat() / b.height)
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
            } finally {
                h.unlockCanvasAndPost(canvas)
            }
        }

        private fun drawInteractiveIsland(canvas: Canvas) {
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            if (islandLeft < 0f) {
                islandLeft = canvas.width - 66f
                islandTop = 18f
                val savedLeft = prefs.getFloat("island_left", islandLeft)
                val savedTop = prefs.getFloat("island_top", islandTop)
                islandLeft = savedLeft.coerceIn(4f, (canvas.width - 80f).coerceAtLeast(4f))
                islandTop = savedTop.coerceIn(4f, (canvas.height - 50f).coerceAtLeast(4f))
            }

            val pillWidth = if (islandOpen) 76f else 52f
            val pill = RectF(islandLeft, islandTop, islandLeft + pillWidth, islandTop + 38f)
            paint.color = Color.argb(215, 8, 8, 8)
            canvas.drawRoundRect(pill, 20f, 20f, paint)
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = 1.2f
            paint.color = Color.argb(100, 255, 255, 255)
            canvas.drawRoundRect(pill, 20f, 20f, paint)
            paint.style = Paint.Style.FILL
            paint.color = Color.WHITE
            paint.textSize = 21f
            paint.typeface = android.graphics.Typeface.DEFAULT_BOLD
            canvas.drawText("≡", islandLeft + pillWidth / 2f - 7f, islandTop + 27f, paint)

            if (!islandOpen) return
            val panelRight = islandLeft + 52f
            val panelLeft = panelRight - 250f
            val panelTop = islandTop + 46f
            val panelBottom = panelTop + 348f
            paint.color = Color.argb(232, 16, 16, 16)
            canvas.drawRoundRect(RectF(panelLeft, panelTop, panelRight, panelBottom), 20f, 20f, paint)
            paint.textSize = 14f
            paint.typeface = android.graphics.Typeface.DEFAULT_BOLD
            paint.color = Color.WHITE
            canvas.drawText("Wallpaper Engine", panelLeft + 14f, panelTop + 24f, paint)
            paint.textSize = 9f
            paint.typeface = android.graphics.Typeface.DEFAULT
            paint.color = Color.argb(145, 255, 255, 255)
            canvas.drawText("Drag the Island • tap ≡ to close", panelLeft + 14f, panelTop + 39f, paint)

            val labels = arrayOf(
                "KILL ENGINE",
                "RESTART",
                "TOUCH " + if (touchEnabled) "ON" else "OFF",
                "LOOP " + if (reverseLoop) "REVERSE" else "NORMAL",
                "BATTERY " + if (batteryMode) "ON" else "OFF",
                "FPS " + targetFps
            )
            paint.textSize = 13f
            paint.typeface = android.graphics.Typeface.DEFAULT_BOLD
            for (i in labels.indices) {
                val yy = panelTop + 67f + i * 48f
                paint.color = if (i == 0) Color.rgb(255, 110, 110) else Color.WHITE
                canvas.drawText(labels[i], panelLeft + 16f, yy, paint)
                paint.color = Color.argb(35, 255, 255, 255)
                if (i < labels.lastIndex) canvas.drawRect(panelLeft + 12f, yy + 12f, panelRight - 12f, yy + 13f, paint)
            }
            paint.typeface = android.graphics.Typeface.DEFAULT
            paint.textSize = 9f
            paint.color = Color.argb(150, 255, 255, 255)
            canvas.drawText("ENGINE RUNNING", panelLeft + 16f, panelBottom - 10f, paint)
        }

        companion object {
            private val IDENTITY = floatArrayOf(
                1f, 0f, 0f, 0f,
                0f, 1f, 0f, 0f,
                0f, 0f, 1f, 0f,
                0f, 0f, 0f, 1f
            )
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
    <uses-permission android:name="android.permission.SET_WALLPAPER" />
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
