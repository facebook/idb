# FBSimulatorVideo

Records and streams the screen of an iOS Simulator. It is the Simulator's video capability, added onto `Simulator` from outside `FBSimulatorControl`: a consumer that does not need video does not link it, and one that does depends on this library alongside `FBSimulatorControl`.

It builds on two other libraries. `FBSimulatorControl` provides the framebuffer it reads, and [`FBVideoCore`](../FBVideoCore/README.md) provides the configuration, command protocols and container writers it produces through.

## From framebuffer to video

`FBSimulatorControl` exposes a booted Simulator's screen as an `IOSurface`-backed `Framebuffer`. An `IOSurface` is cheap to wrap as a `CVPixelBuffer`, the input VideoToolbox encodes from, so `SimulatorVideoStream` encodes the Simulator's screen without copying a bitmap per frame.

- **Cadence.** By default a stream is variable-frame-rate: a frame is pushed only when the framebuffer reports that the Simulator rendered one, so an idle screen costs nothing. A fixed frame rate drives pushes from a drift-corrected clock instead, and skips the deadlines a stall consumed rather than emitting a burst of late frames.
- **Encoding.** H.264 and HEVC are encoded with VideoToolbox, hardware where the host has it. MJPEG, minicap and raw BGRA frames are also available, and the frames are scaled and padded to the configured output dimensions.
- **Overlays.** Bars and shapes rendered by `OverlayRenderer` are composited over each frame, in a margin added around the screen or over it. Updating an overlay pushes a frame even when the screen has not changed.
- **Output.** A stream writes into a `DataConsumer` through the `FBVideoCore` container writers, with timed metadata in the MPEG-TS and fragmented MP4 transports. `SimulatorVideo` records to an MP4 or MOV file instead, optionally adding a QuickTime chapter track once the recording is finished.

## Using it

The `videoRecording` and `videoStream` command nouns are available on a `Simulator` once this library is imported:

```swift
import FBSimulatorVideo

let recording = try await simulator.videoRecording.start(toFile: "/tmp/screen.mp4")
// ...
let file = try await recording.stop()
```

A consumer that drives the pipeline itself, for example to composite its own overlays, connects a framebuffer and builds the stream directly with `SimulatorVideoStream.start(framebuffer:configuration:to:logger:)`.

## The recorder session

`Recorder/` holds the session setup and the line-oriented stdin protocol that the `sim-video` tool uses, so other local clients can drive a recording the same way. The protocol is documented in [the `sim-video` README](../Tools/VideoRecorder/README.md).
