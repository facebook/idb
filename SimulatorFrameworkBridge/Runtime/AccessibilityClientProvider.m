/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "AccessibilityClientProvider.h"

static id<FBAXRuntime> gInjectedRuntime = nil;
static FBAXRuntimeFactory gInjectedRuntimeFactory = nil;

static id<FBAXRuntime> _Nullable FBAXBridgeCreateRuntime(FBAXRuntimeFactory factory, NSString *_Nullable *_Nullable error)
{
  @try {
    return factory(error);
  } @catch (NSException *exception) {
    NSLog(@"[AccessibilityService] runtime initialization raised: %@", exception);
    if (error) {
      *error = [NSString stringWithFormat:@"accessibility initialization raised: %@", exception.reason ?: exception.name];
    }
    return nil;
  }
}

// The runtime is bound once and reused across requests: `dlopen` + `initForRemoteAccess` is the
// dominant setup cost (~260ms), so caching it is what makes the persistent `serve` mode fast.
// Not thread-safe by design — requests are handled serially.
static id<FBAXRuntime> _Nullable FBAXBridgeSharedRuntime(NSString *_Nullable *_Nullable error)
{
  if (gInjectedRuntime) {
    return gInjectedRuntime;
  }
  if (gInjectedRuntimeFactory) {
    return FBAXBridgeCreateRuntime(gInjectedRuntimeFactory, error);
  }
  static id<FBAXRuntime> shared;
  static NSString *cachedError;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSString *setupError = nil;
    shared = FBAXBridgeCreateRuntime(^id<FBAXRuntime>(NSString **initializationError) {
      return [[FBAXLiveRuntime alloc] initWithError:initializationError];
    }, &setupError);
    cachedError = setupError;
  });
  if (!shared && error) {
    *error = cachedError ?: @"accessibility setup failed";
  }
  return shared;
}

@implementation FBAXClientProvider

+ (void)prepare
{
  FBAXBridgeSharedRuntime(NULL);
}

+ (FBAXClient *)clientWithError:(NSError **)error
{
  NSString *setupError = nil;
  id<FBAXRuntime> runtime = FBAXBridgeSharedRuntime(&setupError);
  if (!runtime) {
    if (error) {
      *error = [NSError errorWithDomain:@"FBAXRuntimeInitialization"
                                   code:1
                               userInfo:@{NSLocalizedDescriptionKey : setupError ?: @"accessibility setup failed"}];
    }
    return nil;
  }
  return [[FBAXClient alloc] initWithRuntime:runtime];
}

+ (void)setRuntimeForTesting:(id<FBAXRuntime>)runtime
{
  gInjectedRuntime = runtime;
}

+ (void)setRuntimeFactoryForTesting:(FBAXRuntimeFactory)factory
{
  gInjectedRuntimeFactory = [factory copy];
}

@end
