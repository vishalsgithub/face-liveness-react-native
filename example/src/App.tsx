import { useEffect, useState } from 'react';
import {
  Image,
  Platform,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import {
  DEFAULT_LIVENESS_THRESHOLD,
  FaceLiveness,
  FaceLivenessCamera,
  type CameraError,
  type LivenessResult,
} from 'react-native-face-liveness';

const REQUIRED_LIVE_FRAMES = 8;

// Sample photo used by the self-test on launch (logs `face_liveness self-test`).
// Android reads it from the app's external files dir:
//   adb push face.jpg /sdcard/Android/data/com.xpertnest.liveness/files/face.jpg
const SAMPLE_PHOTO =
  Platform.OS === 'ios'
    ? (Image.resolveAssetSource(require('./face.jpg'))?.uri ?? '')
    : '/sdcard/Android/data/com.xpertnest.liveness/files/face.jpg';

export default function App() {
  const [result, setResult] = useState<LivenessResult | null>(null);
  const [error, setError] = useState<CameraError | null>(null);
  const [verified, setVerified] = useState(false);
  const [strict, setStrict] = useState(false);
  const [selfTest, setSelfTest] = useState('Sample photo: checking…');
  const threshold = strict ? 0.97 : DEFAULT_LIVENESS_THRESHOLD;

  useEffect(() => {
    FaceLiveness.detectInFile(SAMPLE_PHOTO)
      .then((faces) => {
        const f = faces[0];
        setSelfTest(
          f
            ? `Sample photo: ${f.isLive ? 'real' : 'spoof'} ${f.livenessScore.toFixed(3)}`
            : 'Sample photo: no face'
        );
        console.log('face_liveness self-test', JSON.stringify(faces));
      })
      .catch((e) => setSelfTest(`Sample photo: ${String(e)}`));
  }, []);

  const face = result?.face;
  const status = error
    ? { title: error.message, color: '#FF9500' }
    : !result
      ? { title: 'Starting camera…', color: '#8E8E93' }
      : !face
        ? { title: 'Position your face in the frame', color: '#8E8E93' }
        : result.isVerified
          ? { title: 'Real face', color: '#34C759' }
          : face.isLive
            ? { title: 'Checking…', color: '#0A84FF' }
            : { title: 'Spoof detected', color: '#FF3B30' };

  return (
    <View style={styles.container}>
      <FaceLivenessCamera
        style={StyleSheet.absoluteFill}
        livenessThreshold={threshold}
        requiredLiveFrames={REQUIRED_LIVE_FRAMES}
        onResult={(r) => {
          setResult(r);
          if (!r.face?.isLive) setVerified(false);
        }}
        onVerified={(r) => {
          setVerified(true);
          console.log('face_liveness verified', r.face?.livenessScore);
        }}
        onError={setError}
      />

      <TouchableOpacity
        style={styles.strictButton}
        onPress={() => setStrict((s) => !s)}
      >
        <Text style={styles.strictText}>
          {strict ? 'Strict 0.970' : 'Default 0.915'}
        </Text>
      </TouchableOpacity>

      <View style={styles.card}>
        <View style={styles.row}>
          <Text style={[styles.title, { color: status.color }]}>
            {verified ? '✓ ' : ''}
            {status.title}
          </Text>
          {face && (
            <Text style={styles.score}>{face.livenessScore.toFixed(3)}</Text>
          )}
        </View>
        <View style={styles.track}>
          <View
            style={[
              styles.bar,
              {
                backgroundColor: status.color,
                width: `${Math.min(1, (result?.consecutiveLiveFrames ?? 0) / REQUIRED_LIVE_FRAMES) * 100}%`,
              },
            ]}
          />
        </View>
        <Text style={styles.caption}>
          Threshold {threshold.toFixed(3)} ·{' '}
          {Math.round(result?.processingTimeMs ?? 0)} ms / frame
        </Text>
        <Text style={styles.caption}>{selfTest}</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#000' },
  strictButton: {
    position: 'absolute',
    top: 64,
    right: 16,
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 18,
    backgroundColor: 'rgba(28,28,30,0.8)',
  },
  strictText: { color: '#fff', fontWeight: '600' },
  card: {
    position: 'absolute',
    left: 16,
    right: 16,
    bottom: 40,
    padding: 16,
    borderRadius: 16,
    backgroundColor: 'rgba(28,28,30,0.88)',
  },
  row: { flexDirection: 'row', alignItems: 'center' },
  title: { flex: 1, fontSize: 17, fontWeight: '600' },
  score: {
    color: '#fff',
    fontSize: 17,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },
  track: {
    height: 6,
    borderRadius: 3,
    marginTop: 12,
    backgroundColor: 'rgba(255,255,255,0.15)',
    overflow: 'hidden',
  },
  bar: { height: 6, borderRadius: 3 },
  caption: { color: '#AEAEB2', fontSize: 12, marginTop: 8 },
});
