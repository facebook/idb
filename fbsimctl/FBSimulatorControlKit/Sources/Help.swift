/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

extension Help : CustomStringConvertible {
  public var description: String {

    let classPrim = PrimitiveDesc(name: "class", desc: "A class name.")
    let filePrim = PrimitiveDesc(name: "file", desc: "A file URI.")
    let dirPrim = PrimitiveDesc(name: "dir", desc: "A directory URI.")

    func fileOpt(_ action: String) -> ParserDescription {
      return
        SequenceDesc(children: [
          FlagDesc(name: "file", desc: "The file to \(action)"),
          filePrim
        ])
    }

    func dirOpt(_ action: String) -> ParserDescription {
      return
        SequenceDesc(children: [
          FlagDesc(name: "dir", desc: "The directory to \(action)"),
          dirPrim
        ])
    }

    let buildSection = SectionDesc(tag: "build-opts", name: "Building",
                                   desc: "Build specific targets.",
                                   child: ChoiceDesc(children: [
                                     classPrim,
                                     fileOpt("build"),
                                     dirOpt("build")
                                   ]))

    let testSection = SectionDesc(tag: "test-opts", name: "Testing",
                                  desc: "Run tests on the given targets.",
                                  child: ChoiceDesc(children: [
                                    classPrim,
                                    fileOpt("test"),
                                    dirOpt("test")
                                  ]))

    let choices = ChoiceDesc(children: [
      FlagDesc(name: "version", desc: "Print the version"),
      FlagDesc(name: "help", desc: "Print the help dialog"),
      buildSection,
      testSection
    ])

    let app = SequenceDesc(children: [
      CmdDesc(cmd: "fbsimctl"),
      choices
    ])

    let desc = SectionDesc(tag: "fbsimctl", name: "Help",
                           desc: "This is an example help/usage dialog built using `ParserDescription`. This is not the actual dialog for `fbsimctl`",
                           child: app)

    // return CLI.parser.description
    return desc.normalised.usage
  }
}
