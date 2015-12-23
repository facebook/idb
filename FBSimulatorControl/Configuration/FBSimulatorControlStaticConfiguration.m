/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlStaticConfiguration.h"

#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorLogger.h"
#import "FBTaskExecutor.h"

NSString *const FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID = @"FBSIMULATORCONTROL_SIM_UDID";
NSString *const FBSimulatorControlDebugLogging = @"FBSIMULATORCONTROL_DEBUG_LOGGING";

@implementation FBSimulatorControlStaticConfiguration

+ (NSString *)developerDirectory
{
  static dispatch_once_t onceToken;
  static NSString *directory;
  dispatch_once(&onceToken, ^{
    directory = [[[FBTaskExecutor.sharedInstance
      taskWithLaunchPath:@"/usr/bin/xcode-select" arguments:@[@"--print-path"]]
      startSynchronouslyWithTimeout:FBSimulatorControlStaticConfiguration.fastTimeout]
      stdOut];
    NSCAssert(directory, @"Xcode Path could not be determined from `xcode-select`");
  });
  return directory;
}

+ (NSDecimalNumber *)sdkVersionNumber
{
  return [NSDecimalNumber decimalNumberWithString:self.sdkVersion];
}

+ (NSNumberFormatter *)sdkVersionNumberFormatter
{
  static dispatch_once_t onceToken;
  static NSNumberFormatter *formatter;
  dispatch_once(&onceToken, ^{
    formatter = [NSNumberFormatter new];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = 1;
    formatter.maximumFractionDigits = 3;
  });
  return formatter;
}

+ (NSString *)sdkVersion
{
  static dispatch_once_t onceToken;
  static NSString *sdkVersion;
  dispatch_once(&onceToken, ^{
    NSString *showSdks= [[[FBTaskExecutor.sharedInstance
      taskWithLaunchPath:@"/usr/bin/xcodebuild" arguments:@[@"-showsdks"]]
      startSynchronouslyWithTimeout:FBSimulatorControlStaticConfiguration.fastTimeout]
      stdOut];

    NSString *pattern = @"iphonesimulator(.*)";
    NSRegularExpression *regex = [NSRegularExpression
      regularExpressionWithPattern:pattern
      options:(NSRegularExpressionOptions) 0
      error:nil];

    NSArray *matches = [regex
      matchesInString:showSdks
      options:(NSMatchingOptions) 0
      range:NSMakeRange(0, showSdks.length)];

    // If xcode license is not accepted, no sdk is shown.
    NSCAssert(matches.count >= 1, @"Could not find a match for the SDK version");

    NSTextCheckingResult *match = [matches lastObject];
    NSCAssert(
      match.numberOfRanges == 2, @"We expect to have exactly 1 match. Text is %@",
      [showSdks substringWithRange:match.range]
    );

    sdkVersion = [showSdks substringWithRange:[match rangeAtIndex:1]];
  });
  return sdkVersion;
}

+ (NSTimeInterval)fastTimeout
{
  return 10;
}

+ (NSTimeInterval)regularTimeout
{
  return 30;
}

+ (NSTimeInterval)slowTimeout
{
  return 120;
}

+ (BOOL)supportsCustomDeviceSets
{
  // Prior to Xcode 7, 'iOS Simulator.app' calls `+[SimDeviceSet defaultSet]` directly
  // This means that the '-DeviceSetPath' won't do anything for Simulators booted with prior to Xcode 7.
  // It should be possible to fix this by injecting a shim that swizzles this method in these Xcode versions.
  return [self.sdkVersionNumber isGreaterThanOrEqualTo:[NSDecimalNumber decimalNumberWithString:@"9.0"]];
}

+ (BOOL)simulatorDebugLoggingEnabled
{
  return [NSProcessInfo.processInfo.environment[FBSimulatorControlDebugLogging] boolValue];
}

+ (id<FBSimulatorLogger>)defaultLogger
{
  return FBSimulatorControlStaticConfiguration.simulatorDebugLoggingEnabled ? FBSimulatorLogger.toNSLog : nil;
}

+ (NSString *)description
{
  return [NSString stringWithFormat:
    @"Developer Directory %@ | SDK Version %@ | Supports Custom Device Sets %d | Debug Logging Enabled %d",
    self.developerDirectory,
    self.sdkVersion,
    self.supportsCustomDeviceSets,
    self.simulatorDebugLoggingEnabled
  ];
}

@end
