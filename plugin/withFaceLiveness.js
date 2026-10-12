/**
 * Expo config plugin for @solankivishal/react-native-face-liveness.
 *
 *   "plugins": [
 *     ["@solankivishal/react-native-face-liveness", { "cameraPermission": "Custom text" }]
 *   ]
 *
 * - iOS: adds NSCameraUsageDescription (kept if the app already sets one).
 * - Android: adds the CAMERA permission (also merged from the library manifest).
 */
const {
  AndroidConfig,
  createRunOncePlugin,
  withInfoPlist,
} = require('expo/config-plugins');

const pkg = require('../package.json');

const DEFAULT_CAMERA_PERMISSION =
  'The camera is used to check that a real person is in front of the device.';

function withFaceLiveness(config, props = {}) {
  const cameraPermission = props.cameraPermission ?? DEFAULT_CAMERA_PERMISSION;

  config = withInfoPlist(config, (cfg) => {
    if (props.cameraPermission || !cfg.modResults.NSCameraUsageDescription) {
      cfg.modResults.NSCameraUsageDescription = cameraPermission;
    }
    return cfg;
  });

  config = AndroidConfig.Permissions.withPermissions(config, ['android.permission.CAMERA']);
  return config;
}

module.exports = createRunOncePlugin(withFaceLiveness, pkg.name, pkg.version);
