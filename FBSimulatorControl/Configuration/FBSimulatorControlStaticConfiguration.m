/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorControlStaticConfiguration.h"

#include <dlfcn.h>

#import <CoreSimulator/SimRuntime.h>
#import <CoreSimulator/NSUserDefaults-SimDefaults.h>

#import "FBSimulator.h"
#import "FBSimulatorApplication.h"
#import "FBSimulatorLogger.h"
#import "FBTaskExecutor.h"

NSString *const FBSimulatorControlSimulatorLaunchEnvironmentSimulatorUDID = @"FBSIMULATORCONTROL_SIM_UDID";
NSString *const FBSimulatorControlDebugLogging = @"FBSIMULATORCONTROL_DEBUG_LOGGING";

static void LoadFrameworkAtPath(id<FBSimulatorLogger> logger, NSString *path)
{
  NSBundle *bundle = [NSBundle bundleWithPath:path];
  NSCAssert(bundle, @"Could not create a bundle at path %@", path);

  NSError *error = nil;
  BOOL success = [bundle loadAndReturnError:&error];
  NSCAssert(success, @"Could not load bundle with error %@", error);
  [logger logMessage:@"Successfully loaded %@", path.lastPathComponent];
}

/**
 Given that it is possible for FBSimulatorControl.framework to be loaded after any of the
 Private Frameworks upon which it depends, it's possible that these Frameworks may have
 been loaded from a different Developer Directory.

 In order to prevent crazy behaviour from arising, FBSimulatorControl will check the
 directories of these Frameworks match the one that is currently set.
 */
static void VerifyDeveloperDirectoryForPrivateClass(NSString *className, NSString *developerDirectory)
{
  NSBundle *bundle = [NSBundle bundleForClass:NSClassFromString(className)];
  NSCAssert(bundle, @"Could not obtain Framework bundle for class named %@", className);

  // Developer Directory is: /Applications/Xcode.app/Contents/Developer
  // The common base path is: is: /Applications/Xcode.app
  NSString *basePath = [[developerDirectory stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
  BOOL matches = [bundle.bundlePath hasPrefix:basePath];

  NSCAssert(
    matches,
    @"Expected Framework %@ to be loaded for Developer Directory at path %@, but was loaded from %@ unpredicatable behaviour may arise",
    bundle.bundlePath.lastPathComponent,
    bundle.bundlePath,
    developerDirectory
  );
}

static void LoadPrivateFrameworks(id<FBSimulatorLogger> logger)
{
  // This will assert if the directory could not be found.
  NSString *developerDirectory = FBSimulatorControlStaticConfiguration.developerDirectory;

  // A Mapping of Class Names to the Frameworks that they belong to. This serves to:
  // 1) Represent the Frameworks that FBSimulatorControl is dependent on via their classes
  // 2) Provide a path to the relevant Framework.
  // 3) Provide a class for sanity checking the Framework load.
  // 4) Provide a class that can be checked before the Framework load to avoid re-loading the same
  //    Framework if others have done so before.
  // 5) Provide a sanity check that any preloaded Private Frameworks match the current xcode-select version
  NSDictionary *classMapping = @{
    @"SimDevice" : @"Library/PrivateFrameworks/CoreSimulator.framework",
    @"DVTDevice" : @"../SharedFrameworks/DVTFoundation.framework",
    @"DTiPhoneSimulatorApplicationSpecifier" : @"../SharedFrameworks/DVTiPhoneSimulatorRemoteClient.framework"
  };
  [logger logMessage:@"Using Developer Directory %@", developerDirectory];

  for (NSString *className in classMapping) {
    NSString *relativePath = classMapping[className];
    NSString *path = [[developerDirectory stringByAppendingPathComponent:relativePath] stringByStandardizingPath];
    if (NSClassFromString(className)) {
      [logger logMessage:@"%@ is allready loaded, skipping load of framework %@", className, path];
      VerifyDeveloperDirectoryForPrivateClass(className, developerDirectory);
      continue;
    }

    [logger logMessage:@"%@ is not loaded. Loading %@ at path %@", className, path.lastPathComponent, path];
    LoadFrameworkAtPath(logger, path);

    NSCAssert(NSClassFromString(className), @"Expected %@ to be loaded after %@ was loaded", className, path.lastPathComponent);
  }
}

__attribute__((constructor)) static void EntryPoint()
{
  LoadPrivateFrameworks(FBSimulatorControlStaticConfiguration.defaultLogger);
}

void FBSetSimulatorLoggingEnabled(BOOL enabled)
{
  NSUserDefaults *simulatorDefaults = [NSUserDefaults simulatorDefaults];
  [simulatorDefaults setBool:enabled forKey:@"DebugLogging"];
}

@implementation FBSimulatorControlStaticConfiguration

+ (NSString *)developerDirectory
{
  static dispatch_once_t onceToken;
  static NSString *directory;
  dispatch_once(&onceToken, ^{
    directory = [[[FBTaskExecutor.sharedInstance
      taskWithLaunchPath:@"/usr/bin/xcode-select" arguments:@[@"--print-path"]]
      startSynchronouslyWithTimeout:10]
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
      startSynchronouslyWithTimeout:10]
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
