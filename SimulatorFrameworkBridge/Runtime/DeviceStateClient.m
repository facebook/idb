/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "DeviceStateClient.h"

#import <dlfcn.h>
#import <string.h>

#import "Private/CoreMotionPrivate.h"

@implementation FBDeviceStateClient

+ (NSNumber *)currentOrientation
{
  @try {
    dlopen(FBCMFrameworkPath, RTLD_NOW);
    Class<CMDeviceStateManagerClass> managerClass = (Class<CMDeviceStateManagerClass>)NSClassFromString(@"CMDeviceStateManager");
    if (![managerClass respondsToSelector:@selector(isAvailable)] || ![managerClass isAvailable]
        || ![managerClass respondsToSelector:@selector(sharedManager)]) {
      NSLog(@"CoreMotion device state is unavailable");
      return nil;
    }
    CMDeviceStateManager *manager = [managerClass sharedManager];
    if (![manager respondsToSelector:@selector(currentDeviceState)]) {
      NSLog(@"CoreMotion current device state is unavailable");
      return nil;
    }
    CMDeviceStateEvent *event = [manager currentDeviceState];
    if (![event respondsToSelector:@selector(propertyA)]) {
      NSLog(@"CoreMotion returned no current orientation");
      return nil;
    }
    NSMethodSignature *signature = [event methodSignatureForSelector:@selector(propertyA)];
    if (signature.numberOfArguments != 2 || strcmp(signature.methodReturnType, @encode(NSInteger)) != 0) {
      NSLog(@"CoreMotion orientation signature is unsupported");
      return nil;
    }
    return @([event propertyA]);
  } @catch (NSException *exception) {
    NSLog(@"CoreMotion orientation read failed: %@", exception);
    return nil;
  }
}

@end
