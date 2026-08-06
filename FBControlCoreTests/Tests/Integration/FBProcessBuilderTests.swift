/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

/// Pins the parts of `FBProcessBuilder`'s IO behaviour that its headers do not
/// describe accurately: what an unconfigured builder does with output, what a
/// `with*` call does to the receiver, and the two unrelated behaviours that are
/// both named after `/dev/null`.
///
/// Nothing here asserts a desirable design. Each case records what callers
/// observe today so that a later replacement has to either reproduce it or
/// change it deliberately.
@Suite
struct FBProcessBuilderTests {

  private static func shell(_ script: String) -> FBProcessBuilder<NSNull, NSData, NSData> {
    FBProcessBuilder<NSNull, NSData, NSData>.withLaunchPath("/bin/sh", arguments: ["-c", script])
  }

  // MARK: - Default sinks

  @Test("An unconfigured builder buffers stdout in memory as a String, not the NSData its signature promises")
  func defaultStandardOutputSinkIsAnInMemoryString() async throws {
    let process = try await bridgeFBFuture(
      Self.shell("echo hello").runUntilCompletion(withAcceptableExitCodes: nil))

    // `+withLaunchPath:` is typed `<NSNull, NSData, NSData>` and documented as
    // "stdout is written to NSData", but the default sink is
    // `+outputToStringBackedByMutableData`, which yields an NSString with a
    // single trailing newline stripped.
    let observed: AnyObject? = process.stdOut
    #expect(observed is NSString)
    #expect(!(observed is NSData))
    #expect(observed as? String == "hello")
  }

  @Test("An unconfigured builder buffers stderr in memory as a String too")
  func defaultStandardErrorSinkIsAnInMemoryString() async throws {
    let process = try await bridgeFBFuture(
      Self.shell("echo oops 1>&2").runUntilCompletion(withAcceptableExitCodes: nil))

    let observed: AnyObject? = process.stdErr
    #expect(observed is NSString)
    #expect(observed as? String == "oops")
  }

  // MARK: - Builder mutation

  @Test("A with* method mutates and returns the receiver rather than deriving a new builder")
  func mutatingASinkAliasesTheReceiver() async throws {
    let base = Self.shell("test -e /dev/fd/1")

    // The declared return type reparameterises stdout to NSNull, but no new
    // builder is produced. `base` and `derived` are one object, so `base`'s own
    // NSData stdout parameter is now a lie about its own contents.
    let derived: FBProcessBuilder<NSNull, NSNull, NSData> = base.withStdOutToDevNull()
    #expect(base === derived)

    // Running `base` observes the mutation that was applied through `derived`.
    let process = try await bridgeFBFuture(base.runUntilCompletion(withAcceptableExitCodes: nil))
    #expect(process.stdOut == nil)
  }

  // MARK: - The two dev nulls

  @Test("withStdOutToDevNull leaves the child with a closed descriptor, not the null device")
  func builderDevNullClosesTheChildDescriptor() async throws {
    // `/dev/fd/N` exists on devfs only while fd N is open in the calling
    // process, so `test -e` is a direct probe of whether stdout was handed over.
    let closed = try await bridgeFBFuture(
      Self.shell("test -e /dev/fd/1")
        .withStdOutToDevNull()
        .runUntilCompletion(withAcceptableExitCodes: nil))

    // `withStdOutToDevNull` sets the stdout sink to nil, which produces no
    // `posix_spawn` file action at all. Under POSIX_SPAWN_CLOEXEC_DEFAULT the
    // child therefore starts with fd 1 closed.
    #expect(closed.exitCode.result?.int32Value == 1)

    let connected = try await bridgeFBFuture(
      Self.shell("test -e /dev/fd/1").runUntilCompletion(withAcceptableExitCodes: nil))
    #expect(connected.exitCode.result?.int32Value == 0)
  }

  @Test("FBProcessIO.outputToDevNull attaches descriptor -1, so it names no file at all")
  func nullDeviceOutputAttachesNoDescriptor() async throws {
    let io = FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull()
    let attachment = try await bridgeFBFuture(io.attach())

    #expect(attachment.stdOut?.fileDescriptor == -1)
    #expect(attachment.stdErr?.fileDescriptor == -1)

    try await bridgeFBFutureVoid(attachment.detach())
  }

  @Test("FBProcessIO.outputToDevNull cannot be spawned by the host engine")
  func nullDeviceOutputCannotBeSpawnedOnTheHost() async throws {
    let configuration = FBProcessSpawnConfiguration(
      launchPath: "/bin/sh",
      arguments: ["-c", "true"],
      environment: [:],
      io: FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull(),
      mode: .default)

    // Descriptor -1 cannot be duplicated onto stdout, so the launch fails
    // outright. Only the file-based attachment below resolves to a usable sink.
    await #expect(throws: (any Error).self) {
      _ = try await bridgeFBFuture(
        FBSubprocess<AnyObject, AnyObject, AnyObject>.launchProcess(with: configuration, logger: nil))
    }
  }

  @Test("FBProcessIO.outputToDevNull resolves to the literal /dev/null only on the file path")
  func nullDeviceOutputIsAPathOnlyWhenAttachedViaFile() async throws {
    let io = FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull()
    let attachment = try await bridgeFBFuture(io.attachViaFile())

    #expect(attachment.stdOut?.filePath == "/dev/null")
    #expect(attachment.stdErr?.filePath == "/dev/null")

    try await bridgeFBFutureVoid(attachment.detach())
  }
}
