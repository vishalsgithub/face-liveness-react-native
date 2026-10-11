package com.faceliveness

import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.LifecycleEventListener
import com.facebook.react.bridge.WritableMap
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.uimanager.SimpleViewManager
import com.facebook.react.uimanager.ThemedReactContext
import com.facebook.react.uimanager.UIManagerHelper
import com.facebook.react.uimanager.ViewManagerDelegate
import com.facebook.react.uimanager.annotations.ReactProp
import com.facebook.react.uimanager.events.Event
import com.facebook.react.viewmanagers.FaceLivenessCameraViewManagerDelegate
import com.facebook.react.viewmanagers.FaceLivenessCameraViewManagerInterface

@ReactModule(name = FaceLivenessCameraViewManager.NAME)
class FaceLivenessCameraViewManager : SimpleViewManager<FaceLivenessCameraView>(),
  FaceLivenessCameraViewManagerInterface<FaceLivenessCameraView> {

  private val delegate = FaceLivenessCameraViewManagerDelegate(this)

  override fun getDelegate(): ViewManagerDelegate<FaceLivenessCameraView> = delegate

  override fun getName(): String = NAME

  override fun createViewInstance(context: ThemedReactContext): FaceLivenessCameraView {
    val view = FaceLivenessCameraView(context)
    view.listener = Listener(context)
    // Pause the camera while the app is in the background.
    val hostListener = object : LifecycleEventListener {
      override fun onHostResume() { view.hostResumed = true }
      override fun onHostPause() { view.hostResumed = false }
      override fun onHostDestroy() { view.destroy() }
    }
    context.addLifecycleEventListener(hostListener)
    view.hostListener = hostListener
    return view
  }

  override fun onDropViewInstance(view: FaceLivenessCameraView) {
    view.hostListener?.let { (view.context as? ThemedReactContext)?.removeLifecycleEventListener(it) }
    view.hostListener = null
    view.destroy()
    super.onDropViewInstance(view)
  }

  @ReactProp(name = "active", defaultBoolean = true)
  override fun setActive(view: FaceLivenessCameraView, value: Boolean) {
    view.active = value
  }

  @ReactProp(name = "livenessThreshold", defaultFloat = 0.915f)
  override fun setLivenessThreshold(view: FaceLivenessCameraView, value: Float) {
    view.livenessThreshold = value
  }

  @ReactProp(name = "requiredLiveFrames", defaultInt = 8)
  override fun setRequiredLiveFrames(view: FaceLivenessCameraView, value: Int) {
    view.requiredLiveFrames = maxOf(1, value)
  }

  @ReactProp(name = "cameraPosition")
  override fun setCameraPosition(view: FaceLivenessCameraView, value: String?) {
    view.useFrontCamera = value != "back"
  }

  @ReactProp(name = "showFaceOverlay", defaultBoolean = true)
  override fun setShowFaceOverlay(view: FaceLivenessCameraView, value: Boolean) {
    view.showFaceOverlay = value
  }

  override fun getExportedCustomDirectEventTypeConstants(): MutableMap<String, Any> = mutableMapOf(
    EVENT_RESULT to mapOf("registrationName" to "onLivenessResult"),
    EVENT_VERIFIED to mapOf("registrationName" to "onVerified"),
    EVENT_ERROR to mapOf("registrationName" to "onCameraError"),
  )

  private class Listener(private val context: ThemedReactContext) : FaceLivenessCameraListener {
    override fun onResult(view: FaceLivenessCameraView, result: FrameResult) =
      dispatch(view, EVENT_RESULT, resultMap(view, result))

    override fun onVerified(view: FaceLivenessCameraView, result: FrameResult) =
      dispatch(view, EVENT_VERIFIED, resultMap(view, result))

    override fun onError(view: FaceLivenessCameraView, code: String, message: String) =
      dispatch(view, EVENT_ERROR, Arguments.createMap().apply {
        putString("code", code)
        putString("message", message)
      })

    private fun resultMap(view: FaceLivenessCameraView, r: FrameResult): WritableMap {
      // React Native layout uses dp; the view reports pixels.
      val density = view.resources.displayMetrics.density
      return Arguments.createMap().apply {
        val face = r.face
        putBoolean("hasFace", face != null)
        putBoolean("isLive", r.isLive)
        putDouble("livenessScore", (face?.livenessScore ?: 0f).toDouble())
        putDouble("detectionConfidence", (face?.detectionConfidence ?: 0f).toDouble())
        val frame = r.frameInView
        putDouble("frameX", ((frame?.left ?: 0f) / density).toDouble())
        putDouble("frameY", ((frame?.top ?: 0f) / density).toDouble())
        putDouble("frameWidth", ((frame?.width() ?: 0f) / density).toDouble())
        putDouble("frameHeight", ((frame?.height() ?: 0f) / density).toDouble())
        putDouble("boundsX", (face?.bounds?.left ?: 0f).toDouble())
        putDouble("boundsY", (face?.bounds?.top ?: 0f).toDouble())
        putDouble("boundsWidth", (face?.bounds?.width() ?: 0f).toDouble())
        putDouble("boundsHeight", (face?.bounds?.height() ?: 0f).toDouble())
        putInt("imageWidth", r.imageWidth)
        putInt("imageHeight", r.imageHeight)
        putDouble("processingTimeMs", r.processingTimeMs.toDouble())
        putInt("consecutiveLiveFrames", r.consecutiveLiveFrames)
        putBoolean("isVerified", r.isVerified)
      }
    }

    private fun dispatch(view: FaceLivenessCameraView, name: String, data: WritableMap) {
      val dispatcher = UIManagerHelper.getEventDispatcherForReactTag(context, view.id) ?: return
      dispatcher.dispatchEvent(CameraEvent(UIManagerHelper.getSurfaceId(view), view.id, name, data))
    }
  }

  private class CameraEvent(
    surfaceId: Int,
    viewId: Int,
    private val name: String,
    private val data: WritableMap,
  ) : Event<CameraEvent>(surfaceId, viewId) {
    override fun getEventName(): String = name
    override fun getEventData(): WritableMap = data
  }

  companion object {
    const val NAME = "FaceLivenessCameraView"
    const val EVENT_RESULT = "topLivenessResult"
    const val EVENT_VERIFIED = "topVerified"
    const val EVENT_ERROR = "topCameraError"
  }
}
