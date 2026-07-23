/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import PackagePlugin

// Stamps the build date/time into a generated BuildInfo.swift so the idb-repl
// executable can reference `kBuildDate` / `kBuildTime` (used by `--version`). This
// is the Swift Package Manager equivalent of the `Generate BuildInfo.swift`
// preBuildScript in the xcodebuild build and the `:BuildInfo` genrule in the Buck
// build. Running it as a prebuild command keeps the generated file out of the
// shared REPL/CLI sources, so the xcodebuild and Buck builds are unaffected.
@main
struct GenerateBuildInfo: BuildToolPlugin {
  func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
    let outputFile = context.pluginWorkDirectory.appending("BuildInfo.swift")
    return [
      .prebuildCommand(
        displayName: "Generate BuildInfo.swift",
        executable: .init("/bin/sh"),
        arguments: [
          "-c",
          #"{ date +'let kBuildDate = "%b %-d %Y"'; date +'let kBuildTime = "%H:%M:%S"'; } > "\#(outputFile.string)""#,
        ],
        outputFilesDirectory: context.pluginWorkDirectory
      )
    ]
  }
}
