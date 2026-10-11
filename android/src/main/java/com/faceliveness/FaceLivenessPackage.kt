package com.faceliveness

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfo
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.facebook.react.uimanager.ViewManager

class FaceLivenessPackage : BaseReactPackage() {
  override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> =
    listOf(FaceLivenessCameraViewManager())

  override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? =
    if (name == FaceLivenessModule.NAME) FaceLivenessModule(reactContext) else null

  override fun getReactModuleInfoProvider() = ReactModuleInfoProvider {
    mapOf(
      FaceLivenessModule.NAME to ReactModuleInfo(
        FaceLivenessModule.NAME,
        FaceLivenessModule.NAME,
        false, // canOverrideExistingModule
        false, // needsEagerInit
        false, // isCxxModule
        true, // isTurboModule
      )
    )
  }
}
