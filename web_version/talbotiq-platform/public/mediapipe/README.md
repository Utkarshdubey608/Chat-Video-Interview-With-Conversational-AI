# MediaPipe assets — Face-Fit pre-flight

The "fit your face to frame" screen (`src/features/avatar-screening/facefit/`)
uses MediaPipe FaceLandmarker on-device. It needs two assets:

| Asset | Default source | Config constant |
| ----- | -------------- | --------------- |
| **Model** (`face_landmarker.task`, ~3.7 MB) | self-hosted here (`/mediapipe/face_landmarker.task`) | `MODEL_URL` / `VITE_FACEFIT_MODEL_URL` |
| **WASM runtime** (~11 MB, one variant loads) | jsDelivr CDN, pinned to the installed version | `WASM_BASE` / `VITE_FACEFIT_WASM_BASE` |

The model is committed here so the most likely CSP/availability failure point
does not depend on a third party. If either asset fails to load, the screen
degrades gracefully to a guide-only oval + manual "I'm ready" confirm — it never
hard-blocks the candidate.

## Fully offline / Capacitor (Play Store) builds

A CDN request for the WASM may be blocked (CSP) or unavailable (offline) inside
the Android WebView. To bundle the runtime locally, copy it into this folder and
point `VITE_FACEFIT_WASM_BASE` at it:

```bash
# from talbotiq-platform/
cp -r node_modules/@mediapipe/tasks-vision/wasm public/mediapipe/wasm
# .env / build env:
#   VITE_FACEFIT_WASM_BASE=/mediapipe/wasm
```

Then `npm run build` includes it in `dist/` and `npx cap sync` ships it in the
APK/AAB. (The `wasm/` folder is git-ignored by default to keep the repo light —
commit it if your deployment needs it vendored.)

## Refreshing the model

```bash
curl -L -o public/mediapipe/face_landmarker.task \
  https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task
```
