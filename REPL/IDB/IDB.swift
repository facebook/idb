/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation
import ImageIO
@_implementationOnly import ReplProtocol

// The API that injected REPL code calls to drive the connected target while its
// own code runs. Everything public is nested under the single `IDB` namespace
// enum, so importing this module adds only the name `IDB` to the caller's scope --
// no command, type, or helper leaks in unqualified where it could collide with the
// user's own code or another import. UI-automation commands live under `IDB.ui`,
// e.g. `IDB.ui.tap(point)`, `IDB.ui.text("...")`, `IDB.ui.describeAll()`.
//
// The Swift module is named `IDBAPI`, not `IDB`, so the namespace type and the
// module do not share a name -- a type sharing its module's name breaks
// `.swiftinterface` generation (it emits unparseable `IDB.IDB.X` references). The
// driver auto-imports the module by the name the companion reports, so injected
// code never writes the import itself.
//
// This module is linked into `libRepl`, which serves the REPL in each context
// (DYLD-injected into the xctest process for `test`, dlopen'd by
// SimulatorFrameworkBridge for `simulator`, and DYLD-injected into a launched app
// for `app`, where libRepl starts itself). Injected code compiles against the
// matching `IDBAPI.swiftinterface`; at run time its `IDB.*` references resolve to
// this module's symbols, exported by the loaded `libRepl`. Each call encodes a
// `ReplCommand` (the shared wire type) and hands it to the host's
// `FBReplInvokeHostCommand` C entry point, resolved here with `dlsym` (it lives
// in the same loaded image, so there is no link dependency on libRepl). The only
// link dependency is `ReplProtocol`, the pure wire types shared with the
// companion -- so the request contract is one type-checked model on both sides.
//
// The calls do not throw. Losing the connection to the companion ends the session,
// so instead of surfacing a catchable error on every call it stops the submission
// outright (see `haltReplExecution`): the disposable test / simulator host exits,
// while in the app context the app keeps running and only the submission ends. A
// command that merely did not apply is ignored (best-effort). If a future command's
// failure is a meaningful result of the call, make that one `throws`.
//
// Injected code must not write to stdout/stderr: in the REPL host those file
// descriptors can alias the control socket, so a stray write corrupts the
// protocol. That is why failures are silent rather than logged.

/// Encodes `command`, sends it to the companion, and returns the parsed `result`
/// value on success, or `nil` on failure -- a command that did not apply, or a lost
/// connection. A lost connection also stops the submission via `haltReplExecution`,
/// which exits the disposable test / simulator host or simply returns in the app
/// context (leaving the app running) before this returns `nil`.
///
/// Top-level and `private`, so it is neither exported to injected code nor part
/// of the `IDB` namespace surface; the command methods below call it directly.
@discardableResult
private func perform(_ command: ReplCommand) -> Any? {
  typealias InvokeFunction = @convention(c) (UnsafeRawPointer?, Int32, UnsafeMutablePointer<Int32>?) -> UnsafeMutableRawPointer?
  guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "FBReplInvokeHostCommand") else {
    haltReplExecution() // not running inside an idb REPL host
    return nil
  }
  let invokeHostCommand = unsafeBitCast(symbol, to: InvokeFunction.self)
  // Encode the command as a binary property list so values (e.g. coordinates)
  // round-trip bit-for-bit rather than through a decimal string. It travels as
  // the raw payload of a length-prefixed frame -- there is no text envelope.
  let encoder = PropertyListEncoder()
  encoder.outputFormat = .binary
  guard let commandData = try? encoder.encode(command) else {
    return nil // a command that cannot be encoded cannot be sent; skip it
  }
  var responseLength: Int32 = 0
  let responsePtr = commandData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
    invokeHostCommand(raw.baseAddress, Int32(raw.count), &responseLength)
  }
  guard let responsePtr else {
    haltReplExecution() // the REPL host disconnected mid-command
    return nil
  }
  defer { free(responsePtr) }
  let responseData = Data(bytes: responsePtr, count: Int(responseLength))
  let response = ((try? PropertyListSerialization.propertyList(from: responseData, options: [], format: nil)) as? [String: Any]) ?? [:]
  if response["success"] as? Bool == true {
    return response["result"]
  }
  return nil
}

/// Ends the current REPL submission because the companion is no longer reachable.
/// The test and simulator hosts are disposable, so this exits the process outright
/// -- injected code can do nothing useful once the host is gone, and the driver
/// observes the halt as the session disconnecting. In the app context the host
/// outlives the session (the server resets and waits for the next client), so this
/// returns instead; the caller then ends the submission quietly by returning `nil`,
/// leaving the app running.
private func haltReplExecution() {
  if hostOutlivesSession() {
    return
  }
  exit(EXIT_FAILURE)
}

/// Whether the REPL host process outlives a single session -- true in the app
/// context (`FBReplServeSocket(..., keepListening: YES)`), false for the disposable
/// test and simulator hosts. Resolved from the loaded `libRepl` with `dlsym`, like
/// `FBReplInvokeHostCommand`; treated as false if the host predates this entry point.
private func hostOutlivesSession() -> Bool {
  typealias QueryFunction = @convention(c) () -> ObjCBool
  guard let symbol = dlsym(dlopen(nil, RTLD_NOW), "FBReplHostOutlivesSession") else {
    return false
  }
  return unsafeBitCast(symbol, to: QueryFunction.self)().boolValue
}

/// Interprets a host command's raw result as a UTF-8 string, or nil when the
/// result is absent or empty -- a command that did not apply or failed.
private func stringResult(_ value: Any?) -> String? {
  guard let data = value as? Data, !data.isEmpty else {
    return nil
  }
  return String(data: data, encoding: .utf8)
}

/// The idb command namespace. It is a caseless enum used purely to scope the API:
/// injected code reaches everything through `IDB.` (e.g. `IDB.ui`), and nothing
/// leaks into the importer's unqualified namespace.
public enum IDB {

  /// UI-automation commands for the connected target, reached through `IDB.ui`.
  public struct UI {

    /// Taps the connected target at the given point.
    public func tap(_ point: CGPoint) {
      perform(.tap(point))
    }

    /// Taps the frontmost-app accessibility element whose label contains `marker`.
    public func tap(marker: String) {
      perform(.tapMarker(marker))
    }

    /// Swipes from one point to another. `duration` is the gesture's length in
    /// seconds; `delta` is the spacing in points between intermediate touches (0
    /// uses a default). 0 values let the companion pick sensible behavior.
    public func swipe(from: CGPoint, to: CGPoint, duration: Double = 0, delta: Double = 0) {
      perform(.swipe(from: from, to: to, duration: duration, delta: delta))
    }

    /// Pinches centered at the given point. `scale` < 1 pinches in, > 1 pinches out.
    public func pinch(at center: CGPoint, scale: Double, duration: Double = 0.5, radius: Double = 100) {
      perform(.pinch(at: center, scale: scale, duration: duration, radius: radius))
    }

    /// Presses a hardware button: "home", "lock", "side_button", "siri", or "apple_pay".
    public func button(_ name: String) {
      perform(.button(name))
    }

    /// Types `string` on the hardware keyboard.
    public func text(_ string: String) {
      perform(.text(string))
    }

    /// Begins a touch at the given point. Hold it with `touchMove`, end with `touchUp`.
    public func touchDown(_ point: CGPoint) {
      perform(.touchDown(point))
    }

    /// Moves an in-progress touch to the given point.
    public func touchMove(_ point: CGPoint) {
      perform(.touchMove(point))
    }

    /// Ends an in-progress touch at the given point.
    public func touchUp(_ point: CGPoint) {
      perform(.touchUp(point))
    }

    /// Returns the connected target's accessibility hierarchy as a tree of
    /// `AXElement`, or nil if it could not be retrieved.
    public func describeAll() -> AXElement? {
      guard let data = perform(.describeAll) as? Data else {
        return nil
      }
      if let root = try? PropertyListDecoder().decode(AXElement.self, from: data) {
        return root
      }
      return try? PropertyListDecoder().decode([AXElement].self, from: data).first
    }
  }

  /// The UI-automation command namespace, reached as `IDB.ui`.
  ///
  /// A computed property rather than a stored global on purpose: injected code is
  /// compiled against the library-evolution `IDB.swiftinterface` and so reaches
  /// `ui` through a getter, but `libRepl` is built without library evolution,
  /// where a stored value would export only an addressor (no getter symbol) and
  /// the load-time lookup would fail. A computed property's getter is an ordinary
  /// exported function, resolved like the command methods. `UI` is stateless, so
  /// a fresh value per access costs nothing.
  public static var ui: UI { UI() }

  /// Screenshot commands for the connected target, reached through `IDB.screenshot`.
  public struct Screenshot {

    /// Captures the full screen to a PNG artifact on the companion and returns its
    /// path, or nil on failure. The path is on the companion's filesystem, which is
    /// where other `IDB` commands operate.
    @discardableResult
    public func capture() -> String? {
      fileResult(.full)
    }

    /// Captures `rect` (in screen points, the same coordinate space as
    /// `IDB.ui.tap`) to a PNG artifact and returns its path, or nil on failure.
    @discardableResult
    public func capture(rect: CGRect) -> String? {
      fileResult(.rect(rect))
    }

    /// Captures the frontmost-app accessibility element whose label contains
    /// `label` (the same lookup as `IDB.ui.tap(marker:)`) to a PNG artifact and
    /// returns its path, or nil on failure.
    @discardableResult
    public func capture(label: String) -> String? {
      fileResult(.element(label: label))
    }

    /// Captures the full screen and returns it as a `CGImage` (nothing is written
    /// to disk), or nil on failure.
    public func captureImage() -> CGImage? {
      imageResult(.full)
    }

    /// Captures `rect` (in screen points) and returns it as a `CGImage`, or nil on
    /// failure.
    public func captureImage(rect: CGRect) -> CGImage? {
      imageResult(.rect(rect))
    }

    /// Captures the frontmost-app accessibility element whose label contains
    /// `label` and returns it as a `CGImage`, or nil on failure.
    public func captureImage(label: String) -> CGImage? {
      imageResult(.element(label: label))
    }

    /// Saves the capture as a PNG artifact and returns its companion-side path.
    private func fileResult(_ area: ScreenshotArea) -> String? {
      stringResult(perform(.screenshot(area: area, output: .file)))
    }

    /// Returns the capture as a `CGImage`, decoded from the uncompressed TIFF the
    /// companion sends back (preserving the screen's color space).
    private func imageResult(_ area: ScreenshotArea) -> CGImage? {
      guard let data = perform(.screenshot(area: area, output: .data)) as? Data,
        !data.isEmpty,
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
      else {
        return nil
      }
      return image
    }
  }

  /// The screenshot command namespace, reached as `IDB.screenshot`. Computed for
  /// the same library-evolution reason as `ui`.
  public static var screenshot: Screenshot { Screenshot() }

  /// Video-recording commands for the connected target, reached through `IDB.video`.
  public struct Video {

    /// Starts recording the connected target's screen into an auto-named file in
    /// the session's temporary directory. Only one recording runs at a time;
    /// returns false if one is already in progress or recording could not start.
    @discardableResult
    public func startRecording() -> Bool {
      guard let data = perform(.startRecording) as? Data else {
        return false
      }
      return !data.isEmpty
    }

    /// Stops the in-progress recording and returns the companion-side path to the
    /// recorded file, or nil if no recording was in progress. The path is on the
    /// companion's filesystem, which is the correct path for other `IDB` commands.
    @discardableResult
    public func stopRecording() -> String? {
      stringResult(perform(.stopRecording))
    }
  }

  /// The video command namespace, reached as `IDB.video`. Computed for the same
  /// library-evolution reason as `ui`.
  public static var video: Video { Video() }
}
