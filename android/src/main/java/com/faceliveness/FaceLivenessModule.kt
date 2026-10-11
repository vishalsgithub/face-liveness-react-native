package com.faceliveness

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.annotations.ReactModule
import java.io.File
import java.io.InputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors

@ReactModule(name = FaceLivenessModule.NAME)
class FaceLivenessModule(reactContext: ReactApplicationContext) :
  NativeFaceLivenessSpec(reactContext) {

  override fun getName(): String = NAME

  override fun detectInFile(path: String, livenessThreshold: Double, allFaces: Boolean, promise: Promise) {
    executor.execute {
      try {
        val engine = NativeEngine.shared(reactApplicationContext)
        // EXIF orientation is applied by the engine, so decode the raw pixels.
        val orientation = open(path).use { ExifInterface(it) }
          .getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
          .coerceIn(1, 8)
        val bitmap = open(path).use {
          BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply {
            inPreferredConfig = Bitmap.Config.ARGB_8888
          })
        } ?: throw IllegalArgumentException("Could not read an image at $path")

        // ARGB_8888 bitmaps are RGBA in memory.
        val pixels = ByteBuffer.allocateDirect(bitmap.rowBytes * bitmap.height)
        bitmap.copyPixelsToBuffer(pixels)
        val faces = engine.detectRgba(pixels, bitmap.width, bitmap.height, bitmap.rowBytes, orientation, allFaces)
        bitmap.recycle()

        val result = Arguments.createArray()
        for (face in faces) {
          result.pushMap(Arguments.createMap().apply {
            putDouble("x", face.bounds.left.toDouble())
            putDouble("y", face.bounds.top.toDouble())
            putDouble("width", face.bounds.width().toDouble())
            putDouble("height", face.bounds.height().toDouble())
            putDouble("detectionConfidence", face.detectionConfidence.toDouble())
            putDouble("livenessScore", face.livenessScore.toDouble())
            putBoolean("isLive", face.livenessScore >= livenessThreshold)
          })
        }
        promise.resolve(result)
      } catch (e: LivenessEngineException) {
        promise.reject("engine-error", e.message, e)
      } catch (e: Exception) {
        promise.reject("invalid-image", e.message ?: "Could not read the image.", e)
      }
    }
  }

  /** Opens a file path, file:// or content:// URI. */
  private fun open(path: String): InputStream {
    val uri = Uri.parse(path)
    return when (uri.scheme) {
      "content", "file" -> reactApplicationContext.contentResolver.openInputStream(uri)
        ?: throw IllegalArgumentException("Could not open $path")
      else -> File(path).inputStream()
    }
  }

  companion object {
    const val NAME = "FaceLiveness"
    private val executor = Executors.newSingleThreadExecutor()
  }
}
