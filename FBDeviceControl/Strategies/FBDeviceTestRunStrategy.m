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
@property (nonatomic, assign, readonly) NSTimeInterval timeout;
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;

@end

@implementation FBDeviceTestRunStrategy

+ (instancetype)strategyWithDevice:(FBDevice *)device
                      testHostPath:(nullable NSString *)testHostPath
                    testBundlePath:(nullable NSString *)testBundlePath
                       withTimeout:(NSTimeInterval)timeout
                     withArguments:(NSArray<NSString *> *)arguments
{
  return [[self alloc] initWithDevice:device testHostPath:testHostPath testBundlePath:testBundlePath withTimeout:timeout withArguments:arguments];
}

- (instancetype)initWithDevice:(FBDevice *)device
                  testHostPath:(nullable NSString *)testHostPath
                testBundlePath:(nullable NSString *)testBundlePath
                   withTimeout:(NSTimeInterval)timeout
                 withArguments:(NSArray<NSString *> *)arguments
{
  if (timeout <= 0) {
    timeout = FBControlCoreGlobalConfiguration.slowTimeout;
  }

  _device = device;
  _testHostPath = testHostPath;
  _testBundlePath = testBundlePath;
  _timeout = timeout;
  _arguments = arguments;

  return self;
}

- (NSDictionary<NSString *, NSDictionary<NSString *, NSObject *> *> *)buildXCTestRunProperties
{
  return @{
    @"StubBundleId" : @{
        @"TestHostPath" : self.testHostPath,
        @"TestBundlePath" : self.testBundlePath,
        @"UseUITargetAppProvidedByTests" : @YES,
        @"IsUITestBundle" : @YES,
        @"CommandLineArguments": self.arguments,
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

- (FBTask *)runXCodeBuild
{
  NSMutableArray<NSString *> *arguments = [[NSMutableArray alloc] init];

  [arguments addObject: @"xcodebuild"];
  [arguments addObject: @"test-without-building"];
  [arguments addObject: @"-xctestrun"];
  [arguments addObject: self.filePath];
  [arguments addObject: @"-destination"];
  [arguments addObject: [NSString stringWithFormat:@"id=%@", self.device.udid]];

  NSDictionary<NSString *, NSString *> *env = [[NSProcessInfo processInfo] environment];

  FBTask *task = [[[[[FBTaskBuilder withLaunchPath:@"/usr/bin/xcrun" arguments: arguments]
                     withEnvironment:env]
                    withStdOutToLogger:self.device.logger]
                   withStdErrToLogger:self.device.logger]
                  build];

  [task startSynchronouslyWithTimeout:self.timeout];
  return task;
}

- (BOOL)startWithError:(NSError **)error
{
  NSParameterAssert(self.device);
  NSParameterAssert(self.testHostPath);
  NSParameterAssert(self.testBundlePath);
  NSParameterAssert(self.timeout > 0);

  if (![self createXCTestRunFileWithError:error]) {
    if (error) {
      [[[[[FBDeviceControlError alloc] init] describe:@"Failed to create xctestrun file"] causedBy:*error] fail:error];
    }
    return NO;
  }

  FBTask *task = [self runXCodeBuild];
  if (![task wasSuccessful]) {
    [[[[[FBDeviceControlError alloc] init] describe:@"xcodebuild failed"] causedBy: [task error]] fail:error];
    return NO;
  }

  return YES;
}

@end
