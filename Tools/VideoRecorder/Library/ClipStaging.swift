/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Where a clip and the report beside it are written while they are being made, so that nothing
/// another process can see exists until both are complete.
///
/// Cutting a clip refuses an output that already exists, and that refusal is checked before any
/// decoding starts. It cannot hold for the length of a transcode: a file that appears at the
/// destination in the meantime belongs to whoever created it. So the promotion refuses again, by
/// moving rather than replacing, and this invocation removes only what it staged itself.
public struct ClipStaging: Sendable {
  /// The directory holding both staged files, which this invocation owns entirely.
  public let directory: URL
  /// Where the clip is written before it is promoted.
  public let clip: URL
  /// Where the clip's report is written before it is promoted.
  public let report: URL

  /// Stage beside the destination, so promoting is a rename within one volume rather than a copy.
  public init(for destination: URL, using fileManager: FileManager = .default) throws {
    directory = try fileManager.url(
      for: .itemReplacementDirectory,
      in: .userDomainMask,
      appropriateFor: destination.deletingLastPathComponent(),
      create: true
    )
    clip = directory.appendingPathComponent(destination.lastPathComponent)
    report = directory.appendingPathComponent(Self.reportName(for: destination))
  }

  /// The report a clip is described by: the clip's own name with `.json` after it.
  public static func reportURL(for destination: URL) -> URL {
    destination.deletingLastPathComponent().appendingPathComponent(reportName(for: destination))
  }

  /// Move both staged files to where they are published, replacing nothing that is already
  /// there, and taking the clip back if its report cannot be placed beside it.
  ///
  /// The two moves are not one atomic step, so there is a window between them. What is taken back
  /// in that window is only the file this invocation put there, identified by the file it turned
  /// out to be: a publisher that replaced it in between owns what is at that path now, and this
  /// leaves it alone rather than deleting someone else's clip.
  public func promote(to destination: URL, using fileManager: FileManager = .default) throws {
    try fileManager.moveItem(at: clip, to: destination)
    let published = Self.identity(of: destination, using: fileManager)
    do {
      try fileManager.moveItem(at: report, to: Self.reportURL(for: destination))
    } catch {
      if let published, published == Self.identity(of: destination, using: fileManager) {
        try? fileManager.removeItem(at: destination)
      }
      throw error
    }
  }

  /// Remove everything staged, whether or not any of it was promoted. Nothing outside the staging
  /// directory is reachable from here, so nothing outside it can be removed by mistake.
  public func discard(using fileManager: FileManager = .default) {
    try? fileManager.removeItem(at: directory)
  }

  /// Which file a path is, rather than what it is called.
  private static func identity(of url: URL, using fileManager: FileManager) -> UInt64? {
    let attributes = try? fileManager.attributesOfItem(atPath: url.path)
    return (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
  }

  private static func reportName(for destination: URL) -> String {
    "\(destination.lastPathComponent).json"
  }
}
