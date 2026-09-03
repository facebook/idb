/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionUtilities
@preconcurrency import FBControlCore
import GRPC
import IDBGRPCSwift
import Testing

@Suite
struct IDBTransientTests {

  // MARK: - FileContainerValueTransformer Tests

  @Test
  func fileContainerMapsAllKnownKinds() {
    let mappings: [(Idb_FileContainer.Kind, FBFileContainerKind)] = [
      (.root, .root),
      (.media, .media),
      (.crashes, .crashes),
      (.provisioningProfiles, .provisioningProfiles),
      (.mdmProfiles, .mdmProfiles),
      (.springboardIcons, .springboardIcons),
      (.wallpaper, .wallpaper),
      (.diskImages, .diskImages),
      (.groupContainer, .group),
      (.applicationContainer, .application),
      (.auxillary, .auxillary),
      (.xctest, .xctest),
      (.dylib, .dylib),
      (.dsym, .dsym),
      (.framework, .framework),
      (.symbols, .symbols),
    ]
    for (protoKind, expectedKind) in mappings {
      let result = FileContainerValueTransformer.fileContainer(from: protoKind)
      #expect((result) == (expectedKind), "Mapping failed for \(protoKind)")
    }
  }

  @Test
  func fileContainerReturnsNilForApplicationKind() {
    #expect((FileContainerValueTransformer.fileContainer(from: .application)) == nil)
  }

  @Test
  func fileContainerReturnsNilForNoneKind() {
    #expect((FileContainerValueTransformer.fileContainer(from: .none)) == nil)
  }

  @Test
  func rawFileContainerReturnsRawValueForKnownKind() {
    var container = Idb_FileContainer()
    container.kind = .root
    let result = FileContainerValueTransformer.rawFileContainer(from: container)
    #expect((result) == (FBFileContainerKind.root.rawValue))
  }

  @Test
  func rawFileContainerReturnsBundleIDForUnmappedKind() {
    var container = Idb_FileContainer()
    container.kind = .application
    container.bundleID = "com.example.app"
    let result = FileContainerValueTransformer.rawFileContainer(from: container)
    #expect((result) == ("com.example.app"))
  }

  // MARK: - GrpcDataMappings Tests

  @Test
  func installRequestExtractsPayload() {
    let payload = Idb_Payload.with { $0.source = .data(Data([1, 2, 3])) }
    var request = Idb_InstallRequest()
    request.value = .payload(payload)
    #expect((request.extractPayload()) != nil)
  }

  @Test
  func installRequestReturnsNilWithoutPayload() {
    let request = Idb_InstallRequest()
    #expect((request.extractPayload()) == nil)
  }

  @Test
  func pushRequestExtractsPayload() {
    let payload = Idb_Payload.with { $0.source = .data(Data([4, 5])) }
    var request = Idb_PushRequest()
    request.value = .payload(payload)
    #expect((request.extractPayload()) != nil)
  }

  @Test
  func pushRequestReturnsNilWithoutPayload() {
    let request = Idb_PushRequest()
    #expect((request.extractPayload()) == nil)
  }

  @Test
  func addMediaRequestExtractsPayload() {
    var request = Idb_AddMediaRequest()
    request.payload = Idb_Payload.with { $0.source = .data(Data([7, 8])) }
    #expect((request.extractPayload()) != nil)
  }

  @Test
  func addMediaRequestReturnsNilWithoutPayload() {
    let request = Idb_AddMediaRequest()
    #expect((request.extractPayload()) == nil)
  }

  @Test
  func payloadExtractsDataFrame() {
    let testData = Data([10, 20, 30])
    let payload = Idb_Payload.with { $0.source = .data(testData) }
    #expect((payload.extractDataFrame()) == (testData))
  }

  @Test
  func payloadReturnsNilDataFrameForFilePath() {
    let payload = Idb_Payload.with { $0.source = .filePath("/tmp/file") }
    #expect((payload.extractDataFrame()) == nil)
  }

  @Test
  func payloadExtractableChainExtractsData() {
    let testData = Data([1, 2, 3, 4])
    let payload = Idb_Payload.with { $0.source = .data(testData) }
    var request = Idb_InstallRequest()
    request.value = .payload(payload)
    #expect((request.extractDataFrame()) == (testData))
  }

  @Test
  func payloadExtractableChainReturnsNilWithoutPayload() {
    let request = Idb_InstallRequest()
    #expect((request.extractDataFrame()) == nil)
  }

  // MARK: - IDBPortsConfiguration Tests

  @Test
  func defaultDebugserverPort() {
    let (defaults, cleanup) = makeTestDefaults()
    defer { cleanup() }
    let config = IDBPortsConfiguration(arguments: defaults)
    #expect((config.debugserverPort) == (10881))
  }

  @Test
  func customDebugserverPort() {
    let (defaults, cleanup) = makeTestDefaults()
    defer { cleanup() }
    defaults.set("12345", forKey: "-debug-port")
    let config = IDBPortsConfiguration(arguments: defaults)
    #expect((config.debugserverPort) == (12345))
  }

  @Test
  func swiftServerTargetDefaultsToTcpPort() {
    let (defaults, cleanup) = makeTestDefaults()
    defer { cleanup() }
    let config = IDBPortsConfiguration(arguments: defaults)
    if case .tcpPort(let port) = config.swiftServerTarget {
      #expect((port) == (10882))
    } else {
      Issue.record("Expected TCP port target")
    }
  }

  @Test
  func swiftServerTargetUsesCustomGrpcPort() {
    let (defaults, cleanup) = makeTestDefaults()
    defer { cleanup() }
    defaults.set("9999", forKey: "-grpc-port")
    let config = IDBPortsConfiguration(arguments: defaults)
    if case .tcpPort(let port) = config.swiftServerTarget {
      #expect((port) == (9999))
    } else {
      Issue.record("Expected TCP port target")
    }
  }

  @Test
  func swiftServerTargetPrefersUnixDomainSocket() {
    let (defaults, cleanup) = makeTestDefaults()
    defer { cleanup() }
    defaults.set("/tmp/test.sock", forKey: "-grpc-domain-sock")
    defaults.set("9999", forKey: "-grpc-port")
    let config = IDBPortsConfiguration(arguments: defaults)
    if case .unixDomainSocket(let path) = config.swiftServerTarget {
      #expect((path) == ("/tmp/test.sock"))
    } else {
      Issue.record("Expected Unix domain socket target")
    }
  }

  @Test
  func tlsCertPathFromDefaults() {
    let (defaults, cleanup) = makeTestDefaults()
    defer { cleanup() }
    defaults.set("/path/to/cert.pem", forKey: "-tls-cert-path")
    let config = IDBPortsConfiguration(arguments: defaults)
    #expect((config.tlsCertPath) == ("/path/to/cert.pem"))
  }

  @Test
  func tlsCertPathDefaultsToNil() {
    let (defaults, cleanup) = makeTestDefaults()
    defer { cleanup() }
    let config = IDBPortsConfiguration(arguments: defaults)
    #expect((config.tlsCertPath) == nil)
  }

  // MARK: - GRPCConnectionTarget Tests

  @Test
  func tcpPortDescription() {
    let target = GRPCConnectionTarget.tcpPort(port: 8080)
    #expect((target.description) == ("tcp port 8080"))
  }

  @Test
  func unixDomainSocketDescription() {
    let target = GRPCConnectionTarget.unixDomainSocket("/tmp/test.sock")
    #expect((target.description) == ("unix socket /tmp/test.sock"))
  }

  @Test
  func tcpPortSupportsTLS() {
    #expect((GRPCConnectionTarget.tcpPort(port: 443).supportsTLSCert))
  }

  @Test
  func unixDomainSocketDoesNotSupportTLS() {
    #expect(!(GRPCConnectionTarget.unixDomainSocket("/tmp/s").supportsTLSCert))
  }

  @Test
  func outputDescriptionThrowsForNilAddress() {
    let target = GRPCConnectionTarget.tcpPort(port: 8080)
    do {
      _ = try target.outputDescription(for: nil)
      Issue.record("expected an ExtractionError")
    } catch {
      #expect(error is GRPCConnectionTarget.ExtractionError)
    }
  }

  // MARK: - CrashLogQueryValueTransformer Tests

  @Test
  func emptyQueryReturnsTruePredicate() {
    let query = Idb_CrashLogQuery()
    let predicate = CrashLogQueryValueTransformer.predicate(from: query)
    #expect((predicate) == (NSPredicate(value: true)))
  }

  @Test
  func queryWithSinceReturnsCompoundPredicate() {
    var query = Idb_CrashLogQuery()
    query.since = 1000
    let predicate = CrashLogQueryValueTransformer.predicate(from: query)
    #expect((predicate is NSCompoundPredicate))
  }

  @Test
  func queryWithBeforeReturnsCompoundPredicate() {
    var query = Idb_CrashLogQuery()
    query.before = 2000
    let predicate = CrashLogQueryValueTransformer.predicate(from: query)
    #expect((predicate is NSCompoundPredicate))
  }

  @Test
  func queryWithNameReturnsCompoundPredicate() {
    var query = Idb_CrashLogQuery()
    query.name = "MyCrash"
    let predicate = CrashLogQueryValueTransformer.predicate(from: query)
    #expect((predicate is NSCompoundPredicate))
  }

  @Test
  func queryWithBundleIDReturnsCompoundPredicate() {
    var query = Idb_CrashLogQuery()
    query.bundleID = "com.example.app"
    let predicate = CrashLogQueryValueTransformer.predicate(from: query)
    #expect((predicate is NSCompoundPredicate))
  }

  @Test
  func queryWithMultipleFiltersReturnsCorrectSubpredicateCount() {
    var query = Idb_CrashLogQuery()
    query.since = 1000
    query.before = 2000
    query.name = "Crash"
    let predicate = CrashLogQueryValueTransformer.predicate(from: query)
    let compound = predicate as! NSCompoundPredicate
    #expect((compound.subpredicates.count) == (3))
  }

  // MARK: - StreamReadError Tests

  @Test
  func streamReadErrorMakesFailedPreconditionStatus() {
    let error = StreamReadError<String>.nextElementNotProduced
    let status = error.makeGRPCStatus()
    #expect((status.code) == (.failedPrecondition))
    #expect((status.message?.contains("String") ?? false))
  }

  // MARK: - IDBConfiguration Tests

  @Test
  func defaultEventReporterIsEmptyReporter() {
    #expect((IDBConfiguration.eventReporter is EmptyEventReporter))
  }

  // MARK: - EmptyEventReporter Tests

  @Test
  func emptyEventReporterMetadataStartsEmpty() {
    let reporter = EmptyEventReporter()
    #expect((reporter.metadata.isEmpty))
  }

  // MARK: - Helpers

  private func makeTestDefaults() -> (UserDefaults, () -> Void) {
    let suiteName = "IDBTransientTests_\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let cleanup = { defaults.removePersistentDomain(forName: suiteName) }
    return (defaults, cleanup)
  }
}
