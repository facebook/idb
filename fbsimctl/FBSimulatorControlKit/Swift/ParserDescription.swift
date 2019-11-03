/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/**
 * ParserDescription
 *
 * Metadata associated with a parser. Describes the format that this parser
 * recognises, and provides ways to represent that in a human readable format
 * that can be used, for example, in a usage dialog.
 */
public protocol ParserDescription: CustomStringConvertible {
  /**
   * normalised: ParserDescription
   *
   * Convert the description into a normal form whilst preserving its meaning,
   * by getting rid of redundant information (such as sequences with only one
   * sub-description, or a choice nested within a choice).
   */
  var normalised: ParserDescription { get }

  /**
   * isDelimited: Bool
   *
   * When the summary of this description is printed as part of a larger
   * summary, is it unambiguous, when reading the larger summary, which parts of
   * it belong to this description and which parts belong to others.
   *
   * If it is not obvious, then the output can be disambiguated using the
   * `delimitedSummary` property, which will wrap the summary in square
   * brackets.
   */
  var isDelimited: Bool { get }

  /**
   * summary: String
   *
   * A summary of the format corresponding to this description.
   */
  var summary: String { get }

  /**
   * children: [ParserDescription]
   *
   * Get all the immediate children of a particular description.
   */
  var children: [ParserDescription] { get }
}

/**
 * delimit(String) -> String
 *
 * Wrap the given string in delimiters so it has a well-defined beginning and
 * end
 */
internal func delimit(_ str: String) -> String {
  return "{{ \(str) }}"
}

extension ParserDescription {
  /**
   * delimitedSummary: String
   *
   * A version of the summary that is guaranteed to have a well-defined
   * beginning and end.
   */
  public var delimitedSummary: String {
    if isDelimited {
      return summary
    } else {
      return delimit(summary)
    }
  }

  public var description: String {
    return summary
  }

  /**
   * findAll<D : ParserDescription>(_ descs: inout [D])
   *
   * Find all `D`-typed descriptions reachable from this description that are
   * not also descendants of a `SectionDesc` that is reachable from this
   * description, and add them to `descs`.
   *
   * Given:
   *
   *     A [D1, B [D2], SectionDesc[D3], C [D4]]
   *
   * We expect this function to append the following to `descs`:
   *
   *     [D1, D2, D4]
   */
  public func findAll<D: ParserDescription>(_ descs: inout [D]) {
    for child in children {
      switch child {
      case let d as D:
        descs.append(d)
      default:
        break
      }

      if !(child is SectionDesc) {
        child.findAll(&descs)
      }
    }
  }
}

/**
 * LeafParserDescription
 *
 * Specialisation of `ParserDescription` that has no children.
 */
public protocol LeafParserDescription: ParserDescription {}

extension LeafParserDescription {
  public var children: [ParserDescription] { return [] }
}

/**
 * DEF_FMT: String
 *
 * Format for presenting a name and its description on a single line. The
 * format indents the definition by one tabstop, then displays the name, in a
 * 25 character wide window, left-aligned and padded with spaces (if necessary),
 * followed by another tab, and then the definition.
 */
internal let DEF_FMT = "\t%-25s\t%s"

/**
 * PrimitiveDesc(name:, desc:)
 *
 * Describes a primitive piece of data. Examples include integers, floats,
 * file and directory URIs etc.
 */
public struct PrimitiveDesc: LeafParserDescription {
  let name: String
  let desc: String

  public var normalised: ParserDescription { return self }

  public var isDelimited: Bool { return true }

  public var summary: String { return "<\(name)>" }

  public var description: String {
    return String(format: DEF_FMT,
                  (summary as NSString).utf8String!,
                  (desc as NSString).utf8String!)
  }
}

/**
 * FlagDesc(name:, desc:)
 *
 * Describes a command-line flag.
 */
public struct FlagDesc: LeafParserDescription {
  let name: String
  let desc: String

  public var normalised: ParserDescription { return self }

  public var isDelimited: Bool { return true }

  public var summary: String { return "--\(name)" }

  public var description: String {
    return String(format: DEF_FMT,
                  (summary as NSString).utf8String!,
                  (desc as NSString).utf8String!)
  }
}

/**
 * CmdDesc(cmd:, child:)
 *
 * Describes a simple command.
 */
public struct CmdDesc: LeafParserDescription {
  let cmd: String

  public var normalised: ParserDescription {
    return self
  }

  public var isDelimited: Bool { return true }

  public var summary: String { return cmd }
}

/**
 * SectionDesc(tag:, name:, desc:, child:)
 *
 * Describes a chunk of format that is logically related. Mainly used to split
 * up large formats into smaller, manageable chunks.
 */
public struct SectionDesc: ParserDescription {
  let tag: String
  let name: String
  let desc: String
  let child: ParserDescription

  public var normalised: ParserDescription {
    return SectionDesc(tag: tag, name: name, desc: desc,
                       child: child.normalised)
  }

  public var isDelimited: Bool { return true }

  public var summary: String { return "[\(tag)]" }

  public var children: [ParserDescription] { return [child] }

  public var description: String {
    let title = "\(summary) \(name)"
    let underline = String(repeating: "=", count: title.count)
    let header = title + "\n" + underline

    var flags = [FlagDesc](); findAll(&flags)
    var seen = [String: Bool]()
    let flagDescs = flags
      .filter { seen.updateValue(true, forKey: $0.summary) == nil }
      .sorted { $0.summary < $1.summary }
      .map { $0.description }
      .joined(separator: "\n")

    return [header, "\t" + child.summary, desc, flagDescs]
      .filter { !$0.isEmpty }
      .joined(separator: "\n\n")
  }
}

/**
 * AtleastDesc(lowerBound:, children:)
 *
 * Describes a format that recognises at-least `lowerBound`-many occurrences
 * of a rule described by `child`.
 */
public struct AtleastDesc: ParserDescription {
  let lowerBound: Int
  let child: ParserDescription
  let sep: ParserDescription?

  init(lowerBound: Int, child: ParserDescription, sep: ParserDescription?) {
    self.lowerBound = lowerBound
    self.child = child
    self.sep = sep
  }

  init(lowerBound: Int, child: ParserDescription) {
    self.init(lowerBound: lowerBound, child: child, sep: nil)
  }

  public var normalised: ParserDescription {
    return AtleastDesc(lowerBound: lowerBound,
                       child: child.normalised,
                       sep: sep?.normalised)
  }

  public var isDelimited: Bool { return true }

  private var suffix: String {
    switch lowerBound {
    case 0:
      return "*"
    case 1:
      return "+"
    default:
      return "{\(lowerBound)+}"
    }
  }

  public var summary: String {
    let partS = child.delimitedSummary
    if let sepS = sep?.summary, !sepS.isEmpty {
      return delimit(partS + " ... " + sepS + " " + partS) + suffix
    } else {
      return partS + suffix
    }
  }

  public var children: [ParserDescription] {
    if let sep = sep {
      return [child, sep]
    } else {
      return [child]
    }
  }
}

/**
 * OptionalDesc
 *
 * Describes a format that will succeed in parsing even if its child does not
 * succeed.
 */
public struct OptionalDesc: ParserDescription {
  let child: ParserDescription

  public var normalised: ParserDescription {
    switch child {
    case let child as AtleastDesc where child.lowerBound == 1:
      return AtleastDesc(lowerBound: 0, child: child.child, sep: child.sep)
    default:
      return OptionalDesc(child: child.normalised)
    }
  }

  public var isDelimited: Bool { return true }

  public var summary: String { return child.delimitedSummary + "?" }

  public var children: [ParserDescription] { return [child] }
}

/**
 * normalisedTransitiveChildren(Of: desc)
 *
 * The transitive children of a description of type `D` are its immediate
 * children not of type `D`, or  the transitive children of immediate children
 * of type `D`.
 *
 * This property contains all the transitive children, normalised, and in
 * their left-to-right order according to the `children` property.
 *
 * Given a structure as follows:
 *
 *     D [x1, x2, D [x3, D[x4]], C [D [x5], x6]]
 *
 * Should return:
 *
 *     [nx1, nx2, nx3, nx4, nC [D [x5], x6]]
 *
 * Where `nd` is the normal form of description `d`.
 */

private func normalisedTransitiveChildren<D: ParserDescription>(
  Of desc: D
) -> [ParserDescription] {
  var ntChildren = [ParserDescription]()

  for child in desc.children {
    switch child.normalised {
    case let dChild as D:
      ntChildren += normalisedTransitiveChildren(Of: dChild)

    case let normChild:
      ntChildren.append(normChild)
    }
  }

  return ntChildren
}

/**
 * SequenceDesc(children:)
 *
 * Description of a format that recognises the sequential composition of the
 * formats of its children.
 */
public struct SequenceDesc: ParserDescription {
  public let children: [ParserDescription]

  public var normalised: ParserDescription {
    let ntChildren = normalisedTransitiveChildren(Of: self)

    if ntChildren.count == 1 {
      return ntChildren.first!
    } else {
      return SequenceDesc(children: ntChildren)
    }
  }

  public var isDelimited: Bool {
    return children.count == 1 && children.first!.isDelimited
  }

  public var summary: String {
    if children.count == 1 {
      return children.first!.summary
    } else {
      return children.map { $0.delimitedSummary }.joined(separator: " ")
    }
  }
}

/**
 * ChoiceDesc(children:)
 *
 * Describes a format that accepts a string that matches any of the formats
 * described by rules in `children`.
 */
public struct ChoiceDesc: ParserDescription {
  public let children: [ParserDescription]

  /**
   * isExpanded
   *
   * Decides whether the summary of this choice description should span over
   * multiple lines or not.
   */
  private let isExpanded: Bool

  private init(children: [ParserDescription], isExpanded: Bool) {
    self.children = children
    self.isExpanded = isExpanded
  }

  init(children: [ParserDescription]) {
    self.init(children: children, isExpanded: false)
  }

  public var normalised: ParserDescription {
    let ntChildren = normalisedTransitiveChildren(Of: self)

    if ntChildren.count == 1 {
      return ntChildren.first!
    } else {
      return ChoiceDesc(children: ntChildren, isExpanded: isExpanded)
    }
  }

  public var isDelimited: Bool {
    return children.count == 1 && children.first!.isDelimited
  }

  public var summary: String {
    if children.count == 1 {
      return children.first!.summary
    } else {
      return children
        .map { $0.summary }
        .joined(separator: isExpanded ? "\nOR\t" : " | ")
    }
  }

  /**
   * expanded
   *
   * Convert to a `ChoiceDesc` with an expanded summary.
   */
  public var expanded: ChoiceDesc {
    if isExpanded {
      return self
    } else {
      return ChoiceDesc(children: children, isExpanded: true)
    }
  }
}

extension ParserDescription {
  /**
   * usage: String
   *
   * The human-readable version of the contents of the description.
   */
  public var usage: String {
    var waitingSections = [SectionDesc]()
    var sectDescs = [String: String]()
    var primDescs = [String: String]()

    func addPrims(_ prims: [PrimitiveDesc]) {
      for prim in prims {
        let name = prim.name
        if primDescs[name] == nil {
          primDescs[name] = prim.description
        }
      }
    }

    var sects = [SectionDesc](); findAll(&sects)
    waitingSections += sects

    var prims = [PrimitiveDesc](); findAll(&prims)
    addPrims(prims)

    while let sect = waitingSections.popLast() {
      let tag = sect.tag
      if sectDescs[tag] != nil { continue }

      sectDescs[tag] = sect.description

      sects.removeAll(keepingCapacity: true)
      sect.findAll(&sects)
      waitingSections += sects

      prims.removeAll(keepingCapacity: true)
      sect.findAll(&prims)
      addPrims(prims)
    }

    let sectUsage = sectDescs
      .keys.sorted()
      .map { sectDescs[$0]! }
      .joined(separator: "\n\n\n")

    let primUsage = primDescs
      .keys.sorted()
      .map { primDescs[$0]! }
      .joined(separator: "\n")

    return [description, sectUsage, "Primitives:\n\n" + primUsage]
      .filter { !$0.isEmpty }
      .joined(separator: "\n\n\n")
  }
}
