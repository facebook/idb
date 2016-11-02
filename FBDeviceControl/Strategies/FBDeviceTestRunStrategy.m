/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBDeviceControl/FBDeviceControl.h>

@interface FBDeviceTestRunStrategy ()

@property (nonatomic, strong, readonly) FBDevice *device;
@property (nonatomic, copy, readonly) NSString *testHostPath;
@property (nonatomic, copy, readonly) NSString *testBundlePath;

@end

@implementation FBDeviceTestRunStrategy


+ (instancetype)strategyWithDevice:(FBDevice *)device
                      testHostPath:(nullable NSString *)testHostPath
                    testBundlePath:(nullable NSString *)testBundlePath
{
  return [[self alloc] initWithDevice:device testHostPath:testHostPath testBundlePath:testBundlePath];
}

- (instancetype)initWithDevice:(FBDevice *)device
                  testHostPath:(nullable NSString *)testHostPath
                testBundlePath:(nullable NSString *)testBundlePath
{
  _device = device;
  _testHostPath = testHostPath;
  _testBundlePath = testBundlePath;

  return self;
}

- (BOOL)startWithError:(NSError **)error
{
  NSParameterAssert(self.device);
  NSParameterAssert(self.testHostPath);
  NSParameterAssert(self.testBundlePath);

  return YES;
}

@end
