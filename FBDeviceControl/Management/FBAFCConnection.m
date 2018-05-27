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

static NSString *AFCCodeKey = @"AFCCode";
static NSString *AFCDomainKey = @"AFCDomain";

static BOOL FBAFCOperationSuccedded(FBAFCConnection *afc, CFTypeRef operation, NSError **error) {
  int status = afc.calls.OperationGetResultStatus(operation);
  if (status == 0) {
    return YES;
  }
  NSDictionary<NSString *, id> *infoDictionary = (__bridge id)(afc.calls.OperationGetResultObject(operation));
  if (![infoDictionary isKindOfClass:[NSDictionary class]]) {
    return [[FBDeviceControlError
      describeFormat:@"AFCOperation failed. status: %d, result object: %@", status, infoDictionary]
      failBool:error];
  }

  NSNumber *code = infoDictionary[AFCCodeKey];
  NSString *domain = infoDictionary[AFCDomainKey];
  if (!code || ![code respondsToSelector:@selector(integerValue)] || !domain || ![domain isKindOfClass:NSString.class]) {
    return [[FBDeviceControlError
      describeFormat:@"AFCOperation failed. status: %d, result object: %@", status, infoDictionary]
      failBool:error];
  }
  return [[[FBDeviceControlError
    describe:@"AFCOperation failed"]
    code:code.integerValue]
    failBool:error];
}

static BOOL FBAFCRemovePathAndContents(FBAFCConnection *afc, CFStringRef path, NSError **error)
{
  CFTypeRef operation = afc.calls.OperationCreateRemovePathAndContents(CFGetAllocator(afc.connection), path, NULL);
  if (operation == nil) {
    return [[FBDeviceControlError
      describe:@"Operation couldn't be created"]
      failBool:error];
  }
  int op_result = afc.calls.ConnectionProcessOperation(afc.connection, operation);
  if (op_result != 0) {
    CFRelease(operation);
    return [[FBDeviceControlError
      describeFormat:@"Operation couldn't be processed (%d)", op_result]
      failBool:error];
  }
  BOOL success = FBAFCOperationSuccedded(afc, operation, error);
  CFRelease(operation);
  return success;
}

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

#pragma mark Public Methods

- (BOOL)copyFromHost:(NSURL *)url toContainerPath:(NSString *)containerPath error:(NSError **)error
{
  NSNumber *isDir;
  if (![url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:error]) {
    return NO;
  }
  if (isDir.boolValue) {
    containerPath = [containerPath stringByAppendingPathComponent:url.lastPathComponent];
    BOOL success = [self createDirectory:containerPath error:error];
    if (!success) {
      return NO;
    }
    return [self copyContentsOfHostDirectory:url toContainerPath:containerPath error:error];
  } else {
    return [self copyFileFromHost:url toContainerPath:[containerPath stringByAppendingPathComponent:url.lastPathComponent] error:error];
  }
}

- (BOOL)createDirectory:(NSString *)path error:(NSError **)error
{
  mach_error_t result = self.calls.DirectoryCreate(self.connection, [path UTF8String]);
  if (result != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Error when creating directory: %d", result]
      failBool:error];
  }
  return YES;
}

const char *SingleDot = ".";
const char *DoubleDot = "..";

- (NSArray<NSString *> *)contentsOfDirectory:(NSString *)path error:(NSError **)error
{
  CFTypeRef directory;
  mach_error_t result = self.calls.DirectoryOpen(self.connection, path.UTF8String, &directory);
  if (result != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Error when opening directory: %d", result]
      fail:error];
  }
  NSMutableArray<NSString *> *dirs = [NSMutableArray array];
  while (YES) {
    char *listing = nil;
    result = self.calls.DirectoryRead(self.connection, directory, &listing);
    if (!listing) {
      break;
    }
    if (strcmp(listing, SingleDot) == 0 || strcmp(listing, DoubleDot) == 0) {
      continue;
    }

    [dirs addObject:[NSString stringWithUTF8String:listing]];
  }

  self.calls.DirectoryClose(self.connection, directory);
  return [NSArray arrayWithArray:dirs];
}

- (NSData *)contentsOfPath:(NSString *)path error:(NSError **)error
{
  CFTypeRef file;
  mach_error_t result = self.calls.FileRefOpen(self.connection, [path UTF8String], FBAFCReadOnlyMode, &file);
  if (result != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Error when opening file: %x", result]
      fail:error];
  }
  self.calls.FileRefSeek(self.connection, file, 0, 2);
  uint64_t offset = 0;
  self.calls.FileRefTell(self.connection, file, &offset);
  NSMutableData *buffer = [[NSMutableData alloc] initWithLength:offset];
  uint64_t len = offset;
  uint64_t toRead = len;
  self.calls.FileRefSeek(self.connection, file, 0, 0);
  while (toRead > 0) {
    uint64_t read = toRead;
    result = self.calls.FileRefRead(self.connection, file, [buffer mutableBytes] + (len - toRead), &read);
    toRead -= read;
    if (result != 0) {
      self.calls.FileRefClose(self.connection, file);
      return [[FBDeviceControlError
        describeFormat:@"Error when reading file: %x", result]
        fail:error];
    }
  }
  self.calls.FileRefClose(self.connection, file);
  return buffer;
}

- (BOOL)removePath:(NSString *)path recursively:(BOOL)recursively error:(NSError **)error
{
  if (recursively) {
    return FBAFCRemovePathAndContents(self.connection, (__bridge CFStringRef)(path), error);
  } else {
    mach_error_t result = self.calls.RemovePath(self.connection, [path UTF8String]);
    if (result != 0) {
      return [[FBDeviceControlError
        describeFormat:@"Error when removing path: %d", result]
        failBool:error];
    }
  }
  return YES;
}

#pragma mark Private

- (BOOL)copyFileFromHost:(NSURL *)path toContainerPath:(NSString *)containerPath error:(NSError **)error
{
  NSData *data = [NSData dataWithContentsOfURL:path];
  if (!data) {
    return [[FBDeviceControlError
      describeFormat:@"Could not find file on host: %@", path]
      failBool:error];
  }

  CFTypeRef fileReference;
  mach_error_t result = self.calls.FileRefOpen(self.connection, containerPath.UTF8String, FBAFCreateReadAndWrite, &fileReference);
  if (result != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Error when opening file: %x", result]
      failBool:error];
  }

  __block mach_error_t writeResult = 0;
  [data enumerateByteRangesUsingBlock:^(const void *bytes, NSRange byteRange, BOOL *stop) {
    if (byteRange.length == 0) {
      return;
    }
    writeResult = self.calls.FileRefWrite(self.connection, fileReference, bytes, byteRange.length);
    if (writeResult != 0) {
      *stop = YES;
    }
  }];
  self.calls.FileRefClose(self.connection, fileReference);
  if (writeResult != 0) {
    return [[FBDeviceControlError
      describeFormat:@"Error when writing file: %x", writeResult]
      failBool:error];
  }
  return YES;
}

- (BOOL)copyContentsOfHostDirectory:(NSURL *)path toContainerPath:(NSString *)containerPath error:(NSError **)error
{
  NSFileManager *fileManager = NSFileManager.defaultManager;
  NSDirectoryEnumerator<NSURL *> *urls = [fileManager
    enumeratorAtURL:path
    includingPropertiesForKeys:@[NSURLIsDirectoryKey]
    options:NSDirectoryEnumerationSkipsSubdirectoryDescendants
    errorHandler:NULL];

  for (NSURL *url in urls) {
    BOOL success = [self copyFromHost:url toContainerPath:containerPath error:error];
    if (!success) {
      return NO;
    }
  }

  return YES;
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
