# FBVideoCore

The video vocabulary shared by every kind of target. `FBSimulatorControl` records and streams a Simulator's screen and `FBDeviceControl` records a physical device's; both are written against this library, and a consumer that handles video from either kind of target only needs to know this one.

It depends only on `FBControlCore`, so linking it does not bring in any target implementation.

## What it provides

- **The video capability.** `VideoTarget` is a protocol refining `Target` with two command nouns, `videoRecording` and `videoStream`. It is declared here rather than on `Target`, so `FBControlCore` does not have to know about video and a target is given the capability by the library that implements it: `FBSimulatorControl` conforms `Simulator`, and `FBDeviceControl` conforms `Device`.
- **Command protocols.** `VideoRecordingCommands` starts a recording to a file and returns a `VideoRecording` to stop it. `VideoStreamCommands` starts a stream into a `DataConsumer` and returns a `VideoStreamOperation`.
- **Stream configuration.** `VideoStreamConfiguration` describes what to produce: a `VideoStreamFormat` (H.264 or HEVC in an Annex-B, MPEG-TS or fragmented MP4 transport, MJPEG, minicap or raw BGRA), the frame rate, rate control, scale and key-frame interval, and the `DisplaySelection` to capture.
- **Container writers.** Encoded samples become bytes through an `EncodedFrameWriter`: `AnnexBFrameWriter`, `MPEGTSFrameWriter` and the fragmented MP4 writer for compressed video, `MJPEGFrameWriter`, `MinicapFrameWriter` and `BGRAFrameWriter` for the rest. The MPEG-TS and fMP4 writers also carry timed metadata alongside the video. `VideoFileWriter` records an `AVCaptureSession` to a file.

## Using it

A caller holding a concrete target reaches its video commands directly:

```swift
let recording = try await simulator.videoRecording.start(toFile: "/tmp/screen.mp4")
// ...
let file = try await recording.stop()
```

A caller holding `any Target` resolves the capability against the target types it links, naming each one rather than casting to `any VideoTarget`: a conformance declared in a library of its own is only linked into a binary when something references it.
