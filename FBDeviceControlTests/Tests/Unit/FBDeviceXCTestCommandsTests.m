/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTest/XCTest.h>
#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBDeviceControl.h>

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

  NSDictionary<NSString *, id> *realProperties = [FBDeviceXCTestCommands
                                                  overwriteXCTestRunPropertiesWithBaseProperties:baseProperties
                                                  newProperties:newProperties];

  XCTAssertEqualObjects(expectedProperties, realProperties);
}

@end
