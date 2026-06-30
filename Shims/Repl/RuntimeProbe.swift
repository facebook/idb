/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// In-process Swift runtime metadata probe for idb-repl.
//
// STATUS: first validation increment — NOT yet build/run-verified (see
// fbobjc/Tools/idb/plans/runtime_symbols.md). It walks a target image's
// `__TEXT,__swift5_types` section, recovers each top-level type's kind, name,
// module, and stored properties, and writes one `<Module>.swiftinterface` file
// per module, returning the output path. It lives ONLY in the `libRepl` shim,
// never in the shared `ReplExecutor`.
//
// Deliberately out of scope for this first cut (next increments):
//   - methods / vtable recovery (via exact-match `dladdr` on vtable slots)
//   - ABI-faithful field types & layout (full symbolic-reference resolution)
//   - nested and generic types, enum cases/payloads
//   - returning structured data / the socket `describe` command
//
// All metadata offsets follow the stable Swift runtime ABI
// (TargetContextDescriptor / TargetTypeContextDescriptor / TargetFieldDescriptor).
// Parsing is defensive: any malformed/unsupported descriptor is skipped rather
// than crashing the host process.

// patternlint-disable cdecl-unsupported

import Foundation
import MachO

// MARK: - Context descriptor kinds (low 5 bits of the descriptor Flags word)

private let kindModule: UInt32 = 0
private let kindClass: UInt32 = 16
private let kindStruct: UInt32 = 17
private let kindEnum: UInt32 = 18

private let flagIsGeneric: UInt32 = 0x80 // bit 7 of the Flags word

// MARK: - Relative pointers
// Swift relative pointers are 32-bit signed offsets from the field's own address.
// "Indirectable" pointers use the low bit to mean "the target is a pointer to the
// value" rather than the value itself.

@inline(__always)
private func relativeDirect(_ field: UnsafeRawPointer) -> UnsafeRawPointer? {
  let offset = field.loadUnaligned(as: Int32.self)
  if offset == 0 { return nil }
  return field.advanced(by: Int(offset))
}

@inline(__always)
private func relativeIndirectable(_ field: UnsafeRawPointer) -> UnsafeRawPointer? {
  let raw = field.loadUnaligned(as: Int32.self)
  if raw == 0 { return nil }
  let target = field.advanced(by: Int(raw & ~1))
  if (raw & 1) != 0 {
    let p = target.loadUnaligned(as: UInt.self)
    return p == 0 ? nil : UnsafeRawPointer(bitPattern: p)
  }
  return target
}

@inline(__always)
private func cString(at ptr: UnsafeRawPointer?) -> String? {
  guard let ptr else { return nil }
  return String(cString: ptr.assumingMemoryBound(to: CChar.self))
}

// MARK: - Mangled type name resolution

// We resolve a field's mangled type reference (including embedded symbolic
// references) by calling the Swift runtime's
// `swift_getTypeByMangledNameInContext`. That symbol name is reserved by the
// runtime and cannot be bound with `@_silgen_name`, so resolve it dynamically
// with `dlsym` and call through a C function pointer instead.
// Returns the type metadata pointer (Swift runtime `const Metadata *`); callers
// bitcast it to `Any.Type`. A metatype isn't `@convention(c)`-representable, so
// the C signature uses a raw pointer.
private typealias GetTypeByMangledNameInContext =
  @convention(c) (
    _ name: UnsafePointer<UInt8>,
    _ length: UInt,
    _ context: UnsafeRawPointer?,
    _ genericArgs: UnsafeRawPointer?
  ) -> UnsafeRawPointer?

private let getTypeByMangledNameInContext: GetTypeByMangledNameInContext? = {
  // RTLD_DEFAULT is ((void *)-2) on Darwin: search every loaded image for the
  // libswiftCore entry point.
  guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swift_getTypeByMangledNameInContext") else {
    return nil
  }
  return unsafeBitCast(symbol, to: GetTypeByMangledNameInContext.self)
}()

/// Length of a mangled type-name string, accounting for embedded symbolic
/// references (whose 4- or 8-byte operands may themselves contain null bytes,
/// so a plain `strlen` is wrong).
private func mangledNameLength(_ start: UnsafeRawPointer) -> Int {
  var p = start
  while true {
    let b = p.loadUnaligned(as: UInt8.self)
    if b == 0 { break }
    if b >= 0x01, b <= 0x17 {
      p = p.advanced(by: 5) // 1 control byte + 4-byte relative reference
    } else if b >= 0x18, b <= 0x1F {
      p = p.advanced(by: 9) // 1 control byte + 8-byte absolute reference
    } else {
      p = p.advanced(by: 1)
    }
  }
  return start.distance(to: p)
}

/// Best-effort: resolve a field's mangled type reference to a qualified Swift
/// type spelling (e.g. "Swift.Int"). Returns nil if the type can't be resolved
/// in-process (e.g. unbound generic), so callers can fall back to a placeholder.
private func resolveTypeName(_ mangled: UnsafeRawPointer?, context: UnsafeRawPointer) -> String? {
  guard let mangled, let resolve = getTypeByMangledNameInContext else { return nil }
  let len = mangledNameLength(mangled)
  guard len > 0 else { return nil }
  let bytes = mangled.assumingMemoryBound(to: UInt8.self)
  guard let metadata = resolve(bytes, UInt(len), context, nil) else {
    return nil
  }
  let type = unsafeBitCast(metadata, to: Any.Type.self)
  return String(reflecting: type)
}

// MARK: - Descriptor walking

private struct FieldInfo {
  let name: String
  let typeName: String
}

/// Resolve a `__swift5_types` record (a relative, possibly-indirect pointer) to
/// the type context descriptor it names.
private func resolveTypeRecord(_ entry: UnsafeRawPointer) -> UnsafeRawPointer? {
  let raw = entry.loadUnaligned(as: Int32.self)
  if raw == 0 { return nil }
  let target = entry.advanced(by: Int(raw & ~1))
  if (raw & 1) != 0 {
    let p = target.loadUnaligned(as: UInt.self)
    return p == 0 ? nil : UnsafeRawPointer(bitPattern: p)
  }
  return target
}

/// Walk the parent chain to the enclosing module descriptor and read its name.
private func moduleName(of descriptor: UnsafeRawPointer) -> String? {
  var current: UnsafeRawPointer? = relativeIndirectable(descriptor.advanced(by: 4)) // Parent
  var depth = 0
  while let c = current, depth < 16 {
    let kind = c.loadUnaligned(as: UInt32.self) & 0x1F
    if kind == kindModule {
      return cString(at: relativeDirect(c.advanced(by: 8))) // module descriptor: Name at +8
    }
    current = relativeIndirectable(c.advanced(by: 4))
    depth += 1
  }
  return nil
}

/// Whether the descriptor's immediate parent is a module (i.e. it's a top-level
/// type). We skip nested types for now.
private func isTopLevel(_ descriptor: UnsafeRawPointer) -> Bool {
  guard let parent = relativeIndirectable(descriptor.advanced(by: 4)) else { return false }
  return (parent.loadUnaligned(as: UInt32.self) & 0x1F) == kindModule
}

/// Stored properties from the type's field descriptor (`Fields` at +16).
private func storedFields(of descriptor: UnsafeRawPointer) -> [FieldInfo] {
  guard let fd = relativeDirect(descriptor.advanced(by: 16)) else { return [] }
  let recordSize = Int(fd.advanced(by: 10).loadUnaligned(as: UInt16.self))
  let numFields = Int(fd.advanced(by: 12).loadUnaligned(as: UInt32.self))
  guard recordSize >= 12, numFields > 0, numFields < 4096 else { return [] }
  let records = fd.advanced(by: 16)
  var fields: [FieldInfo] = []
  for i in 0..<numFields {
    let rec = records.advanced(by: i * recordSize)
    let name = cString(at: relativeDirect(rec.advanced(by: 8))) ?? "field\(i)" // FieldName at +8
    let typeName =
      resolveTypeName(relativeDirect(rec.advanced(by: 4)), context: descriptor) // MangledTypeName at +4
      ?? "Any /* TODO: unresolved type */"
    fields.append(FieldInfo(name: name, typeName: typeName))
  }
  return fields
}

// MARK: - Image enumeration

private func matchingImageHeaders(filter: String) -> [UnsafeRawPointer] {
  var headers: [UnsafeRawPointer] = []
  let count = _dyld_image_count()
  var i: UInt32 = 0
  while i < count {
    defer { i += 1 }
    guard let nameC = _dyld_get_image_name(i) else { continue }
    let name = String(cString: nameC)
    guard name.contains(filter) else { continue }
    if let header = _dyld_get_image_header(i) {
      headers.append(UnsafeRawPointer(header))
    }
  }
  return headers
}

private func typeDescriptors(in header: UnsafeRawPointer) -> [UnsafeRawPointer] {
  var size: UInt = 0
  let mh = header.assumingMemoryBound(to: mach_header_64.self)
  guard let section = getsectiondata(mh, "__TEXT", "__swift5_types", &size) else { return [] }
  let base = UnsafeRawPointer(section)
  let count = Int(size) / 4
  var descriptors: [UnsafeRawPointer] = []
  for i in 0..<count {
    if let desc = resolveTypeRecord(base.advanced(by: i * 4)) {
      descriptors.append(desc)
    }
  }
  return descriptors
}

// MARK: - Interface rendering

private func renderType(_ descriptor: UnsafeRawPointer) -> String? {
  let flags = descriptor.loadUnaligned(as: UInt32.self)
  guard (flags & flagIsGeneric) == 0 else { return nil } // skip generics for now
  guard isTopLevel(descriptor) else { return nil } // skip nested types for now

  let keyword: String
  switch flags & 0x1F {
  case kindClass: keyword = "class"
  case kindStruct: keyword = "struct"
  case kindEnum: keyword = "enum"
  default: return nil
  }
  guard let name = cString(at: relativeDirect(descriptor.advanced(by: 8))) else { return nil } // Name at +8

  var lines = ["public \(keyword) \(name) {"]
  if keyword == "enum" {
    lines.append("  // TODO: enum cases / payload layout not yet recovered")
  } else {
    for field in storedFields(of: descriptor) {
      lines.append("  public var \(field.name): \(field.typeName)")
    }
  }
  if keyword == "class" {
    lines.append("  // TODO: methods (vtable + exact-match dladdr) not yet recovered")
  }
  lines.append("}")
  return lines.joined(separator: "\n")
}

private func renderInterface(module: String, declarations: [String]) -> String {
  var out = "// swift-interface-format-version: 1.0\n"
  out += "// Generated by idb-repl RuntimeProbe (validation spike — not ABI-complete).\n"
  out += "// swift-module-flags: -module-name \(module)\n\n"
  out += declarations.joined(separator: "\n\n")
  out += "\n"
  return out
}

// MARK: - Probe

final class RuntimeProbe {
  /// Enumerate the Swift types in the image(s) whose path contains
  /// `imageNameFilter`, write one `<Module>.swiftinterface` per module into
  /// `outputDir`, and return the path of the first file written (nil on failure).
  func generateInterfaces(outputDir: String, imageNameFilter: String) -> String? {
    guard !imageNameFilter.isEmpty else {
      NSLog("[idb-repl][probe] no image filter provided; refusing to scan all images")
      return nil
    }
    let headers = matchingImageHeaders(filter: imageNameFilter)
    guard !headers.isEmpty else {
      NSLog("[idb-repl][probe] no loaded image matched '%@'", imageNameFilter)
      return nil
    }

    var declarationsByModule: [String: [String]] = [:]
    for header in headers {
      for descriptor in typeDescriptors(in: header) {
        guard let declaration = renderType(descriptor) else { continue }
        let module = moduleName(of: descriptor) ?? "Unknown"
        declarationsByModule[module, default: []].append(declaration)
      }
    }
    guard !declarationsByModule.isEmpty else {
      NSLog("[idb-repl][probe] matched image(s) but recovered no top-level Swift types")
      return nil
    }

    try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
    var firstPath: String?
    for (module, declarations) in declarationsByModule {
      let text = renderInterface(module: module, declarations: declarations)
      let path = (outputDir as NSString).appendingPathComponent("\(module).swiftinterface")
      do {
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        NSLog("[idb-repl][probe] wrote %@ (%d types)", path, declarations.count)
        if firstPath == nil { firstPath = path }
      } catch {
        NSLog("[idb-repl][probe] failed to write %@: %@", path, "\(error)")
      }
    }
    return firstPath
  }
}

// MARK: - C entry point (called from the ObjC shim; see TestRepl.m)

/// Generates `.swiftinterface` file(s) for the matching image(s) and returns a
/// malloc'd path (the caller must `free` it), or NULL.
@_cdecl("FBReplGenerateSwiftInterface")
public func FBReplGenerateSwiftInterface(
  _ outDirC: UnsafePointer<CChar>?,
  _ imageFilterC: UnsafePointer<CChar>?
) -> UnsafePointer<CChar>? {
  let outDir = outDirC.map { String(cString: $0) } ?? NSTemporaryDirectory()
  let filter = imageFilterC.map { String(cString: $0) } ?? ""
  guard let path = RuntimeProbe().generateInterfaces(outputDir: outDir, imageNameFilter: filter) else {
    return nil
  }
  guard let duplicated = strdup(path) else {
    return nil
  }
  return UnsafePointer(duplicated)
}
