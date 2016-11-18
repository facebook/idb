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
#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBDeviceControl.h>

@interface FBDeviceControlFrameworkLoader (UNITTEST)

+ (BOOL)isAtLeastMacOSSierra;
+ (BOOL)isAtLeastXcode81;
+ (NSArray<FBWeakFramework *> *)privateFrameworks;

@end

@interface FBWeakFramework (UNITTEST)

- (NSString *)name;

@end

@interface FBDeviceControlFrameworkLoaderTests : XCTestCase

@end

@implementation FBDeviceControlFrameworkLoaderTests

- (BOOL)array:(NSArray<FBWeakFramework *> *)array containsFrameworkWithName:(NSString *)name
{
  NSUInteger index;

  index = [array indexOfObjectPassingTest:^BOOL(FBWeakFramework * _Nonnull framework,
                                                     NSUInteger idx,
                                                     BOOL * _Nonnull stop) {
    return [framework.name isEqualToString:@"DFRSupportKit"];
  }];
  return index != NSNotFound;
}

- (void)testPrivateFrameworksForAtLeastSierraAndAtLeastXcode81
{
  id MockLoader = [OCMockObject mockForClass:[FBDeviceControlFrameworkLoader class]];

  [[[MockLoader stub] andReturnValue:OCMOCK_VALUE(YES)] isAtLeastMacOSSierra];
  [[[MockLoader stub] andReturnValue:OCMOCK_VALUE(YES)] isAtLeastXcode81];

  NSArray<FBWeakFramework *> *frameworks = FBDeviceControlFrameworkLoader.privateFrameworks;

  XCTAssertTrue([self array:frameworks containsFrameworkWithName:@"DFRSupportKit"],
                @"Expected private frameworks to contain DFRSupportKit on macOS >= 10.12"
                " and Xcode >= 8.1");
  XCTAssertTrue([self array:frameworks containsFrameworkWithName:@"DVTKit"],
                @"Expected private frameworks to contain DVTKit on macOS >= 10.12"
                " and Xcode >= 8.1");

  [MockLoader verify];
}

- (void)testPrivateFrameworksForElCapAndXcode81
{
  id MockLoader = [OCMockObject mockForClass:[FBDeviceControlFrameworkLoader class]];

  [[[MockLoader stub] andReturnValue:OCMOCK_VALUE(NO)] isAtLeastMacOSSierra];
  [[[MockLoader stub] andReturnValue:OCMOCK_VALUE(YES)] isAtLeastXcode81];

  NSArray<FBWeakFramework *> *frameworks = FBDeviceControlFrameworkLoader.privateFrameworks;

  XCTAssertFalse([self array:frameworks containsFrameworkWithName:@"DFRSupportKit"],
                @"Expected private frameworks not to contain DFRSupportKit on macOS < 10.12"
                " and Xcode >= 8.1");
  XCTAssertFalse([self array:frameworks containsFrameworkWithName:@"DVTKit"],
                @"Expected private frameworks not to contain DVTKit on macOS < 10.12"
                " and Xcode >= 8.1");

  [MockLoader verify];
}

- (void)testPrivateFrameworksForSierraAndXcode80
{
  id MockLoader = [OCMockObject mockForClass:[FBDeviceControlFrameworkLoader class]];

  [[[MockLoader stub] andReturnValue:OCMOCK_VALUE(YES)] isAtLeastMacOSSierra];
  [[[MockLoader stub] andReturnValue:OCMOCK_VALUE(NO)] isAtLeastXcode81];

  NSArray<FBWeakFramework *> *frameworks = FBDeviceControlFrameworkLoader.privateFrameworks;

  XCTAssertFalse([self array:frameworks containsFrameworkWithName:@"DFRSupportKit"],
                 @"Expected private frameworks not to contain DFRSupportKit on macOS >= 10.12"
                 " and Xcode < 8.1");
  XCTAssertFalse([self array:frameworks containsFrameworkWithName:@"DVTKit"],
                 @"Expected private frameworks not to contain DVTKit on macOS >= 10.12"
                 " and Xcode < 8.1");

  [MockLoader verify];
}

- (void)testPrivateFrameworksForElCapAndXcode80
{
  id MockLoader = [OCMockObject mockForClass:[FBDeviceControlFrameworkLoader class]];

  [[[MockLoader stub] andReturnValue:OCMOCK_VALUE(NO)] isAtLeastMacOSSierra];
  [[[MockLoader stub] andReturnValue:OCMOCK_VALUE(NO)] isAtLeastXcode81];

  NSArray<FBWeakFramework *> *frameworks = FBDeviceControlFrameworkLoader.privateFrameworks;

  XCTAssertFalse([self array:frameworks containsFrameworkWithName:@"DFRSupportKit"],
                 @"Expected private frameworks not to contain DFRSupportKit on macOS < 10.12"
                 " and Xcode < 8.1");
  XCTAssertFalse([self array:frameworks containsFrameworkWithName:@"DVTKit"],
                 @"Expected private frameworks not to contain DVTKit on macOS < 10.12"
                 " and Xcode < 8.1");

  [MockLoader verify];
}

@end
