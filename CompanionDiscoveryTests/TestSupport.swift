/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
import Foundation

/// Shared helpers for the CompanionDiscovery tests.
enum TestSupport {
  /// A unique udid for a test, prefixed so it can't collide with a real
  /// simulator/device or with another parallel test.
  static func uniqueUDID() -> String {
    "TEST-\(UUID().uuidString)"
  }

  /// Creates a unique temporary directory and returns its path. The caller is
  /// responsible for removing it.
  static func makeTemporaryDirectory() -> String {
    let path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("companion_discovery_tests_\(UUID().uuidString)")
    try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    return path
  }

  /// A short, unique AF_UNIX socket path under `/tmp`. The `sun_path` field is
  /// only ~104 bytes, so the long `NSTemporaryDirectory()` paths can overflow it.
  static func shortSocketPath() -> String {
    "/tmp/cdt_\(UUID().uuidString.prefix(8)).sock"
  }

  /// Writes `script` to a unique temporary executable file and returns its path,
  /// for use as a fake `idb_companion`. The caller removes its parent directory.
  static func makeExecutableScript(_ script: String) throws -> String {
    let path = (makeTemporaryDirectory() as NSString).appendingPathComponent("fake_idb_companion")
    try script.write(toFile: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    return path
  }

  /// A fake companion that echoes the requested `--grpc-domain-sock` value back
  /// as `grpc_path` (the v1 startup handshake the spawner reads), then exits.
  static let echoSocketScript = """
    #!/bin/bash
    path=""
    prev=""
    for arg in "$@"; do
      if [ "$prev" = "--grpc-domain-sock" ]; then path="$arg"; fi
      prev="$arg"
    done
    printf '{"grpc_path": "%s"}\\n' "$path"
    """

  /// A fake `idb2`: derives the conventional v2 socket path from its `--udid`,
  /// records its argv at `<socket>.args`, then prints the bare path (the v2
  /// startup handshake) and exits. The `/tmp/idb2` prefix mirrors
  /// `CompanionPaths(version: .v2)`.
  static let idb2CompanionScript = """
    #!/bin/bash
    udid=""
    prev=""
    for arg in "$@"; do
      if [ "$prev" = "--udid" ]; then udid="$arg"; fi
      prev="$arg"
    done
    socket=$(printf '/tmp/idb2/%s_companion.sock' "$udid")
    echo "$*" > "$socket.args"
    printf '%s\\n' "$socket"
    """

  /// Creates and binds a listening AF_UNIX socket at `path`, returning its fd.
  /// The caller closes the fd and unlinks the path.
  static func makeListeningSocket(at path: String) -> Int32 {
    try? FileManager.default.createDirectory(
      atPath: (path as NSString).deletingLastPathComponent,
      withIntermediateDirectories: true)

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    precondition(fd >= 0, "socket() failed")
    unlink(path)

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    precondition(path.utf8.count < capacity, "socket path too long for sun_path")
    withUnsafeMutablePointer(to: &addr.sun_path) { rawPointer in
      rawPointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
        _ = strncpy(destination, path, capacity - 1)
      }
    }

    let length = socklen_t(MemoryLayout<sockaddr_un>.size)
    let bindResult = withUnsafePointer(to: &addr) { addrPointer in
      addrPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        bind(fd, sockaddrPointer, length)
      }
    }
    precondition(bindResult == 0, "bind() failed (errno \(errno))")
    precondition(listen(fd, 1) == 0, "listen() failed (errno \(errno))")
    return fd
  }
}
