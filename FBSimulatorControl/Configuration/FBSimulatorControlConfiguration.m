/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorControlConfiguration.h"

#import <CoreSimulator/CDStructures.h>
#import <CoreSimulator/SimDeviceSet.h>
#import <CoreSimulator/SimDeviceSet+Removed.h>

#import <FBControlCore/FBControlCore.h>

#import <objc/runtime.h>
#import <objc/message.h>

#import "FBSimulatorControl+PrincipalClass.h"
#import "FBSimulatorControlFrameworkLoader.h"

@interface FBSimulatorControlConfiguration ()

@property (nonatomic, copy, readwrite) NSString *deviceSetPath;

@end

@implementation FBSimulatorControlConfiguration

+ (void)initialize
{
  [FBSimulatorControlFrameworkLoader.essentialFrameworks loadPrivateFrameworksOrAbort];
}

#pragma mark Initializers

+ (instancetype)configurationWithDeviceSetPath:(NSString *)deviceSetPath logger:(id<FBControlCoreLogger>)logger reporter:(id<FBEventReporter>)reporter
{
  return [[self alloc] initWithDeviceSetPath:deviceSetPath logger:(logger ?: FBControlCoreGlobalConfiguration.defaultLogger) reporter:reporter];
}

- (instancetype)initWithDeviceSetPath:(NSString *)deviceSetPath logger:(id<FBControlCoreLogger>)logger reporter:(id<FBEventReporter>)reporter
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _deviceSetPath = deviceSetPath;
  _logger = logger;
  _reporter = reporter;

  return self;
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark NSObject

- (NSUInteger)hash
{
  return self.deviceSetPath.hash;
}

- (BOOL)isEqual:(FBSimulatorControlConfiguration *)object
{
  if (![object isKindOfClass:self.class]) {
    return NO;
  }
  return ((self.deviceSetPath == nil && object.deviceSetPath == nil) || [self.deviceSetPath isEqual:object.deviceSetPath]);
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Pool Config | Set Path %@",
    self.deviceSetPath
  ];
}

@end

@implementation FBSimulatorControlConfiguration (Helpers)

+ (NSString *)defaultDeviceSetPath
{
  static dispatch_once_t onceToken;
  static NSString *deviceSetPath = nil;
  
  dispatch_once(&onceToken, ^{
    @autoreleasepool {
      Class deviceSetClass = objc_lookUpClass("SimDeviceSet");
      NSAssert(deviceSetClass, @"Expected SimDeviceSet to be loaded");
      
      // Try Xcode <= 15 API first
      if ([deviceSetClass respondsToSelector:@selector(defaultSetPath)]) {
        deviceSetPath = [deviceSetClass defaultSetPath];
        id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
        [logger logFormat:@"Using SimDeviceSet.defaultSetPath (Xcode ≤15 API): %@", deviceSetPath];
        return;
      }
      
      // For Xcode 16+, we need to use SimServiceContext
      Class serviceContextClass = objc_lookUpClass("SimServiceContext");
      if (serviceContextClass) {
        // Try to get shared context using sharedServiceContextForDeveloperDir:error:
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
        SEL sharedContextSelector = @selector(sharedServiceContextForDeveloperDir:error:);
#pragma clang diagnostic pop
        if ([serviceContextClass respondsToSelector:sharedContextSelector]) {
          NSError *error = nil;
          NSString *developerDir = [NSProcessInfo.processInfo.environment objectForKey:@"DEVELOPER_DIR"];
          // Fallback to default Xcode location if DEVELOPER_DIR not set
          if (!developerDir) {
            NSString *defaultPath = @"/Applications/Xcode.app/Contents/Developer";
            if ([[NSFileManager defaultManager] fileExistsAtPath:defaultPath]) {
              developerDir = defaultPath;
            } else {
              id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
              [logger logFormat:@"Default Xcode path not found at %@, DEVELOPER_DIR not set", defaultPath];
              return;
            }
          }
          
          id sharedContext = ((id (*)(id, SEL, id, NSError **))objc_msgSend)(serviceContextClass, sharedContextSelector, developerDir, &error);
          
          if (sharedContext) {
            // Use defaultDeviceSetWithError: method
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
            SEL defaultSetSelector = @selector(defaultDeviceSetWithError:);
#pragma clang diagnostic pop
            if ([sharedContext respondsToSelector:defaultSetSelector]) {
              error = nil;
              id deviceSet = ((id (*)(id, SEL, NSError **))objc_msgSend)(sharedContext, defaultSetSelector, &error);
              if (deviceSet && [deviceSet respondsToSelector:@selector(setPath)]) {
                deviceSetPath = [deviceSet performSelector:@selector(setPath)];
                id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
                [logger logFormat:@"Using SimServiceContext API (Xcode 16+) with developerDir: %@, deviceSetPath: %@", developerDir, deviceSetPath];
                return;
              }
            }
          }
        }
      }
      
      // Fallback: Try the old defaultSet method (though it won't work on Xcode 16+)
      if ([deviceSetClass respondsToSelector:@selector(defaultSet)]) {
        id defaultSet = [deviceSetClass performSelector:@selector(defaultSet)];
        if (defaultSet && [defaultSet respondsToSelector:@selector(setPath)]) {
          deviceSetPath = [defaultSet performSelector:@selector(setPath)];
          return;
        }
      }
      
      // Log failure for diagnostics
      id<FBControlCoreLogger> logger = FBControlCoreGlobalConfiguration.defaultLogger;
      [logger logFormat:@"CoreSimulator API changed - unable to determine default device set path. Tried both SimDeviceSet.defaultSet and SimServiceContext.defaultDeviceSetWithError:"];
    }
  });
  
  return deviceSetPath;
}

@end
