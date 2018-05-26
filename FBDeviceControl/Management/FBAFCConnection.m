/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBAFCConnection.h"

#import <FBControlCore/FBControlCore.h>

#include <dlfcn.h>

#import "FBDeviceControlError.h"
#import "FBAMDServiceConnection.h"

static AFCCalls defaultCalls;

@implementation FBAFCConnection

#pragma mark Initializers

- (instancetype)initWithConnection:(AFCConnectionRef)connection calls:(AFCCalls)calls
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _connection = connection;
  _calls = calls;

  return self;
}

+ (nullable instancetype)afcFromServiceConnection:(FBAMDServiceConnection *)serviceConnection calls:(AFCCalls)calls error:(NSError **)error
{
  int socket = serviceConnection.socket;
  AFCConnectionRef afcConnection = calls.Create(0x0, socket, 0x0, 0x0, 0x0);
  return [[self alloc] initWithConnection:afcConnection calls:calls];
}

#pragma mark AFC Calls

+ (AFCCalls)defaultCalls
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    [self populateCallsFromMobileDevice:&defaultCalls];
  });
  return defaultCalls;
}

#pragma mark Private

+ (void)populateCallsFromMobileDevice:(AFCCalls *)calls
{
  void *handle = [[NSBundle bundleWithIdentifier:@"com.apple.mobiledevice"] dlopenExecutablePath];
  calls->ConnectionClose = FBGetSymbolFromHandle(handle, "AFCConnectionClose");
  calls->ConnectionOpen = FBGetSymbolFromHandle(handle, "AFCConnectionOpen");
  calls->ConnectionProcessOperation = FBGetSymbolFromHandle(handle, "AFCConnectionProcessOperation");
  calls->Create = FBGetSymbolFromHandle(handle, "AFCConnectionCreate");
  calls->DirectoryClose = FBGetSymbolFromHandle(handle, "AFCDirectoryClose");
  calls->DirectoryCreate = FBGetSymbolFromHandle(handle, "AFCDirectoryCreate");
  calls->DirectoryOpen = FBGetSymbolFromHandle(handle, "AFCDirectoryOpen");
  calls->DirectoryRead = FBGetSymbolFromHandle(handle, "AFCDirectoryRead");
  calls->FileRefClose = FBGetSymbolFromHandle(handle, "AFCFileRefClose");
  calls->FileRefOpen = FBGetSymbolFromHandle(handle, "AFCFileRefOpen");
  calls->FileRefRead = FBGetSymbolFromHandle(handle, "AFCFileRefRead");
  calls->FileRefSeek = FBGetSymbolFromHandle(handle, "AFCFileRefSeek");
  calls->FileRefTell = FBGetSymbolFromHandle(handle, "AFCFileRefTell");
  calls->FileRefWrite = FBGetSymbolFromHandle(handle, "AFCFileRefWrite");
  calls->OperationCreateRemovePathAndContents = FBGetSymbolFromHandle(handle, "AFCOperationCreateRemovePathAndContents");
  calls->OperationGetResultObject = FBGetSymbolFromHandle(handle, "AFCOperationGetResultObject");
  calls->OperationGetResultStatus = FBGetSymbolFromHandle(handle, "AFCOperationGetResultStatus");
  calls->RemovePath = FBGetSymbolFromHandle(handle, "AFCRemovePath");
  calls->RenamePath = FBGetSymbolFromHandle(handle, "AFCRenamePath");
  calls->SetSecureContext = FBGetSymbolFromHandle(handle, "AFCConnectionSetSecureContext");
}

@end
