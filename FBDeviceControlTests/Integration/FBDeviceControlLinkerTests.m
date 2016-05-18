// Copyright 2004-present Facebook. All Rights Reserved.

#import <XCTest/XCTest.h>

#import <FBDeviceControl/FBDeviceControl.h>

@interface FBDeviceControlLinkerTests : XCTestCase

@end

@implementation FBDeviceControlLinkerTests

- (void)testLinksPrivateFrameworks
{
  [FBDeviceControlFrameworkLoader initializeFrameworks];
}

@end
