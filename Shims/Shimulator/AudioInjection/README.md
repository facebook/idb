# Microphone injection

The audio capability of `libShimulator-iOS` plays an audio file into the
microphone input of the apps running in a booted simulator, so an app under test
hears a recording wherever it would hear the microphone.

## The pieces

| Piece | Where |
|---|---|
| The shim loaded into guest processes | `Source/Shims/Shimulator/AudioInjection/` → `:libShimulator-iOS`, shipped once in the companion's `Resources/` |

The shared Swift `ShimulatorProtocol` target owns the versioned messages, the per-capability socket path and the client that serves it. `AudioInjectionController` contributes the capability name, the typed handler and WAV decoding. `AudioInjectionHAL.swift` owns the IO-proc lifecycle, the synthetic input and the realtime sample copy. The only C is the boundary Swift cannot express: `include/IDBAudioInjectionPrivate.h` declares the private HAL symbols and the audio thread's lock-free counters, and `IDBAudioInjectionInterpose.c` holds the dyld interpose records pointing at the Swift replacements in `AudioInjectionBootstrap.swift`.

It is **not** a guest service, and there is no `audio` verb on
`SimulatorFrameworkBridge`. A separate guest process cannot change what another
process captures: each process gets its own audio from the host's audio server.

## Interpose at the HAL boundary, not above it

The shim interposes `AudioDeviceCreateIOProcID`. `AudioToolbox` asks the host's
audio server for captured audio by registering an IO proc through that
`CoreAudio` entry point, and every capture path crosses it.

Interposing anything above it covers almost nothing. Measured on an iOS 26.2
simulator, a 997 Hz tone at 0.488 of full scale, magnitude of the tone in each
recorder's own capture:

| recording API | `AudioUnitRender` interposed | `AudioDeviceCreateIOProcID` interposed |
|---|---|---|
| `AudioQueue` input | 0.000189 | 0.488277 |
| `AVAudioEngine` input tap | 0.000051 | 0.488277 |
| `AVAudioEngine` with voice processing | 0.000045 | 0.488277 |
| `AVAudioRecorder` | 0.000023 | 0.488262 |
| An app driving a `RemoteIO` unit itself | 0.488000 | 0.488277 |

`AudioQueue`, `AVAudioEngine` and `AVAudioRecorder` pull captured audio inside
`AudioToolbox`. They do call `AudioUnitRender` across an image boundary, about 95
times a second, but never on the input bus, so only an app that renders a
`RemoteIO` input bus itself is covered from there.

## No microphone needed on the host

A simulator's audio input is its host's. Only on a host without a microphone does
the shim supply one: it reports the default output device as the default input,
gives any device without input streams one mono Float32 stream at the device's
rate, and hands the IO proc a buffer for it. A host with a microphone is left
alone, and injection replaces what it captures only while a file plays. Only an
IO proc whose client asked the stream's latency -- which a recorder does and a
player does not -- is filled or counted as having heard the injection.

## Rules for the shim

idb loads `libShimulator-iOS` into every iOS test process it runs, armed or not.
Once a simulator is armed, the shim is also loaded into **every** process it
launches, through the guest `launchd`'s `DYLD_INSERT_LIBRARIES`.

- **Do nothing unless armed.** Arming also sets `IDB_AUDIO_INJECTION=1` in the
  guest `launchd`, and the shim reads it once, at load. Without it, every
  interposed function calls the original with the same arguments and returns its
  result: no thread, no extra HAL call, no synthetic input. Each entry point in
  `AudioInjectionHAL.swift` starts with that check, and the unit tests hold it.
- **Nothing blocks on the audio thread.** It reads no HAL property or file, only
  try-locks around copying samples, and never allocates or frees under that lock.
  Decoding, the socket and freeing finished audio stay on the client thread.
- **Serialize the shim's HAL reads with IO-proc creation.** A property read made
  while an IO proc is being created disturbs the device and costs the app its
  audio, so IO-proc creation and the client thread's sample-rate read hold the
  same lock.
- **Claim only what was played.** `accepted` means the audio thread took samples:
  a process that recorded once keeps its client for life, and would otherwise
  claim injections it never plays.
- **Playback position belongs to the IO proc.** Two recorders each hear the whole
  file. An injection is finished when nothing is still playing it and something
  played it to the end.
- **Key registrations on the `ioProcID` the HAL returned**, not the client data
  (`NULL` is legal) or the device (two recorders can share one).

## Two device-level routes that look right and are not

Both were measured. Neither is worth re-attempting.

- **iOS microphone injection is compiled out of the simulator runtime.**
  `AVAudioSession`'s `MicrophoneInjection` API, `AVAudioPlayer.useInjectionDevice`
  and `_AXSSetAllowsMixToUplink` all bottom out in
  `AQIONode::SetMixTapToTelephonyUplink`, which in the runtime's `AudioToolbox` is
  `mov w0, #-0x2a6f; ret` — it always returns `-10863` — while
  `SetMixTapToTelephonyUplinkAllowedByUser` is a bare `ret`.
  `isMicrophoneInjectionAvailable` is correspondingly false and
  `microphoneInjectionPermission` reads `ServiceDisabled`. Granting
  `kTCCServiceMicrophoneInjection` in the simulator's own privacy database changes
  none of it: there is no implementation behind the gate. A recorder hears such
  playback only when the Mac's speakers are audible — that is the room, not the
  audio stack.
- **Selecting a host device for the guest's microphone works, but only for real
  devices.** `sim_input_device_uid` in the simulator's
  `var/run/simulatoraudio/audiosettings.plist` genuinely re-points one simulator's
  input: the guest watches that file and re-resolves the UID, and pointing one
  simulator elsewhere leaves its neighbour untouched. But the guest can only open
  a real HAL device. Every aggregate carrying a CoreAudio process tap is either
  refused outright or puts the hardware microphone on channel 0 — the only channel
  the guest reads — so the tap is never heard. A device that would carry injected
  audio has to come from a CoreAudio server plugin in
  `/Library/Audio/Plug-Ins/HAL`, which is a host install rather than something idb
  can do per simulator.
