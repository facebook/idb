/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "DynamicStoreTestRuntime.h"

#import <stdio.h>
#import <unistd.h>

#import <SimulatorFrameworkBridgeLib/DynamicStoreService.h>
#import <SimulatorFrameworkBridgeLib/SystemConfigurationLoader.h>
#import <SimulatorFrameworkBridgeLib/SystemConfigurationPrivate.h>

static FBDynamicStoreTestRuntime *runtime;

static SCDynStoreRef createStore(CFAllocatorRef allocator, CFStringRef name, void *callback, void *context)
{
  [runtime.operations addObject:[@"create:" stringByAppendingString:(__bridge NSString *)name]];
  return runtime.storeAvailable ? (void *)CFRetain(CFSTR("test store")) : NULL;
}

static CFPropertyListRef copyValue(SCDynStoreRef store, CFStringRef key)
{
  [runtime.operations addObject:@"read"];
  [runtime.keys addObject:(__bridge NSString *)key];
  return runtime.value ? CFBridgingRetain(runtime.value) : NULL;
}

static Boolean setValue(SCDynStoreRef store, CFStringRef key, CFPropertyListRef value)
{
  [runtime.operations addObject:@"write"];
  [runtime.keys addObject:(__bridge NSString *)key];
  if (!runtime.writeSucceeds) {
    return false;
  }
  runtime.value = (__bridge id)value;
  return true;
}

static Boolean removeValue(SCDynStoreRef store, CFStringRef key)
{
  [runtime.operations addObject:@"remove"];
  [runtime.keys addObject:(__bridge NSString *)key];
  if (!runtime.writeSucceeds) {
    return false;
  }
  runtime.value = nil;
  return true;
}

static Boolean notifyValue(SCDynStoreRef store, CFStringRef key)
{
  [runtime.operations addObject:@"notify"];
  [runtime.keys addObject:(__bridge NSString *)key];
  return true;
}

static int lastError(void)
{
  return runtime.value ? 0 : runtime.errorStatus;
}

@implementation FBDynamicStoreTestRuntime

- (instancetype)init
{
  self = [super init];
  if (self) {
    _libraryAvailable = YES;
    _storeAvailable = YES;
    _writeSucceeds = YES;
    _errorStatus = 1004; // kSCStatusNoKey
    _missingSymbols = [NSSet set];
    _operations = [NSMutableArray array];
    _keys = [NSMutableArray array];
    _output = [NSData data];
  }
  return self;
}

- (int)runAction:(NSString *)action arguments:(NSArray<NSString *> *)arguments input:(NSData *)input
{
  runtime = self;
  FBSystemConfigurationSetLoaderForTesting(^void *{
    [runtime.operations addObject:@"load"];
    return runtime.libraryAvailable ? (__bridge void *)runtime : NULL;
  }, ^void *(void *library, const char *symbol) {
    NSString *name = [NSString stringWithUTF8String:symbol];
    [runtime.operations addObject:[@"lookup:" stringByAppendingString:name]];
    if ([runtime.missingSymbols containsObject:name]) {
      return NULL;
    }
    if ([name isEqualToString:@"SCDynamicStoreCreate"]) {
      return (void *)createStore;
    }
    if ([name isEqualToString:@"SCDynamicStoreCopyValue"]) {
      return (void *)copyValue;
    }
    if ([name isEqualToString:@"SCDynamicStoreSetValue"]) {
      return (void *)setValue;
    }
    if ([name isEqualToString:@"SCDynamicStoreRemoveValue"]) {
      return (void *)removeValue;
    }
    if ([name isEqualToString:@"SCDynamicStoreNotifyValue"]) {
      return (void *)notifyValue;
    }
    if ([name isEqualToString:@"SCError"]) {
      return (void *)lastError;
    }
    return NULL;
  });

  // The service reads the snapshot to restore from stdin and writes its own to stdout, so both
  // descriptors are replaced for the duration of the call rather than passed in.
  fflush(stdout);
  FILE *capture = tmpfile();
  FILE *feed = tmpfile();
  int savedOut = dup(STDOUT_FILENO);
  int savedIn = dup(STDIN_FILENO);
  NSAssert(capture && feed && savedOut >= 0 && savedIn >= 0, @"Cannot replace the service's descriptors");
  if (input.length > 0) {
    fwrite(input.bytes, 1, input.length, feed);
    fflush(feed);
  }
  rewind(feed);
  NSAssert(dup2(fileno(capture), STDOUT_FILENO) >= 0, @"Cannot redirect service output");
  NSAssert(dup2(fileno(feed), STDIN_FILENO) >= 0, @"Cannot feed service input");
  @try {
    return handleDynamicStoreAction(action, arguments);
  } @finally {
    fflush(stdout);
    dup2(savedOut, STDOUT_FILENO);
    dup2(savedIn, STDIN_FILENO);
    close(savedOut);
    close(savedIn);
    rewind(capture);
    NSMutableData *data = [NSMutableData data];
    unsigned char buffer[1024];
    size_t count;
    while ((count = fread(buffer, 1, sizeof(buffer), capture)) > 0) {
      [data appendBytes:buffer length:count];
    }
    fclose(capture);
    fclose(feed);
    _output = data;
    FBSystemConfigurationSetLoaderForTesting(nil, nil);
    runtime = nil;
  }
}

@end
