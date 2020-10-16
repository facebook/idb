/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorControlFrameworkLoader.h"

#import <FBControlCore/FBControlCore.h>

#import <CoreSimulator/NSUserDefaults-SimDefaults.h>

static void FBSimulatorControl_SimLogHandler(int level, const char *function, int lineNumber, NSString *format, ...)
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  id<FBControlCoreLogger> logger = [FBControlCoreGlobalConfiguration.defaultLogger.debug withName:@"CoreSimulator"];
  [logger log:string];
}

@interface FBSimulatorControlFrameworkLoader_Essential : FBSimulatorControlFrameworkLoader

@end

@implementation FBSimulatorControlFrameworkLoader

#pragma mark Initializers

+ (FBSimulatorControlFrameworkLoader *)essentialFrameworks
{
  static dispatch_once_t onceToken;
  static FBSimulatorControlFrameworkLoader *loader;
  dispatch_once(&onceToken, ^{
    loader = [FBSimulatorControlFrameworkLoader_Essential loaderWithName:@"FBSimulatorControl" frameworks:@[
      FBWeakFramework.CoreSimulator,
      FBWeakFramework.AccessibilityPlatformTranslation,
    ]];
  });
  return loader;
}

+ (FBSimulatorControlFrameworkLoader *)xcodeFrameworks
{
  static dispatch_once_t onceToken;
  static FBSimulatorControlFrameworkLoader *loader;
  dispatch_once(&onceToken, ^{
    loader = [FBSimulatorControlFrameworkLoader loaderWithName:@"FBSimulatorControl" frameworks:@[
      FBWeakFramework.SimulatorKit,
    ]];
  });
  return loader;
}

@end

@implementation FBSimulatorControlFrameworkLoader_Essential

#pragma mark Public Methods

- (BOOL)loadPrivateFrameworks:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error
{
  if (self.hasLoadedFrameworks) {
    return YES;
  }
  BOOL loaded = [super loadPrivateFrameworks:logger error:error];
  if (loaded) {
    // Hook the default handler to call us instead.
    [FBSimulatorControlFrameworkLoader_Essential setInternalLogHandler];
    // Set CoreSimulator Logging since it is now loaded.
    [FBSimulatorControlFrameworkLoader_Essential setCoreSimulatorLoggingEnabled:(logger.level >= FBControlCoreLogLevelDebug)];
  }
  return loaded;
}

#pragma mark Private Methods

+ (void)setCoreSimulatorLoggingEnabled:(BOOL)enabled
{
  if (![NSUserDefaults respondsToSelector:@selector(simulatorDefaults)]) {
    return;
  }
  // These are stored at ~/Library/Preferences/com.apple.CoreSimulator.plist
  // This will also be picked up by CoreSimulatorService, which itself links CoreSimulator and uses -[NSUserDefaults(SimDefaults) simulatorDefaults]
  NSUserDefaults *simulatorDefaults = [NSUserDefaults simulatorDefaults];
  [simulatorDefaults setBool:enabled forKey:@"DebugLogging"];
  [simulatorDefaults synchronize];
}

+ (BOOL)setInternalLogHandler
{
  void *coreSimulatorBundle = [[NSBundle bundleWithIdentifier:@"com.apple.CoreSimulator"] dlopenExecutablePath];
  if (!coreSimulatorBundle) {
    return NO;
  }
  void (*SetHandler)(void *) = FBGetSymbolFromHandleOptional(coreSimulatorBundle, "SimLogSetHandler");
  if (!SetHandler) {
    return NO;
  }
  SetHandler(FBSimulatorControl_SimLogHandler);
  return YES;
}

@end

