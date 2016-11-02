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
@property (nonatomic, copy, readonly) NSString *filePath;

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

- (NSDictionary<NSString *, NSDictionary<NSString *, NSObject *> *> *)buildXCTestRunProperties
{
  return @{
    @"StubBundleId" : @{
        @"TestHostPath" : self.testHostPath,
        @"TestBundlePath" : self.testBundlePath,
        @"UseUITargetAppProvidedByTests" : @YES,
        @"IsUITestBundle" : @YES
    }
  };
}

- (BOOL)createXCTestRunFileWithError:(NSError **)error
{
  NSString *tmp = NSTemporaryDirectory();
  NSString *file_name = [[[NSProcessInfo processInfo] globallyUniqueString] stringByAppendingPathExtension:@"xctestrun"];
  _filePath = [tmp stringByAppendingPathComponent:file_name];

  NSDictionary *testRunProperties = [self buildXCTestRunProperties];

  if (![testRunProperties writeToFile:self.filePath atomically:false]) {
    [[[[FBDeviceControlError alloc] init] describeFormat:@"Failed to write to file %@", self.filePath] fail:error];
    return NO;
  }

  return YES;
}

- (BOOL)startWithError:(NSError **)error
{
  NSParameterAssert(self.device);
  NSParameterAssert(self.testHostPath);
  NSParameterAssert(self.testBundlePath);

  if (![self createXCTestRunFileWithError:error]) {
    if (error) {
      [[[[[FBDeviceControlError alloc] init] describe:@"Failed to create xctestrun file"] causedBy:*error] fail:error];
    }
    return NO;
  }

  return YES;
}

@end
