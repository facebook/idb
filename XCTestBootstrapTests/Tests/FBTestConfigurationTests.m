/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>

#import <OCMock/OCMock.h>

#import <XCTestBootstrap/XCTestBootstrap.h>

@interface FBTestConfigurationTests : XCTestCase

@end

@implementation FBTestConfigurationTests

- (void)testSessionIdentifier
{
  NSError *error;
  NSUUID *sessionIdentifier = [[NSUUID alloc] initWithUUIDString:@"E621E1F8-C36C-495A-93FC-0C247A3E6E5F"];
  FBTestConfiguration *testConfiguration =
  [[[FBTestConfigurationBuilder builder]
    withSessionIdentifier:sessionIdentifier]
   buildWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue([testConfiguration isKindOfClass:FBTestConfiguration.class]);
  XCTAssertEqual(testConfiguration.sessionIdentifier, sessionIdentifier);
}

- (void)testModuleName
{
  NSError *error;
  FBTestConfiguration *testConfiguration =
  [[[FBTestConfigurationBuilder builder]
    withModuleName:@"Franek"]
   buildWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue([testConfiguration isKindOfClass:FBTestConfiguration.class]);
  XCTAssertEqual(testConfiguration.moduleName, @"Franek");
}

- (void)testBundlePath
{
  NSError *error;
  FBTestConfiguration *testConfiguration =
  [[[FBTestConfigurationBuilder builder]
    withTestBundlePath:@"MagicPath"]
   buildWithError:&error];
  XCTAssertNil(error);
  XCTAssertTrue([testConfiguration isKindOfClass:FBTestConfiguration.class]);
  XCTAssertEqual(testConfiguration.testBundlePath, @"MagicPath");
  XCTAssertNil(testConfiguration.path);
}

- (void)testSaveAs
{
  NSString *path = @"/Key/To/Heaven";
  OCMockObject<FBFileManager> *fileManagerMock = [OCMockObject mockForProtocol:@protocol(FBFileManager)];
  [[[[fileManagerMock expect] andReturnValue:@YES] ignoringNonObjectArgs] writeData:[OCMArg any] toFile:path options:0 error:[OCMArg anyObjectRef]];

  NSError *error;
  FBTestConfiguration *testConfiguration =
  [[[FBTestConfigurationBuilder builderWithFileManager:fileManagerMock]
    saveAs:path]
   buildWithError:&error];
  XCTAssertNil(error);
  XCTAssertEqual(testConfiguration.path, path);
  [fileManagerMock verify];
}

@end
