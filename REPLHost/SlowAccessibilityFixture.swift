/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import SwiftUI
import UIKit

/// A screen that is slow to describe itself, for tests of how idb's
/// accessibility commands treat an app that does not answer in time.
///
/// Its one element blocks the main thread for a fixed time whenever its label
/// is read, as a heavy screen does while it serializes its accessibility tree.
/// Each answer is recorded in a file in the app's data container, so a test can
/// count how many times the app did that work, including work finished after
/// the reader stopped waiting for it.
struct SlowAccessibilityFixture: UIViewControllerRepresentable {
  /// Followed by the number of seconds each read of the label blocks for.
  static let launchArgument = "--slow-accessibility-fixture"
  static let identifier = "com.facebook.idb.replhost.slow"

  /// Relative to the data container's `Library/Application Support`.
  static let answersPath = "SlowAccessibilityFixture/answers"

  static var requestedDelay: TimeInterval? {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: launchArgument) else {
      return nil
    }
    guard index + 1 < arguments.count, let delay = TimeInterval(arguments[index + 1]) else {
      fatalError("\(launchArgument) must be followed by a number of seconds")
    }
    return delay
  }

  let delay: TimeInterval

  func makeUIViewController(context: Context) -> UIViewController {
    let controller = UIViewController()
    let view: UIView = controller.view
    view.backgroundColor = .systemBackground
    let element = SlowAccessibilityElement(
      accessibilityContainer: view, delay: delay, answers: Self.answersFile())
    element.accessibilityFrameInContainerSpace = CGRect(x: 20, y: 120, width: 200, height: 44)
    view.accessibilityElements = [element]
    return controller
  }

  func updateUIViewController(_ controller: UIViewController, context: Context) {}

  /// Emptied on launch, so the count covers only this launch.
  private static func answersFile() -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let file = support.appendingPathComponent(answersPath)
    do {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    } catch {
      fatalError("Could not create the directory for \(file.path): \(error)")
    }
    guard FileManager.default.createFile(atPath: file.path, contents: nil) else {
      fatalError("Could not create \(file.path)")
    }
    return file
  }
}

private final class SlowAccessibilityElement: UIAccessibilityElement {
  private let delay: TimeInterval
  private let answers: URL

  init(accessibilityContainer container: Any, delay: TimeInterval, answers: URL) {
    self.delay = delay
    self.answers = answers
    super.init(accessibilityContainer: container)
    accessibilityIdentifier = SlowAccessibilityFixture.identifier
  }

  private var answeredThisTurn = false

  /// One serialization of the tree reads the label more than once within a
  /// single turn of the main run loop, so blocking once per turn makes each
  /// recorded answer one serialization.
  override var accessibilityLabel: String? {
    get {
      if !answeredThisTurn {
        answeredThisTurn = true
        DispatchQueue.main.async { self.answeredThisTurn = false }
        Thread.sleep(forTimeInterval: delay)
        recordAnswer()
      }
      return "Slow"
    }
    set {}
  }

  /// A lost answer would undercount the work, so failing to record one crashes
  /// the fixture rather than being skipped.
  private func recordAnswer() {
    do {
      let handle = try FileHandle(forWritingTo: answers)
      defer { try? handle.close() }
      try handle.seekToEnd()
      try handle.write(contentsOf: Data("\(Date().timeIntervalSince1970)\n".utf8))
    } catch {
      fatalError("Could not record an answer in \(answers.path): \(error)")
    }
  }
}
