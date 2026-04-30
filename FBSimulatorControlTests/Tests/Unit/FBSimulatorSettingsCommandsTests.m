/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>
#import <FBSimulatorControl/FBSimulatorControl.h>

#pragma mark - Expose Private Interface for Testing

@interface FBSimulatorSettingsCommands (Testing)

@property (nonatomic, weak, readonly) FBSimulator *simulator;

+ (NSDictionary<FBTargetSettingsService, NSString *> *)tccDatabaseMapping;
+ (NSDictionary<FBTargetSettingsService, NSString *> *)coreSimulatorSettingMappingPreIos13;
+ (NSDictionary<FBTargetSettingsService, NSString *> *)coreSimulatorSettingMappingPostIos13;
+ (NSSet<NSString *> *)permissibleAddressBookDBFilenames;
+ (NSSet<FBTargetSettingsService> *)filteredTCCApprovals:(NSSet<FBTargetSettingsService> *)approvals;
+ (NSString *)preiOS12ApprovalRowsForBundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBTargetSettingsService> *)services;
+ (NSString *)postiOS12ApprovalRowsForBundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBTargetSettingsService> *)services;
+ (NSString *)postiOS15ApprovalRowsForBundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBTargetSettingsService> *)services;
+ (NSString *)postiOS17ApprovalRowsForBundleIDs:(NSSet<NSString *> *)bundleIDs services:(NSSet<FBTargetSettingsService> *)services;
+ (NSString *)magicDeeplinkKeyForScheme:(NSString *)scheme;

@end

#pragma mark - Simulator Test Double

@interface FBSettingsTests_SimDouble : NSObject

@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, strong) dispatch_queue_t asyncQueue;
@property (nonatomic, strong, nullable) id<FBControlCoreLogger> logger;
@property (nonatomic, copy, nullable) NSString *dataDirectory;

@end

@implementation FBSettingsTests_SimDouble

- (instancetype)init
{
  self = [super init];
  if (self) {
    _workQueue = dispatch_queue_create("com.test.settings.work", DISPATCH_QUEUE_SERIAL);
    _asyncQueue = dispatch_queue_create("com.test.settings.async", DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

@end

#pragma mark - Tests

@interface FBSimulatorSettingsCommandsTests : XCTestCase
@end

@implementation FBSimulatorSettingsCommandsTests

#pragma mark - Helpers

- (FBSimulatorSettingsCommands *)makeCommands
{
  FBSettingsTests_SimDouble *sim = [[FBSettingsTests_SimDouble alloc] init];
  return [FBSimulatorSettingsCommands commandsWithTarget:(FBSimulator *)sim];
}

- (void)assertFuture:(FBFuture *)future failsWithTimeout:(NSTimeInterval)timeout message:(NSString *)message
{
  NSError *error = nil;
  [future awaitWithTimeout:timeout error:&error];
  XCTAssertNotNil(error, @"%@", message);
}

#pragma mark - Filtered TCC Approvals

- (void)testFilteredTCCApprovalsKeepsOnlyTCCServices
{
  NSSet *input = [NSSet setWithArray:@[
    FBTargetSettingsServiceContacts,
    FBTargetSettingsServicePhotos,
    FBTargetSettingsServiceLocation,
    FBTargetSettingsServiceNotification,
  ]];
  NSSet *filtered = [FBSimulatorSettingsCommands filteredTCCApprovals:input];
  XCTAssertTrue([filtered containsObject:FBTargetSettingsServiceContacts],
    @"Contacts is in TCC mapping and should be kept");
  XCTAssertTrue([filtered containsObject:FBTargetSettingsServicePhotos],
    @"Photos is in TCC mapping and should be kept");
  XCTAssertFalse([filtered containsObject:FBTargetSettingsServiceLocation],
    @"Location is NOT in TCC mapping and should be removed");
  XCTAssertFalse([filtered containsObject:FBTargetSettingsServiceNotification],
    @"Notification is NOT in TCC mapping and should be removed");
}

- (void)testFilteredTCCApprovalsReturnsEmptyForNonTCCServices
{
  NSSet *input = [NSSet setWithArray:@[
    FBTargetSettingsServiceLocation,
    FBTargetSettingsServiceNotification,
    FBTargetSettingsServiceHealth,
  ]];
  NSSet *filtered = [FBSimulatorSettingsCommands filteredTCCApprovals:input];
  XCTAssertEqual(filtered.count, 0,
    @"Should return empty set when no input services are in TCC mapping");
}

- (void)testFilteredTCCApprovalsKeepsAllFourTCCServices
{
  NSSet *input = [NSSet setWithArray:@[
    FBTargetSettingsServiceContacts,
    FBTargetSettingsServicePhotos,
    FBTargetSettingsServiceCamera,
    FBTargetSettingsServiceMicrophone,
  ]];
  NSSet *filtered = [FBSimulatorSettingsCommands filteredTCCApprovals:input];
  XCTAssertEqual(filtered.count, 4,
    @"All four TCC-backed services should pass through the filter");
}

#pragma mark - Magic Deeplink Key

- (void)testMagicDeeplinkKeyFormatsCorrectly
{
  NSString *key = [FBSimulatorSettingsCommands magicDeeplinkKeyForScheme:@"myapp"];
  XCTAssertEqualObjects(key, @"com.apple.CoreSimulator.CoreSimulatorBridge-->myapp",
    @"Deeplink key should use CoreSimulatorBridge prefix with --> separator");
}

- (void)testMagicDeeplinkKeyHandlesComplexScheme
{
  NSString *key = [FBSimulatorSettingsCommands magicDeeplinkKeyForScheme:@"fb-messenger-api"];
  XCTAssertEqualObjects(key, @"com.apple.CoreSimulator.CoreSimulatorBridge-->fb-messenger-api",
    @"Deeplink key should handle hyphenated scheme names");
}

#pragma mark - Approval Row Generation

- (void)testPreiOS12RowsContainBundleIDAndServiceName
{
  NSSet *bundleIDs = [NSSet setWithObject:@"com.test.app"];
  NSSet *services = [NSSet setWithObject:FBTargetSettingsServiceContacts];
  NSString *rows = [FBSimulatorSettingsCommands preiOS12ApprovalRowsForBundleIDs:bundleIDs services:services];
  XCTAssertTrue([rows containsString:@"kTCCServiceAddressBook"],
    @"Row should reference the TCC service name from the mapping");
  XCTAssertTrue([rows containsString:@"com.test.app"],
    @"Row should embed the bundle ID");
}

- (void)testPostiOS15RowsUseAuthValue2ForAVCaptureCompatibility
{
  NSSet *bundleIDs = [NSSet setWithObject:@"com.test.app"];
  NSSet *services = [NSSet setWithObject:FBTargetSettingsServiceCamera];
  NSString *rows = [FBSimulatorSettingsCommands postiOS15ApprovalRowsForBundleIDs:bundleIDs services:services];
  // auth_value=2 is required for AVCaptureDevice.authorizationStatus to return
  // something other than notDetermined
  XCTAssertTrue([rows containsString:@"0, 2, 2, 2"],
    @"Post-iOS 15 must use auth_value=2 for AVCaptureDevice compatibility");
}

- (void)testPostiOS17RowsIncludePidAndBootUuidColumns
{
  NSSet *bundleIDs = [NSSet setWithObject:@"com.test.app"];
  NSSet *services = [NSSet setWithObject:FBTargetSettingsServiceMicrophone];
  NSString *rows17 = [FBSimulatorSettingsCommands postiOS17ApprovalRowsForBundleIDs:bundleIDs services:services];
  NSString *rows15 = [FBSimulatorSettingsCommands postiOS15ApprovalRowsForBundleIDs:bundleIDs services:services];
  // iOS 17 schema adds pid, pid_version, boot_uuid, last_reminded columns
  // so the row should be longer than iOS 15
  XCTAssertGreaterThan(rows17.length, rows15.length,
    @"iOS 17 rows should be longer than iOS 15 due to additional columns");
  XCTAssertTrue([rows17 containsString:@"'UNUSED'"],
    @"iOS 17 rows should contain boot_uuid placeholder");
}

- (void)testApprovalRowsGenerateCorrectCountForMultipleInputs
{
  NSSet *bundleIDs = [NSSet setWithArray:@[@"com.app1", @"com.app2"]];
  NSSet *services = [NSSet setWithArray:@[FBTargetSettingsServiceContacts, FBTargetSettingsServicePhotos]];
  NSString *rows = [FBSimulatorSettingsCommands preiOS12ApprovalRowsForBundleIDs:bundleIDs services:services];
  // 2 bundleIDs x 2 services = 4 tuples separated by ", "
  NSArray *tuples = [rows componentsSeparatedByString:@"), ("];
  XCTAssertEqual(tuples.count, 4,
    @"Should generate one tuple per bundleID-service combination (2x2=4)");
}

- (void)testApprovalRowsFilterToTCCServicesOnly
{
  NSSet *bundleIDs = [NSSet setWithObject:@"com.test.app"];
  // Location is NOT in the TCC mapping, so it should be filtered out
  NSSet *services = [NSSet setWithArray:@[FBTargetSettingsServiceContacts, FBTargetSettingsServiceLocation]];
  NSString *rows = [FBSimulatorSettingsCommands preiOS12ApprovalRowsForBundleIDs:bundleIDs services:services];
  // Only contacts should produce a row since location is not in TCC mapping
  XCTAssertTrue([rows containsString:@"kTCCServiceAddressBook"],
    @"Should include contacts which is in TCC mapping");
  XCTAssertFalse([rows containsString:@"location"],
    @"Should not include location which is not in TCC mapping");
}

#pragma mark - Grant/Revoke Access Input Validation

- (void)testGrantAccessRejectsEmptyServices
{
  FBSimulatorSettingsCommands *cmds = [self makeCommands];
  [self assertFuture:[cmds grantAccess:[NSSet setWithObject:@"com.test"] toServices:[NSSet set]]
    failsWithTimeout:1.0
    message:@"grantAccess should reject empty services set"];
}

- (void)testGrantAccessRejectsEmptyBundleIDs
{
  FBSimulatorSettingsCommands *cmds = [self makeCommands];
  [self assertFuture:[cmds grantAccess:[NSSet set] toServices:[NSSet setWithObject:FBTargetSettingsServiceContacts]]
    failsWithTimeout:1.0
    message:@"grantAccess should reject empty bundle IDs set"];
}

- (void)testRevokeAccessRejectsEmptyServices
{
  FBSimulatorSettingsCommands *cmds = [self makeCommands];
  [self assertFuture:[cmds revokeAccess:[NSSet setWithObject:@"com.test"] toServices:[NSSet set]]
    failsWithTimeout:1.0
    message:@"revokeAccess should reject empty services set"];
}

- (void)testRevokeAccessRejectsEmptyBundleIDs
{
  FBSimulatorSettingsCommands *cmds = [self makeCommands];
  [self assertFuture:[cmds revokeAccess:[NSSet set] toServices:[NSSet setWithObject:FBTargetSettingsServiceContacts]]
    failsWithTimeout:1.0
    message:@"revokeAccess should reject empty bundle IDs set"];
}

#pragma mark - Deeplink Access Validation

- (void)testGrantDeeplinkRejectsEmptyScheme
{
  FBSimulatorSettingsCommands *cmds = [self makeCommands];
  [self assertFuture:[cmds grantAccess:[NSSet setWithObject:@"com.test"] toDeeplink:@""]
    failsWithTimeout:1.0
    message:@"grantAccess:toDeeplink: should reject empty scheme"];
}

- (void)testGrantDeeplinkRejectsEmptyBundleIDs
{
  FBSimulatorSettingsCommands *cmds = [self makeCommands];
  [self assertFuture:[cmds grantAccess:[NSSet set] toDeeplink:@"myapp"]
    failsWithTimeout:1.0
    message:@"grantAccess:toDeeplink: should reject empty bundle IDs"];
}

- (void)testRevokeDeeplinkRejectsEmptyScheme
{
  FBSimulatorSettingsCommands *cmds = [self makeCommands];
  [self assertFuture:[cmds revokeAccess:[NSSet setWithObject:@"com.test"] toDeeplink:@""]
    failsWithTimeout:1.0
    message:@"revokeAccess:toDeeplink: should reject empty scheme"];
}

- (void)testRevokeDeeplinkRejectsEmptyBundleIDs
{
  FBSimulatorSettingsCommands *cmds = [self makeCommands];
  [self assertFuture:[cmds revokeAccess:[NSSet set] toDeeplink:@"myapp"]
    failsWithTimeout:1.0
    message:@"revokeAccess:toDeeplink: should reject empty bundle IDs"];
}

#pragma mark - Proxy and DNS Validation

- (void)testSetProxyRejectsNilHost
{
  FBSimulatorSettingsCommands *cmds = [self makeCommands];
  [self assertFuture:[cmds setProxyWithHost:nil port:8080 type:@"http"]
    failsWithTimeout:1.0
    message:@"setProxyWithHost should reject nil host"];
}

- (void)testSetDnsServersRejectsEmptyArray
{
  FBSimulatorSettingsCommands *cmds = [self makeCommands];
  [self assertFuture:[cmds setDnsServers:@[]]
    failsWithTimeout:1.0
    message:@"setDnsServers should reject empty array"];
}

@end
