package com.faceliveness

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.SystemClock
import android.view.View
import android.widget.FrameLayout
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.AspectRatioStrategy
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import android.util.Size
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Result of one analysed frame, in view and image coordinates. */
data class FrameResult(
  val face: DetectedFace?,
  val frameInView: RectF?,
  val imageWidth: Int,
  val imageHeight: Int,
  val processingTimeMs: Float,
  val isLive: Boolean,
  val consecutiveLiveFrames: Int,
  val isVerified: Boolean,
)

interface FaceLivenessCameraListener {
  fun onResult(view: FaceLivenessCameraView, result: FrameResult)
  fun onVerified(view: FaceLivenessCameraView, result: FrameResult)
  fun onError(view: FaceLivenessCameraView, code: String, message: String)
}

/**
 * Front-camera preview (CameraX) that runs face detection + liveness on every frame.
 * It owns its own lifecycle: the camera runs while the view is attached, `active`,
 * and the host activity is resumed.
 */
@SuppressLint("ViewConstructor")
class FaceLivenessCameraView(context: Context) : FrameLayout(context), LifecycleOwner {

  var listener: FaceLivenessCameraListener? = null
  var hostListener: com.facebook.react.bridge.LifecycleEventListener? = null

  var active = true
    set(value) { field = value; updateRunning() }
  var hostResumed = true
    set(value) { field = value; updateRunning() }
  var livenessThreshold = NativeEngine.DEFAULT_LIVENESS_THRESHOLD
  var requiredLiveFrames = 8
  var useFrontCamera = true
    set(value) {
      if (field == value) return
      field = value
      if (running) { stopCamera(); updateRunning() }
    }
  var showFaceOverlay = true
    set(value) { field = value; overlay.invalidate() }

  private val previewView = PreviewView(context).apply {
    // TextureView-based so React Native views and our overlay compose correctly on top.
    implementationMode = PreviewView.ImplementationMode.COMPATIBLE
    scaleType = PreviewView.ScaleType.FILL_CENTER
  }
  private val overlay = OverlayView(context)
  private val lifecycleRegistry = LifecycleRegistry(this)
  private var analysisExecutor: ExecutorService? = null
  private var cameraProvider: ProcessCameraProvider? = null
  private var preview: Preview? = null
  private var analysis: ImageAnalysis? = null
  private var running = false
  private var attached = false

  // Touched on the analysis thread only.
  private var consecutiveLive = 0
  private var verifiedNotified = false

  override val lifecycle: Lifecycle get() = lifecycleRegistry

  init {
    lifecycleRegistry.currentState = Lifecycle.State.CREATED
    addView(previewView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
    addView(overlay, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
  }

  // React Native lays out only the root native view; lay out our children ourselves.
  private val measureAndLayout = Runnable {
    measure(
      MeasureSpec.makeMeasureSpec(width, MeasureSpec.EXACTLY),
      MeasureSpec.makeMeasureSpec(height, MeasureSpec.EXACTLY),
    )
    layout(left, top, right, bottom)
  }

  override fun requestLayout() {
    super.requestLayout()
    post(measureAndLayout)
  }

  override fun onAttachedToWindow() {
    super.onAttachedToWindow()
    attached = true
    updateRunning()
  }

  override fun onDetachedFromWindow() {
    attached = false
    updateRunning()
    super.onDetachedFromWindow()
  }

  /** Releases the camera for good (view dropped by React Native). */
  fun destroy() {
    attached = false
    stopCamera()
    lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
  }

  private fun updateRunning() {
    val shouldRun = active && attached && hostResumed &&
      lifecycleRegistry.currentState != Lifecycle.State.DESTROYED
    if (shouldRun && !running) startCamera() else if (!shouldRun && running) stopCamera()
  }

  private fun startCamera() {
    if (ContextCompat.checkSelfPermission(context, android.Manifest.permission.CAMERA) !=
      PackageManager.PERMISSION_GRANTED
    ) {
      listener?.onError(this, "permission-denied", "Camera permission denied.")
      return
    }
    running = true
    resetVerification()
    lifecycleRegistry.currentState = Lifecycle.State.RESUMED

    val future = ProcessCameraProvider.getInstance(context)
    future.addListener({
      if (!running) return@addListener
      try {
        val provider = future.get()
        cameraProvider = provider
        bindUseCases(provider)
      } catch (e: Exception) {
        running = false
        listener?.onError(this, "camera-unavailable", e.message ?: "Could not start the camera.")
      }
    }, ContextCompat.getMainExecutor(context))
  }

  private fun bindUseCases(provider: ProcessCameraProvider) {
    val selector = if (useFrontCamera && provider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)) {
      CameraSelector.DEFAULT_FRONT_CAMERA
    } else {
      CameraSelector.DEFAULT_BACK_CAMERA
    }
    val mirrored = selector == CameraSelector.DEFAULT_FRONT_CAMERA
    val rotation = display?.rotation ?: android.view.Surface.ROTATION_0

    // 4:3 for both so the analysed frame matches what the preview shows.
    val ratio = AspectRatioStrategy.RATIO_4_3_FALLBACK_AUTO_STRATEGY
    val newPreview = Preview.Builder()
      .setResolutionSelector(ResolutionSelector.Builder().setAspectRatioStrategy(ratio).build())
      .setTargetRotation(rotation)
      .build()
      .also { it.setSurfaceProvider(previewView.surfaceProvider) }

    // 640x480 like the Android sample: enough for the 192px detector and 80px crops.
    val newAnalysis = ImageAnalysis.Builder()
      .setResolutionSelector(
        ResolutionSelector.Builder()
          .setAspectRatioStrategy(ratio)
          .setResolutionStrategy(
            ResolutionStrategy(Size(640, 480), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER)
          )
          .build()
      )
      .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
      .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
      .setTargetRotation(rotation)
      .build()

    val executor = Executors.newSingleThreadExecutor().also { analysisExecutor = it }
    newAnalysis.setAnalyzer(executor) { image -> analyze(image, mirrored) }

    provider.unbind(*listOfNotNull(preview, analysis).toTypedArray())
    provider.bindToLifecycle(this, selector, newPreview, newAnalysis)
    preview = newPreview
    analysis = newAnalysis
  }

  private fun stopCamera() {
    running = false
    val provider = cameraProvider
    val useCases = listOfNotNull(preview, analysis)
    if (provider != null && useCases.isNotEmpty()) provider.unbind(*useCases.toTypedArray())
    analysis?.clearAnalyzer()
    preview = null
    analysis = null
    analysisExecutor?.shutdown()
    analysisExecutor = null
    if (lifecycleRegistry.currentState != Lifecycle.State.DESTROYED) {
      lifecycleRegistry.currentState = Lifecycle.State.CREATED
    }
    overlay.update(null, false)
  }

  private fun resetVerification() {
    consecutiveLive = 0
    verifiedNotified = false
  }

  private fun analyze(image: ImageProxy, mirrored: Boolean) {
    try {
      val engine = try {
        NativeEngine.shared(context)
      } catch (e: Exception) {
        post { listener?.onError(this, "engine-error", e.message ?: "Failed to load the models.") }
        return
      }
      val rotation = image.imageInfo.rotationDegrees
      val planes = image.planes
      val begin = SystemClock.elapsedRealtimeNanos()
      val faces = engine.detectYuv420(
        planes[0].buffer, planes[1].buffer, planes[2].buffer,
        image.width, image.height,
        planes[0].rowStride, planes[1].rowStride, planes[1].pixelStride,
        NativeEngine.orientationForRotation(rotation),
      )
      val elapsedMs = (SystemClock.elapsedRealtimeNanos() - begin) / 1_000_000f

      val swap = rotation == 90 || rotation == 270
      val uprightW = if (swap) image.height else image.width
      val uprightH = if (swap) image.width else image.height
      val face = faces.firstOrNull()
      val live = face != null && face.livenessScore >= livenessThreshold
      if (live) consecutiveLive++ else { consecutiveLive = 0; verifiedNotified = false }
      val verified = consecutiveLive >= requiredLiveFrames
      val notifyVerified = verified && !verifiedNotified
      if (notifyVerified) verifiedNotified = true
      val consecutive = consecutiveLive

      post {
        if (!running) return@post
        val frame = face?.let { toViewRect(it.bounds, uprightW, uprightH, mirrored) }
        overlay.update(frame, live)
        val result = FrameResult(face, frame, uprightW, uprightH, elapsedMs, live, consecutive, verified)
        listener?.onResult(this, result)
        if (notifyVerified) listener?.onVerified(this, result)
      }
    } catch (e: Exception) {
      // A bad frame should not stop the stream.
    } finally {
      image.close()
    }
  }

  /** Maps an upright-image rect to view pixels for PreviewView's FILL_CENTER (+ mirroring). */
  private fun toViewRect(bounds: RectF, imageW: Int, imageH: Int, mirrored: Boolean): RectF {
    val scale = maxOf(width / imageW.toFloat(), height / imageH.toFloat())
    val dx = (width - imageW * scale) / 2f
    val dy = (height - imageH * scale) / 2f
    val left = if (mirrored) imageW - bounds.right else bounds.left
    val right = if (mirrored) imageW - bounds.left else bounds.right
    return RectF(left * scale + dx, bounds.top * scale + dy, right * scale + dx, bounds.bottom * scale + dy)
  }

  private inner class OverlayView(context: Context) : View(context) {
    private var rect: RectF? = null
    private var live = false
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
      style = Paint.Style.STROKE
      strokeWidth = 3f * resources.displayMetrics.density
    }

    fun update(rect: RectF?, live: Boolean) {
      this.rect = rect
      this.live = live
      invalidate()
    }

    override fun onDraw(canvas: Canvas) {
      val r = rect ?: return
      if (!showFaceOverlay) return
      paint.color = if (live) Color.rgb(0x34, 0xC7, 0x59) else Color.rgb(0xFF, 0x3B, 0x30)
      val radius = r.width() / 12f
      canvas.drawRoundRect(r, radius, radius, paint)
    }
  }
}
