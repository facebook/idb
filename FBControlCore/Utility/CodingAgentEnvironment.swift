/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Detects whether the current process is being driven by an AI coding agent.
public enum CodingAgentEnvironment {

  /// Environment variables that widely-used AI coding agents set on the tools
  /// they invoke. The presence of any one of them (with a non-empty value)
  /// indicates the process is running inside that agent.
  private static let agentEnvironmentVariables = [
    "CLAUDE_CODE",
    "CLAUDECODE",
    "CODEX_SANDBOX",
    "CURSOR_AGENT",
    "GEMINI_CLI",
    "REPLIT_AGENT",
    "AIDER_SESSION",
  ]

  /// Whether the current process is running inside an AI coding agent.
  public static var isRunningInsideAgent: Bool {
    isRunningInsideAgent(in: ProcessInfo.processInfo.environment)
  }

  /// Testable core of ``isRunningInsideAgent`` that reads from an explicit
  /// environment rather than the live process environment.
  static func isRunningInsideAgent(in environment: [String: String]) -> Bool {
    for name in agentEnvironmentVariables {
      if let value = environment[name], !value.isEmpty {
        return true
      }
    }
    // @oss-disable
    return false
  }
}
