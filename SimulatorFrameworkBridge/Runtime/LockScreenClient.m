/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "LockScreenClient.h"

#import <dlfcn.h>
#import <notify.h>

#import "Private/AccessibilityUtilitiesPrivate.h"
#import "Private/SpringBoardServicesPrivate.h"

/** SpringBoard posts this whenever the lock state changes. */
static const char *const FBLockStateNotification = "com.apple.springboard.lockstate";

@implementation FBLockScreenStatus

- (instancetype)initWithLocked:(BOOL)locked passcodeEnabled:(BOOL)passcodeEnabled
{
  self = [super init];
  if (self) {
    _locked = locked;
    _passcodeEnabled = passcodeEnabled;
  }
  return self;
}

@end

static void *loadSpringBoardServices(void)
{
  void *handle = dlopen(FBAXPathSpringBoardServices, RTLD_NOW);
  if (!handle) {
    NSLog(@"[LockScreen] Failed to load SpringBoardServices: %s", dlerror());
  }
  return handle;
}

static SBSLockScreenService *makeLockScreenService(void)
{
  if (!loadSpringBoardServices()) {
    return nil;
  }
  Class serviceClass = NSClassFromString(@"SBSLockScreenService");
  if (!serviceClass) {
    NSLog(@"[LockScreen] SBSLockScreenService class not found");
    return nil;
  }
  return [[serviceClass alloc] init];
}

/**
 * Waits up to `timeout` for `signal`. On the main thread the run loop keeps turning meanwhile, because
 * SpringBoard's services can deliver their completions on the main queue, which a blocked main thread
 * would never drain.
 */
static BOOL waitForSignal(dispatch_semaphore_t signal, NSTimeInterval timeout)
{
  if (!NSThread.isMainThread) {
    return dispatch_semaphore_wait(signal, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC))) == 0;
  }
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
  while (dispatch_semaphore_wait(signal, DISPATCH_TIME_NOW) != 0) {
    if (deadline.timeIntervalSinceNow <= 0) {
      return NO;
    }
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, true);
  }
  return YES;
}

/** The service raises from `dealloc` unless it was invalidated first, so every one created is invalidated, whatever happened. */
static void invalidateLockScreenService(SBSLockScreenService *service)
{
  @try {
    if ([service respondsToSelector:@selector(invalidate)]) {
      [service invalidate];
    }
  } @catch (NSException *exception) {
    NSLog(@"[LockScreen] Invalidating the lock screen service raised: %@", exception);
  }
}

/** Runs `request`, which must call its argument exactly once, and waits up to `timeout` for that answer. */
static FBLockScreenRequestOutcome awaitRequest(NSTimeInterval timeout, void (^request)(void (^answer)(void)))
{
  dispatch_semaphore_t answered = dispatch_semaphore_create(0);
  request(^{
    dispatch_semaphore_signal(answered);
  });
  return waitForSignal(answered, timeout) ? FBLockScreenRequestOutcomeCompleted : FBLockScreenRequestOutcomeTimedOut;
}

@implementation FBLockScreenClient

+ (FBLockScreenStatus *)currentStatus
{
  void *handle = loadSpringBoardServices();
  if (!handle) {
    return nil;
  }
  FBSBSSpringBoardServerPort serverPort = (FBSBSSpringBoardServerPort)dlsym(handle, "SBSSpringBoardServerPort");
  FBSBGetScreenLockStatus getStatus = (FBSBGetScreenLockStatus)dlsym(handle, "SBGetScreenLockStatus");
  if (!serverPort || !getStatus) {
    NSLog(@"[LockScreen] SpringBoardServices has no lock status call");
    return nil;
  }
  mach_port_t port = serverPort();
  if (port == MACH_PORT_NULL) {
    NSLog(@"[LockScreen] SpringBoard's server port is unavailable");
    return nil;
  }
  BOOL locked = NO;
  BOOL passcodeEnabled = NO;
  kern_return_t result = getStatus(port, &locked, &passcodeEnabled);
  if (result != KERN_SUCCESS) {
    NSLog(@"[LockScreen] SBGetScreenLockStatus failed: %s", mach_error_string(result));
    return nil;
  }
  return [[FBLockScreenStatus alloc] initWithLocked:locked passcodeEnabled:passcodeEnabled];
}

+ (FBLockScreenStatus *)statusAfterWaitingForLocked:(BOOL)locked timeout:(NSTimeInterval)timeout
{
  dispatch_semaphore_t changed = dispatch_semaphore_create(0);
  int token = NOTIFY_TOKEN_INVALID;
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.SimulatorFrameworkBridge.lockstate", DISPATCH_QUEUE_SERIAL);
  // Registered before the first read, so a change between that read and the wait still wakes it.
  uint32_t registration = notify_register_dispatch(FBLockStateNotification,
    &token,
    queue, ^(int _) {
      dispatch_semaphore_signal(changed);
    });
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
  FBLockScreenStatus *status = [self currentStatus];
  // A failed read ends the wait and is reported, not retried: lock and unlock are idempotent, so the caller
  // can retry the whole call.
  while (registration == NOTIFY_STATUS_OK && status && status.locked != locked) {
    if (!waitForSignal(changed, MAX(deadline.timeIntervalSinceNow, 0))) {
      break;
    }
    status = [self currentStatus];
  }
  if (registration == NOTIFY_STATUS_OK) {
    notify_cancel(token);
  }
  return status;
}

+ (FBLockScreenRequestOutcome)lockWithTimeout:(NSTimeInterval)timeout
{
  SBSLockScreenService *service = nil;
  @try {
    service = makeLockScreenService();
    if (![service respondsToSelector:@selector(lockDeviceAnimated:withCompletion:)]) {
      NSLog(@"[LockScreen] The lock screen service cannot lock the device");
      return FBLockScreenRequestOutcomeUnavailable;
    }
    return awaitRequest(timeout, ^(void (^answer)(void)) {
      [service lockDeviceAnimated:NO withCompletion:answer];
    });
  } @catch (NSException *exception) {
    NSLog(@"[LockScreen] Locking the device raised: %@", exception);
    return FBLockScreenRequestOutcomeUnavailable;
  } @finally {
    invalidateLockScreenService(service);
  }
}

+ (FBLockScreenRequestOutcome)requestUnlock
{
  @try {
    if (!dlopen(FBAXPathAccessibilityUtilities, RTLD_NOW)) {
      NSLog(@"[LockScreen] Failed to load AccessibilityUtilities: %s", dlerror());
      return FBLockScreenRequestOutcomeUnavailable;
    }
    Class serverClass = NSClassFromString(@"AXSpringBoardServer");
    if (![serverClass respondsToSelector:@selector(server)]) {
      NSLog(@"[LockScreen] AXSpringBoardServer is unavailable");
      return FBLockScreenRequestOutcomeUnavailable;
    }
    AXSpringBoardServer *server = [serverClass server];
    if (![server respondsToSelector:@selector(unlockDevice)]) {
      NSLog(@"[LockScreen] SpringBoard's accessibility server cannot unlock the device");
      return FBLockScreenRequestOutcomeUnavailable;
    }
    [server unlockDevice];
    return FBLockScreenRequestOutcomeCompleted;
  } @catch (NSException *exception) {
    NSLog(@"[LockScreen] Unlocking the device raised: %@", exception);
    return FBLockScreenRequestOutcomeUnavailable;
  }
}

@end
