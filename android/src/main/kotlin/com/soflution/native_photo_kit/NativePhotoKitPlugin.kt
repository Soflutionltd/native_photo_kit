package com.soflution.native_photo_kit

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RectF
import android.media.ExifInterface
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.nio.ByteBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * Photos are decoded subsampled (never at full resolution to output 1080 px),
 * with EXIF orientation applied, then composited on a `Canvas` and encoded by
 * `Bitmap.compress` (libjpeg-turbo).
 */
class NativePhotoKitPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private companion object {
        /**
         * Matches a Gaussian blur of sigma 12 px: three box-blur passes of
         * radius 1 on a 1/8 downscale give a sigma of 11.3 px at full size.
         */
        const val BLUR_DOWNSCALE = 8
        const val BLUR_RADIUS = 1
        const val BLUR_PASSES = 3
        val BACKGROUND_DIM = Color.argb(60, 12, 12, 12)
    }

    private var channel: MethodChannel? = null

    /** Several photos of the same import are processed in parallel. */
    private var executor: ExecutorService? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private val filter = Paint(Paint.FILTER_BITMAP_FLAG)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        executor = Executors.newFixedThreadPool(2)
        channel = MethodChannel(binding.binaryMessenger, "native_photo_kit").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        executor?.shutdown()
        executor = null
    }

    private class Target(call: MethodCall) {
        val path: String = call.argument<String>("path") ?: throw IllegalArgumentException("missing path")
        val width: Int = call.argument<Int>("width") ?: 0
        val height: Int = call.argument<Int>("height") ?: 0
        val quality: Int = call.argument<Int>("quality") ?: throw IllegalArgumentException("missing quality")

        init {
            require(width > 0 && height > 0) { "invalid size (${width}x$height)" }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val work: () -> Any? = when (call.method) {
            "encodeJpeg" -> { { encodeJpeg(call) } }
            "orientedSize" -> { { orientedSize(call) } }
            "coverJpeg" -> { { coverJpeg(Target(call)) } }
            "formatForFeed" -> { { formatForFeed(Target(call)) } }
            else -> {
                result.notImplemented()
                return
            }
        }

        val pool = executor ?: return result.error("native_photo_kit", "plugin detached", null)
        pool.execute {
            try {
                val reply = work()
                mainHandler.post { result.success(reply) }
            } catch (error: Exception) {
                mainHandler.post { result.error("native_photo_kit", "${call.method}: ${error.message}", null) }
            } catch (error: OutOfMemoryError) {
                mainHandler.post { result.error("native_photo_kit", "${call.method}: out of memory", null) }
            }
        }
    }

    // Methods

    private fun encodeJpeg(call: MethodCall): ByteArray {
        val rgba = call.argument<ByteArray>("rgba") ?: throw IllegalArgumentException("missing pixels")
        val width = call.argument<Int>("width") ?: 0
        val height = call.argument<Int>("height") ?: 0
        val quality = call.argument<Int>("quality") ?: throw IllegalArgumentException("missing quality")
        require(width > 0 && height > 0 && rgba.size >= width * height * 4) {
            "invalid pixels (${width}x$height, ${rgba.size} bytes)"
        }

        // ARGB_8888 is laid out in memory byte by byte as R, G, B, A: the same
        // order as `ui.ImageByteFormat.rawRgba`.
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            bitmap.copyPixelsFromBuffer(ByteBuffer.wrap(rgba, 0, width * height * 4))
            return jpegData(bitmap, quality)
        } finally {
            bitmap.recycle()
        }
    }

    private fun orientedSize(call: MethodCall): List<Int>? {
        val path = call.argument<String>("path") ?: throw IllegalArgumentException("missing path")
        val photo = Photo.open(path) ?: return null
        return listOf(photo.width, photo.height)
    }

    private fun coverJpeg(target: Target): ByteArray? {
        val decoded = Photo.open(target.path)?.decodeCovering(target.width, target.height) ?: return null
        val output = Bitmap.createBitmap(target.width, target.height, Bitmap.Config.ARGB_8888)
        try {
            drawCover(Canvas(output), decoded, target.width, target.height)
            return jpegData(output, target.quality)
        } finally {
            decoded.recycle()
            output.recycle()
        }
    }

    private fun formatForFeed(target: Target): ByteArray? {
        val decoded = Photo.open(target.path)?.decodeCovering(target.width, target.height) ?: return null
        val output = Bitmap.createBitmap(target.width, target.height, Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(output)
            drawBlurredBackground(canvas, decoded, target.width, target.height)
            canvas.drawColor(BACKGROUND_DIM)

            val scale = min(target.width.toFloat() / decoded.width, target.height.toFloat() / decoded.height)
            val foregroundWidth = (decoded.width * scale).roundToInt().coerceIn(1, target.width)
            val foregroundHeight = (decoded.height * scale).roundToInt().coerceIn(1, target.height)
            val left = ((target.width - foregroundWidth) / 2f).roundToInt().toFloat()
            val top = ((target.height - foregroundHeight) / 2f).roundToInt().toFloat()
            canvas.drawBitmap(decoded, null, RectF(left, top, left + foregroundWidth, top + foregroundHeight), filter)

            return jpegData(output, target.quality)
        } finally {
            decoded.recycle()
            output.recycle()
        }
    }

    // Helpers

    /** Image file with its displayed dimensions. */
    private class Photo(
        val path: String,
        private val pixelWidth: Int,
        private val pixelHeight: Int,
        private val orientation: Int,
    ) {
        private val swapsAxes = orientation in setOf(
            ExifInterface.ORIENTATION_TRANSPOSE,
            ExifInterface.ORIENTATION_ROTATE_90,
            ExifInterface.ORIENTATION_TRANSVERSE,
            ExifInterface.ORIENTATION_ROTATE_270,
        )
        val width = if (swapsAxes) pixelHeight else pixelWidth
        val height = if (swapsAxes) pixelWidth else pixelHeight

        companion object {
            fun open(path: String): Photo? {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeFile(path, bounds)
                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null

                // A file without EXIF (PNG, screenshot) is simply upright.
                val orientation = try {
                    ExifInterface(path).getAttributeInt(
                        ExifInterface.TAG_ORIENTATION,
                        ExifInterface.ORIENTATION_NORMAL,
                    )
                } catch (error: IOException) {
                    ExifInterface.ORIENTATION_NORMAL
                }
                return Photo(path, bounds.outWidth, bounds.outHeight, orientation)
            }
        }

        /** Oriented decode, subsampled just enough to still cover the target. */
        fun decodeCovering(targetWidth: Int, targetHeight: Int): Bitmap? {
            val scale = max(targetWidth.toFloat() / width, targetHeight.toFloat() / height)
            var sampleSize = 1
            while (scale * sampleSize * 2 <= 1f) sampleSize *= 2

            val options = BitmapFactory.Options().apply { inSampleSize = sampleSize }
            val sampled = BitmapFactory.decodeFile(path, options) ?: return null

            val matrix = orientationMatrix() ?: return sampled
            val oriented = Bitmap.createBitmap(sampled, 0, 0, sampled.width, sampled.height, matrix, true)
            if (oriented !== sampled) sampled.recycle()
            return oriented
        }

        private fun orientationMatrix(): Matrix? {
            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> {
                    matrix.setRotate(90f)
                    matrix.postScale(-1f, 1f)
                }
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
                ExifInterface.ORIENTATION_TRANSVERSE -> {
                    matrix.setRotate(-90f)
                    matrix.postScale(-1f, 1f)
                }
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
                else -> return null
            }
            return matrix
        }
    }

    /** Scales up or down to fill `width`×`height`, cropped around the center. */
    private fun drawCover(canvas: Canvas, source: Bitmap, width: Int, height: Int) {
        val scale = max(width.toFloat() / source.width, height.toFloat() / source.height)
        val scaledWidth = source.width * scale
        val scaledHeight = source.height * scale
        val left = ((width - scaledWidth) / 2f).roundToInt().toFloat()
        val top = ((height - scaledHeight) / 2f).roundToInt().toFloat()
        canvas.drawBitmap(source, null, RectF(left, top, left + scaledWidth, top + scaledHeight), filter)
    }

    private fun drawBlurredBackground(canvas: Canvas, source: Bitmap, width: Int, height: Int) {
        val smallWidth = max(1, width / BLUR_DOWNSCALE)
        val smallHeight = max(1, height / BLUR_DOWNSCALE)
        val small = Bitmap.createBitmap(smallWidth, smallHeight, Bitmap.Config.ARGB_8888)
        try {
            drawCover(Canvas(small), source, smallWidth, smallHeight)
            val pixels = IntArray(smallWidth * smallHeight)
            small.getPixels(pixels, 0, smallWidth, 0, 0, smallWidth, smallHeight)
            repeat(BLUR_PASSES) { boxBlur(pixels, smallWidth, smallHeight) }
            small.setPixels(pixels, 0, smallWidth, 0, 0, smallWidth, smallHeight)
            canvas.drawBitmap(small, null, RectF(0f, 0f, width.toFloat(), height.toFloat()), filter)
        } finally {
            small.recycle()
        }
    }

    private fun boxBlur(pixels: IntArray, width: Int, height: Int) {
        val buffer = IntArray(pixels.size)
        blurPass(pixels, buffer, width, height, horizontal = true)
        blurPass(buffer, pixels, width, height, horizontal = false)
    }

    private fun blurPass(source: IntArray, target: IntArray, width: Int, height: Int, horizontal: Boolean) {
        val lineCount = if (horizontal) height else width
        val length = if (horizontal) width else height
        val window = 2 * BLUR_RADIUS + 1
        for (line in 0 until lineCount) {
            for (position in 0 until length) {
                var red = 0
                var green = 0
                var blue = 0
                for (offset in -BLUR_RADIUS..BLUR_RADIUS) {
                    val sample = (position + offset).coerceIn(0, length - 1)
                    val pixel = source[if (horizontal) line * width + sample else sample * width + line]
                    red += (pixel shr 16) and 0xFF
                    green += (pixel shr 8) and 0xFF
                    blue += pixel and 0xFF
                }
                val index = if (horizontal) line * width + position else position * width + line
                target[index] = Color.rgb(red / window, green / window, blue / window)
            }
        }
    }

    private fun jpegData(bitmap: Bitmap, quality: Int): ByteArray {
        val output = ByteArrayOutputStream()
        check(bitmap.compress(Bitmap.CompressFormat.JPEG, quality, output)) { "JPEG encoding failed" }
        return output.toByteArray()
    }
}
