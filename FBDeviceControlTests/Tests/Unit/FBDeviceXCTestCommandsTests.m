/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>
#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBDeviceControl.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBTestManagerTestReporterDouble : NSObject <FBTestManagerTestReporter>

@property (nonatomic, assign, readwrite) BOOL testCaseDidStartForTestClassCalled;
@property (nonatomic, assign, readwrite) BOOL testCaseDidFinishForTestClassCalled;

@end

@implementation FBTestManagerTestReporterDouble

- (instancetype)init
{
  self.testCaseDidStartForTestClassCalled = NO;
  self.testCaseDidFinishForTestClassCalled = NO;
  return self;
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testCaseDidStartForTestClass:(NSString *)testClass method:(NSString *)method
{
  self.testCaseDidStartForTestClassCalled = YES;
}

- (void)testManagerMediator:(FBTestManagerAPIMediator *)mediator testCaseDidFinishForTestClass:(NSString *)testClass method:(NSString *)method withStatus:(FBTestReportStatus)status duration:(NSTimeInterval)duration
{
  self.testCaseDidFinishForTestClassCalled = YES;
}

@end

#pragma clang diagnostic pop

@interface FBDeviceXCTestCommandsTests : XCTestCase

@end

@implementation FBDeviceXCTestCommandsTests

- (void)testOverwriteXCTestRunPropertiesWithBaseProperties {
  NSDictionary<NSString *, id> *baseProperties =
    @{
      @"BundleIDBase":
        @{
          @"NoOverwrite": @"Hello",
          @"OverwriteMe": @"Hi",
        }
    };

  NSDictionary<NSString *, id> *newProperties =
  @{
    @"StubBundleId":
      @{
        @"OverwriteMe": @"Hi overwrite!",
        @"NoExist": @"It's not defined in base so it won't be used.",
        }
    };

  NSDictionary<NSString *, id> *expectedProperties =
  @{
    @"BundleIDBase":
      @{
        @"NoOverwrite": @"Hello",
        @"OverwriteMe": @"Hi overwrite!",
        }
    };

  NSDictionary<NSString *, id> *realProperties = [FBXcodeBuildOperation
                                                  overwriteXCTestRunPropertiesWithBaseProperties:baseProperties
                                                  newProperties:newProperties];

  XCTAssertEqualObjects(expectedProperties, realProperties);
}

@end
