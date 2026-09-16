# Simulator video tool

`sim-video` records or streams video from a booted simulator. It runs locally on macOS and connects directly to the simulator framebuffer. Build the full distribution with `./build.sh build all`; the executable is `Build/Distribution/sim-video`.

```sh
Build/Distribution/sim-video record recording.mov --set "$DEVICE_SET_PATH" --udid "$DEVICE_UDID" \
  --encoding auto --bar top:48 bottom:48 --screenshot-dir screenshots
```

`record` writes a video file. H.264 is the default; `hevc` and `mjpeg` are also available. `auto` tries hardware HEVC, then JPEG with software encoding allowed if HEVC cannot produce frames. `auto` and `mjpeg` require a `.mov` output. H.264 and HEVC accept `.mov` or `.mp4`. Existing output files are rejected. If recording fails and leaves a partial file, it is retained for inspection; use a new output path when retrying.

`stream` writes raw video to a path or `-` for stdout. Its encodings are `h264`, `hevc`, `mjpeg`, `minicap`, and `bgra`. H.264 and HEVC support `--transport annex-b`, `mpegts`, or `fmp4` (default: `annex-b`). Streaming MJPEG requires a hardware encoder.

Shared recording and streaming options are: `--fps`, `--scale`, `--compression-quality`, `--avg-bitrate`, `--key-frame-rate`, `--bar`, `--bar-stats`, `--overlay-coord-space`, and `--screenshot-dir`. Quality and bitrate are mutually exclusive. Recording and streaming default to variable frame rate: frames are produced when the screen or overlays change. `--fps 0` explicitly selects this behavior; a positive `--fps` selects a fixed cadence. Bars use `position[:size][:pad|overlay]`, with size 24 and padding by default.

## Controlling a session

From a terminal, stop recording with Ctrl+C. A parent process can supply commands through a pipe.

With piped stdin and no `--duration`, send one JSON object per line. This is a one-way protocol with no request IDs or responses; it is not JSON-RPC 2.0. Commands execute in order. Logs go to stderr; stdout remains available for video bytes.

```json
{"method":"bar","params":{"position":"top","content":"text","text":"test_install","fit":true}}
{"method":"bar","params":{"position":"bottom","content":"text","text":"idb install Example.app","fit":true}}
{"method":"chapter","params":{"text":"test_install"}}
{"method":"screenshot","params":{"index":1}}
{"method":"shutdown"}
```

| Method | Parameters | Effect |
|---|---|---|
| `bar` | `position`, optional `content`, `text`, `fit` | Set a configured bar to `text` or `stats`; omitted content hides it. |
| `overlay` | `overlays` | Replace overlay shapes; an empty array clears them while retaining active bars. |
| `chapter` | `text` | Add a timed chapter; updates at the same video frame keep the latest title. |
| `screenshot` | `index` | Atomically write `screenshot_<index>.png` in the configured directory, including prior overlay updates. |
| `force_keyframe` | none | Make the next encoded frame a keyframe, so a consumer that just joined or lost frames can decode immediately instead of waiting for the next periodic one. |
| `shutdown` | none | Stop and finalize. |

Legacy `topStatus` and `bottomStatus` commands remain accepted. Malformed or unknown commands are logged and the session continues. Closing stdin, SIGINT, and SIGTERM also stop a session. With `--duration`, recording stops after that duration or a signal and does not process stdin commands.

After recording stops, the tool decodes a frame and checks for a positive duration. Success writes `<output>.json` with the selected encoding, dimensions, and duration. This distinguishes a playable recording from a successfully closed empty file. A force-killed process cannot guarantee a finalized file.

JPEG/MOV avoids requiring an H.264 or HEVC hardware encoder, using the existing VideoToolbox and AVFoundation pipeline without a transcoder. Software JPEG availability depends on the macOS installation. JPEG recordings are readable by AVFoundation; browser playback support varies. GitHub runner support must be confirmed by its own CI run.

## Shared implementation

`Library/` contains stdin handling, bar configuration, and session setup. The CLI uses this library so other local clients can share the same protocol implementation. Frame composition, encoding, and file writing remain in the existing simulator control APIs.
