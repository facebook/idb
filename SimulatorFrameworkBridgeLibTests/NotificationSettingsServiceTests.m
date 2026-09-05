/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <dlfcn.h>

#import <XCTest/XCTest.h>

#import <SimulatorFrameworkBridgeLib/BulletinBoardPrivate.h>
#import <SimulatorFrameworkBridgeLib/NotificationSettingsService.h>

extern int handleNotificationSettingsActionWithGateway(NSString *action, NSString *bundleID, id gateway);

@interface FakeNotificationSettingsGateway : NSObject

@property (nonatomic, strong) NSMutableDictionary<NSString *, BBSectionInfo *> *sections;

@end

@implementation FakeNotificationSettingsGateway

- (instancetype)init
{
  self = [super init];
  if (self) {
    _sections = [NSMutableDictionary dictionary];
  }
  return self;
}

- (BBSectionInfo *)sectionInfoForSectionID:(NSString *)sectionID
{
  return self.sections[sectionID];
}

- (void)setSectionInfo:(BBSectionInfo *)sectionInfo forSectionID:(NSString *)sectionID
{
  self.sections[sectionID] = sectionInfo;
}

- (NSArray<NSString *> *)allSectionIDs
{
  return self.sections.allKeys;
}

@end

@interface NotificationSettingsServiceTests : XCTestCase

@property (nonatomic, strong) FakeNotificationSettingsGateway *gateway;

@end

@implementation NotificationSettingsServiceTests

- (void)setUp
{
  [super setUp];
  XCTAssertNotEqual(dlopen("/System/Library/PrivateFrameworks/BulletinBoard.framework/BulletinBoard", RTLD_NOW), NULL);
  self.gateway = [FakeNotificationSettingsGateway new];
}

- (void)testApproveSetsAuthorizedState
{
  NSString *bundleID = @"com.example.test.approve";

  XCTAssertEqual(handleNotificationSettingsActionWithGateway(@"approve", bundleID, self.gateway), 0);

  BBSectionInfo *sectionInfo = [self.gateway sectionInfoForSectionID:bundleID];
  XCTAssertNotNil(sectionInfo);
  XCTAssertTrue(sectionInfo.allowsNotifications);
  XCTAssertEqual(sectionInfo.authorizationStatus, 2);
}

- (void)testRevokeResetsExistingSection
{
  NSString *bundleID = @"com.example.test.revoke";
  XCTAssertEqual(handleNotificationSettingsActionWithGateway(@"approve", bundleID, self.gateway), 0);

  XCTAssertEqual(handleNotificationSettingsActionWithGateway(@"revoke", bundleID, self.gateway), 0);

  BBSectionInfo *sectionInfo = [self.gateway sectionInfoForSectionID:bundleID];
  XCTAssertNotNil(sectionInfo);
  XCTAssertFalse(sectionInfo.allowsNotifications);
  XCTAssertEqual(sectionInfo.authorizationStatus, 0);
}

- (void)testRevokeWithoutAnExistingSectionSucceeds
{
  NSString *bundleID = [@"com.example.test." stringByAppendingString:NSUUID.UUID.UUIDString];

  XCTAssertEqual(handleNotificationSettingsActionWithGateway(@"revoke", bundleID, self.gateway), 0);
  XCTAssertNil([self.gateway sectionInfoForSectionID:bundleID]);
}

- (void)testRevokeWithoutABundleIDReturnsFailure
{
  XCTAssertEqual(handleNotificationSettingsActionWithGateway(@"revoke", nil, self.gateway), 1);
}

- (void)testCheckSucceeds
{
  XCTAssertEqual(handleNotificationSettingsActionWithGateway(@"check", @"com.example.test", self.gateway), 0);
}

- (void)testListWithoutABundleIDSucceeds
{
  XCTAssertEqual(handleNotificationSettingsActionWithGateway(@"list", nil, self.gateway), 0);
}

- (void)testUnknownActionReturnsFailure
{
  XCTAssertEqual(handleNotificationSettingsActionWithGateway(@"unknown", @"com.example.test", self.gateway), 1);
}

@end
