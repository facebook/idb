/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBSimulatorControlFrameworkLoader.h"

#import <CoreSimulatorUtilities/NSUserDefaults-SimDefaults.h>
#import <FBControlCore/FBControlCore.h>
#import <objc/message.h>

static NSString *const FBSimulatorAccessibilityBootstrapErrorDomain = @"com.facebook.FBSimulatorControl.AccessibilityBootstrap";

static NSError *FBSimulatorAccessibilityBootstrapError(NSInteger code, NSString *description)
{
  return [NSError errorWithDomain:FBSimulatorAccessibilityBootstrapErrorDomain
                             code:code
                         userInfo:@{NSLocalizedDescriptionKey: description}];
}

static void FBSimulatorInvalidateAccessibilitySession(id session)
{
  SEL selector = NSSelectorFromString(@"invalidate");
  if ([session respondsToSelector:selector]) {
    ((void (*)(id, SEL))objc_msgSend)(session, selector);
  }
}

@interface FBSimulatorAccessibilityBootstrapResult : NSObject

- (void)completeWithSession:(nullable id)session error:(nullable NSError *)error;
- (nullable id)sessionByMarkingTimedOut;
@property (nonatomic, readonly, nullable) id session;
@property (nonatomic, readonly, nullable) NSError *error;

@end

@implementation FBSimulatorAccessibilityBootstrapResult
{
  NSLock *_lock;
  id _session;
  NSError *_error;
  BOOL _timedOut;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _lock = [NSLock new];
  }
  return self;
}

- (void)completeWithSession:(id)session error:(NSError *)error
{
  [_lock lock];
  BOOL timedOut = _timedOut;
  if (!timedOut) {
    _session = session;
    _error = error;
  }
  [_lock unlock];
  if (timedOut && session) {
    FBSimulatorInvalidateAccessibilitySession(session);
  }
}

- (id)sessionByMarkingTimedOut
{
  [_lock lock];
  _timedOut = YES;
  id session = _session;
  _session = nil;
  [_lock unlock];
  return session;
}

- (id)session
{
  [_lock lock];
  id session = _session;
  [_lock unlock];
  return session;
}

- (NSError *)error
{
  [_lock lock];
  NSError *error = _error;
  [_lock unlock];
  return error;
}

@end

@interface FBSimulatorAccessibilityBootstrapAttempt : NSObject

@property (nonatomic, readonly, strong) dispatch_group_t group;
@property (nonatomic, assign) BOOL succeeded;
@property (nonatomic, nullable, strong) NSError *error;

@end

@implementation FBSimulatorAccessibilityBootstrapAttempt

- (instancetype)init
{
  self = [super init];
  if (self) {
    _group = dispatch_group_create();
    dispatch_group_enter(_group);
  }
  return self;
}

@end

@interface FBSimulatorControlFrameworkLoader ()

+ (BOOL)performAccessibilityBootstrapForSimulatorDevice:(id)simulatorDevice
                                                 timeout:(NSTimeInterval)timeout
                                                  logger:(nullable id<FBControlCoreLogger>)logger
                                                   error:(NSError **)error;

@end

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
    loader = [FBSimulatorControlFrameworkLoader_Essential loaderWithName:@"FBSimulatorControl"
                                                              frameworks:@[
                FBWeakFramework.CoreSimulator,
              ]];
  });
  return loader;
}

+ (FBSimulatorControlFrameworkLoader *)accessibilityFrameworks
{
  static dispatch_once_t onceToken;
  static FBSimulatorControlFrameworkLoader *loader;
  dispatch_once(&onceToken, ^{
    loader = [FBSimulatorControlFrameworkLoader loaderWithName:@"FBSimulatorControl"
                                                    frameworks:@[
                FBWeakFramework.AccessibilityPlatformTranslation,
              ]];
  });
  return loader;
}

+ (FBSimulatorControlFrameworkLoader *)accessibilityAutomationFrameworks
{
  static dispatch_once_t onceToken;
  static FBSimulatorControlFrameworkLoader *loader;
  dispatch_once(&onceToken, ^{
    loader = [FBSimulatorControlFrameworkLoader loaderWithName:@"FBSimulatorControl"
                                                    frameworks:@[
                FBWeakFramework.XCTDaemonControl,
                FBWeakFramework.XCUIAutomation,
              ]];
  });
  return loader;
}

+ (BOOL)bootstrapAccessibilityForSimulatorDevice:(id)simulatorDevice
                                         timeout:(NSTimeInterval)timeout
                                          logger:(id<FBControlCoreLogger>)logger
                                           error:(NSError **)error
{
  static dispatch_once_t onceToken;
  static dispatch_queue_t stateQueue;
  static NSMapTable *attempts;
  dispatch_once(&onceToken, ^{
    stateQueue = dispatch_queue_create("com.facebook.FBSimulatorControl.AccessibilityBootstrap", DISPATCH_QUEUE_SERIAL);
    attempts = [NSMapTable weakToStrongObjectsMapTable];
  });

  __block FBSimulatorAccessibilityBootstrapAttempt *attempt;
  __block BOOL ownsAttempt = NO;
  dispatch_sync(stateQueue, ^{
    attempt = [attempts objectForKey:simulatorDevice];
    if (!attempt) {
      attempt = [FBSimulatorAccessibilityBootstrapAttempt new];
      [attempts setObject:attempt forKey:simulatorDevice];
      ownsAttempt = YES;
    }
  });

  if (!ownsAttempt) {
    dispatch_group_wait(attempt.group, DISPATCH_TIME_FOREVER);
    if (!attempt.succeeded && error) {
      *error = attempt.error;
    }
    return attempt.succeeded;
  }

  NSError *bootstrapError = nil;
  BOOL succeeded = [self performAccessibilityBootstrapForSimulatorDevice:simulatorDevice
                                                                 timeout:timeout
                                                                  logger:logger
                                                                   error:&bootstrapError];
  attempt.succeeded = succeeded;
  attempt.error = bootstrapError;
  dispatch_group_leave(attempt.group);
  dispatch_sync(stateQueue, ^{
    if ([attempts objectForKey:simulatorDevice] == attempt) {
      [attempts removeObjectForKey:simulatorDevice];
    }
  });

  if (!succeeded && error) {
    *error = bootstrapError;
  }
  return succeeded;
}

+ (BOOL)performAccessibilityBootstrapForSimulatorDevice:(id)simulatorDevice
                                                 timeout:(NSTimeInterval)timeout
                                                  logger:(id<FBControlCoreLogger>)logger
                                                   error:(NSError **)error
{
  if (timeout <= 0) {
    if (error) {
      *error = FBSimulatorAccessibilityBootstrapError(1, @"Accessibility bootstrap timeout must be greater than zero");
    }
    return NO;
  }
  if (![self.accessibilityAutomationFrameworks loadPrivateFrameworks:logger error:error]) {
    return NO;
  }

  Class providerClass = NSClassFromString(@"XCUIDeviceRemoteDaemonConnectionProvider");
  SEL providerSelector = NSSelectorFromString(@"connectionProviderForSimDevice:");
  if (![providerClass respondsToSelector:providerSelector]) {
    if (error) {
      *error = FBSimulatorAccessibilityBootstrapError(2, @"The simulator remote daemon connection provider is unavailable");
    }
    return NO;
  }
  id provider = ((id (*)(id, SEL, id))objc_msgSend)(providerClass, providerSelector, simulatorDevice);
  if (!provider) {
    if (error) {
      *error = FBSimulatorAccessibilityBootstrapError(3, @"Could not create a simulator remote daemon connection provider");
    }
    return NO;
  }

  Class sessionClass = NSClassFromString(@"XCUIDeviceRemoteAutomationSession");
  SEL requestSelector = NSSelectorFromString(@"requestSessionWithDaemonConnectionProvider:completion:");
  if (![sessionClass respondsToSelector:requestSelector]) {
    if (error) {
      *error = FBSimulatorAccessibilityBootstrapError(4, @"The simulator remote automation session API is unavailable");
    }
    return NO;
  }

  dispatch_semaphore_t sessionSemaphore = dispatch_semaphore_create(0);
  FBSimulatorAccessibilityBootstrapResult *result = [FBSimulatorAccessibilityBootstrapResult new];
  id completion = ^(id session, NSError *sessionError) {
    [result completeWithSession:session error:sessionError];
    dispatch_semaphore_signal(sessionSemaphore);
  };
  ((void (*)(id, SEL, id, id))objc_msgSend)(sessionClass, requestSelector, provider, completion);

  dispatch_time_t sessionDeadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC));
  if (dispatch_semaphore_wait(sessionSemaphore, sessionDeadline) != 0) {
    id session = [result sessionByMarkingTimedOut];
    if (session) {
      FBSimulatorInvalidateAccessibilitySession(session);
    }
    if (error) {
      *error = FBSimulatorAccessibilityBootstrapError(5, @"Timed out creating the simulator remote automation session");
    }
    return NO;
  }

  id session = result.session;
  if (!session) {
    if (error) {
      *error = result.error ?: FBSimulatorAccessibilityBootstrapError(6, @"Could not create the simulator remote automation session");
    }
    return NO;
  }

  @try {
    SEL enableSelector = NSSelectorFromString(@"enableAutomationModeWithError:");
    if ([session respondsToSelector:enableSelector]) {
      NSError *enableError = nil;
      BOOL enabled = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(session, enableSelector, &enableError);
      if (!enabled) {
        if (error) {
          *error = enableError ?: FBSimulatorAccessibilityBootstrapError(7, @"Could not enable simulator automation mode");
        }
        return NO;
      }
    }

    SEL loadSelector = NSSelectorFromString(@"loadAccessibilityWithTimeout:reply:");
    if (![session respondsToSelector:loadSelector]) {
      if (error) {
        *error = FBSimulatorAccessibilityBootstrapError(8, @"The simulator automation session cannot load Accessibility");
      }
      return NO;
    }

    dispatch_semaphore_t loadSemaphore = dispatch_semaphore_create(0);
    __block BOOL loaded = NO;
    __block NSError *loadError = nil;
    id reply = ^(BOOL didLoad, NSError *returnedError) {
      loaded = didLoad;
      loadError = returnedError;
      dispatch_semaphore_signal(loadSemaphore);
    };
    ((void (*)(id, SEL, double, id))objc_msgSend)(session, loadSelector, timeout, reply);
    dispatch_time_t loadDeadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)((timeout + 1) * NSEC_PER_SEC));
    if (dispatch_semaphore_wait(loadSemaphore, loadDeadline) != 0) {
      if (error) {
        *error = FBSimulatorAccessibilityBootstrapError(9, @"Timed out loading simulator Accessibility");
      }
      return NO;
    }
    if (!loaded) {
      if (error) {
        *error = loadError ?: FBSimulatorAccessibilityBootstrapError(10, @"The simulator rejected the Accessibility load request");
      }
      return NO;
    }

    [logger log:@"Bootstrapped simulator Accessibility through a remote automation session"];
    return YES;
  } @finally {
    FBSimulatorInvalidateAccessibilitySession(session);
  }
}

+ (FBSimulatorControlFrameworkLoader *)xcodeFrameworks
{
  static dispatch_once_t onceToken;
  static FBSimulatorControlFrameworkLoader *loader;
  dispatch_once(&onceToken, ^{
    loader = [FBSimulatorControlFrameworkLoader loaderWithName:@"FBSimulatorControl"
                                                    frameworks:@[
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
  NSBundle *coreSimulatorBundle = [NSBundle bundleWithIdentifier:@"com.apple.CoreSimulator"];
  if (!coreSimulatorBundle) {
    return NO;
  }
  NSString *bundleVersionString = coreSimulatorBundle.infoDictionary[@"CFBundleVersion"];
  if (!bundleVersionString) {
    return NO;
  }
  NSDecimalNumber *bundleVersion = [NSDecimalNumber decimalNumberWithString:bundleVersionString];
  if (!bundleVersion) {
    return NO;
  }
  if ([bundleVersion isEqualToNumber:NSDecimalNumber.notANumber]) {
    return NO;
  }
  if ([bundleVersion isGreaterThanOrEqualTo:[NSDecimalNumber decimalNumberWithString:@"757"]]) {
    return NO;
  }
  void *coreSimulatorHandle = [coreSimulatorBundle dlopenExecutablePath];
  if (!coreSimulatorHandle) {
    return NO;
  }
  void (*SetHandler)(void *) = FBGetSymbolFromHandleOptional(coreSimulatorHandle, "SimLogSetHandler");
  if (!SetHandler) {
    return NO;
  }
  SetHandler(FBSimulatorControl_SimLogHandler);
  return YES;
}

@end
