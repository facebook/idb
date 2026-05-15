/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import GRPC
import IDBGRPCSwift
import XCTest

final class IDBTransientTests: XCTestCase {

  // MARK: - FileContainerValueTransformer Tests

  func testFileContainerMapsAllKnownKinds() {
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
      XCTAssertEqual(result, expectedKind, "Mapping failed for \(protoKind)")
    }
  }

  func testFileContainerReturnsNilForApplicationKind() {
    XCTAssertNil(FileContainerValueTransformer.fileContainer(from: .application))
  }

  func testFileContainerReturnsNilForNoneKind() {
    XCTAssertNil(FileContainerValueTransformer.fileContainer(from: .none))
  }

  func testRawFileContainerReturnsRawValueForKnownKind() {
    var container = Idb_FileContainer()
    container.kind = .root
    let result = FileContainerValueTransformer.rawFileContainer(from: container)
    XCTAssertEqual(result, FBFileContainerKind.root.rawValue)
  }

  func testRawFileContainerReturnsBundleIDForUnmappedKind() {
    var container = Idb_FileContainer()
    container.kind = .application
    container.bundleID = "com.example.app"
    let result = FileContainerValueTransformer.rawFileContainer(from: container)
    XCTAssertEqual(result, "com.example.app")
  }

  // MARK: - GrpcDataMappings Tests

  func testInstallRequestExtractsPayload() {
    let payload = Idb_Payload.with { $0.source = .data(Data([1, 2, 3])) }
    var request = Idb_InstallRequest()
    request.value = .payload(payload)
    XCTAssertNotNil(request.extractPayload())
  }

  func testInstallRequestReturnsNilWithoutPayload() {
    let request = Idb_InstallRequest()
    XCTAssertNil(request.extractPayload())
  }

  func testPushRequestExtractsPayload() {
    let payload = Idb_Payload.with { $0.source = .data(Data([4, 5])) }
    var request = Idb_PushRequest()
    request.value = .payload(payload)
    XCTAssertNotNil(request.extractPayload())
  }

  func testPushRequestReturnsNilWithoutPayload() {
    let request = Idb_PushRequest()
    XCTAssertNil(request.extractPayload())
  }

  func testAddMediaRequestExtractsPayload() {
    var request = Idb_AddMediaRequest()
    request.payload = Idb_Payload.with { $0.source = .data(Data([7, 8])) }
    XCTAssertNotNil(request.extractPayload())
  }

  func testAddMediaRequestReturnsNilWithoutPayload() {
    let request = Idb_AddMediaRequest()
    XCTAssertNil(request.extractPayload())
  }

  func testPayloadExtractsDataFrame() {
    let testData = Data([10, 20, 30])
    let payload = Idb_Payload.with { $0.source = .data(testData) }
    XCTAssertEqual(payload.extractDataFrame(), testData)
  }

  func testPayloadReturnsNilDataFrameForFilePath() {
    let payload = Idb_Payload.with { $0.source = .filePath("/tmp/file") }
    XCTAssertNil(payload.extractDataFrame())
  }

  func testPayloadExtractableChainExtractsData() {
    let testData = Data([1, 2, 3, 4])
    let payload = Idb_Payload.with { $0.source = .data(testData) }
    var request = Idb_InstallRequest()
    request.value = .payload(payload)
    XCTAssertEqual(request.extractDataFrame(), testData)
  }

  func testPayloadExtractableChainReturnsNilWithoutPayload() {
    let request = Idb_InstallRequest()
    XCTAssertNil(request.extractDataFrame())
  }

  // MARK: - IDBPortsConfiguration Tests

  func testDefaultDebugserverPort() {
    let (defaults, cleanup) = makeTestDefaults()
    defer { cleanup() }
    let config = IDBPortsConfiguration(arguments: defaults)
    XCTAssertEqual(config.debugserverPort, 10881)
  }

  func testCustomDebugserverPort() {
    let (defaults, cleanup) = makeTestDefaults()
    defer { cleanup() }
    defaults.set("12345", forKey: "-debug-port")
    let config = IDBPortsConfiguration(arguments: defaults)
    XCTAssertEqual(config.debugserverPort, 12345)
  }

  func testSwiftServerTargetDefaultsToTcpPort() {
    let (defaults, cleanup) = makeTestDefaults()
    defer { cleanup() }
    let config = IDBPortsConfiguration(arguments: defaults)
    if case .tcpPort(let port) = config.swiftServerTarget {
      XCTAssertEqual(port, 10882)
    } else {
      XCTFail("Expected TCP port target")
    }
  }

  func testSwiftServerTargetUsesCustomGrpcPort() {
    let (defaults, cleanup) = makeTestDefaults()
    defer { cleanup() }
    defaults.set("9999", forKey: "-grpc-port")
    let config = IDBPortsConfiguration(arguments: defaults)
    if case .tcpPort(let port) = config.swiftServerTarget {
      XCTAssertEqual(port, 9999)
    } else {
      XCTFail("Expected TCP port target")
    }
  }

  func testSwiftServerTargetPrefersUnixDomainSocket() {
    let (defaults, cleanup) = makeTestDefaults()
    defer { cleanup() }
    defaults.set("/tmp/test.sock", forKey: "-grpc-domain-sock")
    defaults.set("9999", forKey: "-grpc-port")
    let config = IDBPortsConfiguration(arguments: defaults)
    if case .unixDomainSocket(let path) = config.swiftServerTarget {
      XCTAssertEqual(path, "/tmp/test.sock")
    } else {
      XCTFail("Expected Unix domain socket target")
    }
  }

  func testTlsCertPathFromDefaults() {
    let (defaults, cleanup) = makeTestDefaults()
    defer { cleanup() }
    defaults.set("/path/to/cert.pem", forKey: "-tls-cert-path")
    let config = IDBPortsConfiguration(arguments: defaults)
    XCTAssertEqual(config.tlsCertPath, "/path/to/cert.pem")
  }

  func testTlsCertPathDefaultsToNil() {
    let (defaults, cleanup) = makeTestDefaults()
    defer { cleanup() }
    let config = IDBPortsConfiguration(arguments: defaults)
    XCTAssertNil(config.tlsCertPath)
  }

  // MARK: - GRPCConnectionTarget Tests

  func testTcpPortDescription() {
    let target = GRPCConnectionTarget.tcpPort(port: 8080)
    XCTAssertEqual(target.description, "tcp port 8080")
  }

  func testUnixDomainSocketDescription() {
    let target = GRPCConnectionTarget.unixDomainSocket("/tmp/test.sock")
    XCTAssertEqual(target.description, "unix socket /tmp/test.sock")
  }

  func testTcpPortSupportsTLS() {
    XCTAssertTrue(GRPCConnectionTarget.tcpPort(port: 443).supportsTLSCert)
  }

  func testUnixDomainSocketDoesNotSupportTLS() {
    XCTAssertFalse(GRPCConnectionTarget.unixDomainSocket("/tmp/s").supportsTLSCert)
  }

  func testOutputDescriptionThrowsForNilAddress() {
    let target = GRPCConnectionTarget.tcpPort(port: 8080)
    XCTAssertThrowsError(try target.outputDescription(for: nil)) { error in
      XCTAssertTrue(error is GRPCConnectionTarget.ExtractionError)
    }
  }

  // MARK: - CrashLogQueryValueTransformer Tests

  func testEmptyQueryReturnsTruePredicate() {
    let query = Idb_CrashLogQuery()
    let predicate = CrashLogQueryValueTransformer.predicate(from: query)
    XCTAssertEqual(predicate, NSPredicate(value: true))
  }

  func testQueryWithSinceReturnsCompoundPredicate() {
    var query = Idb_CrashLogQuery()
    query.since = 1000
    let predicate = CrashLogQueryValueTransformer.predicate(from: query)
    XCTAssertTrue(predicate is NSCompoundPredicate)
  }

  func testQueryWithBeforeReturnsCompoundPredicate() {
    var query = Idb_CrashLogQuery()
    query.before = 2000
    let predicate = CrashLogQueryValueTransformer.predicate(from: query)
    XCTAssertTrue(predicate is NSCompoundPredicate)
  }

  func testQueryWithNameReturnsCompoundPredicate() {
    var query = Idb_CrashLogQuery()
    query.name = "MyCrash"
    let predicate = CrashLogQueryValueTransformer.predicate(from: query)
    XCTAssertTrue(predicate is NSCompoundPredicate)
  }

  func testQueryWithBundleIDReturnsCompoundPredicate() {
    var query = Idb_CrashLogQuery()
    query.bundleID = "com.example.app"
    let predicate = CrashLogQueryValueTransformer.predicate(from: query)
    XCTAssertTrue(predicate is NSCompoundPredicate)
  }

  func testQueryWithMultipleFiltersReturnsCorrectSubpredicateCount() {
    var query = Idb_CrashLogQuery()
    query.since = 1000
    query.before = 2000
    query.name = "Crash"
    let predicate = CrashLogQueryValueTransformer.predicate(from: query)
    let compound = predicate as! NSCompoundPredicate
    XCTAssertEqual(compound.subpredicates.count, 3)
  }

  // MARK: - StreamReadError Tests

  func testStreamReadErrorMakesFailedPreconditionStatus() {
    let error = StreamReadError<String>.nextElementNotProduced
    let status = error.makeGRPCStatus()
    XCTAssertEqual(status.code, .failedPrecondition)
    XCTAssertTrue(status.message?.contains("String") ?? false)
  }

  // MARK: - EmptyIDBKillswitch Tests

  func testEmptyKillswitchDisabledReturnsTrue() async {
    let killswitch = EmptyIDBKillswitch()
    let result = await killswitch.disabled(.grpcEndpoint)
    XCTAssertTrue(result)
  }

  // MARK: - IDBConfiguration Tests

  func testDefaultEventReporterIsEmptyReporter() {
    XCTAssertTrue(IDBConfiguration.eventReporter is EmptyEventReporter)
  }

  func testDefaultKillswitchIsEmptyKillswitch() {
    XCTAssertTrue(IDBConfiguration.idbKillswitch is EmptyIDBKillswitch)
  }

  // MARK: - EmptyEventReporter Tests

  func testEmptyEventReporterMetadataStartsEmpty() {
    let reporter = EmptyEventReporter()
    XCTAssertTrue(reporter.metadata.isEmpty)
  }

  // MARK: - DefaultConfiguration Tests

  func testDefaultCacheInvalidationInterval() {
    XCTAssertEqual(DefaultConfiguration.cacheInvalidationInterval, 120)
  }

  func testDefaultBaseURLContainsInterngraph() {
    XCTAssertTrue(DefaultConfiguration.baseURL.contains("interngraph"))
  }

  func testDefaultURLSessionTimeout() {
    XCTAssertEqual(DefaultConfiguration.urlSessionConfiguration.timeoutIntervalForRequest, 15)
  }

  // MARK: - FBInternGraphError Tests

  func testFailToFormURLRequestErrorDescription() {
    let error = FBInternGraphError.failToFormURLRequest
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("URL request"))
  }

  func testInconsistentSitevarTypesErrorDescription() {
    let error = FBInternGraphError.inconsistentSitevarTypes
    XCTAssertNotNil(error.errorDescription)
    XCTAssertTrue(error.errorDescription!.contains("types mismatched"))
  }

  // MARK: - FBInternGraphInternalError Tests

  func testSitevarNotFoundDescription() {
    let error = FBInternGraphInternalError.sitevarNotFoundInResult
    XCTAssertTrue(error.description.contains("sitevar not found"))
  }

  func testNotReceiveErrorOrDataDescription() {
    let error = FBInternGraphInternalError.notReceiveErrorOrData
    XCTAssertTrue(error.description.contains("not received error or data"))
  }

  func testInacceptableStatusCodeDescription() {
    let error = FBInternGraphInternalError.inacceptableStatusCode("test output")
    XCTAssertTrue(error.description.contains("test output"))
  }

  // MARK: - Helpers

  private func makeTestDefaults() -> (UserDefaults, () -> Void) {
    let suiteName = "IDBTransientTests_\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let cleanup = { defaults.removePersistentDomain(forName: suiteName) }
    return (defaults, cleanup)
  }
}
