// Copyright 2004-present Facebook. All Rights Reserved.

#import "FBMultiFileReader.h"

#import "FBControlCoreError.h"

@interface FBIOReadInfo : NSObject

@property (nonatomic, strong) dispatch_io_t io;
@property (nonatomic, assign) BOOL done;
@property (nonatomic, assign) int errorCode;

@end

@implementation FBIOReadInfo

@end

@interface FBMultiFileReader ()

@property (nonatomic, strong) NSMutableDictionary<NSNumber *, void (^)(NSData *)> *consumers;

@end

@implementation FBMultiFileReader

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _consumers = [NSMutableDictionary dictionary];

  return self;
}

- (BOOL)addFileHandle:(NSFileHandle *)handle withConsumer:(void (^)(NSData *data))consumer error:(NSError **)error
{
  NSNumber *fileDescriptor = @(handle.fileDescriptor);
  if (self.consumers[fileDescriptor] != nil) {
    return [[FBControlCoreError describeFormat:@"Cannot add file descriptor %@ more than once.", fileDescriptor] failBool:error];
  }
  self.consumers[fileDescriptor] = consumer;

  return YES;
}

- (BOOL)readWhileBlockRuns:(void (^)())block error:(NSError **)error
{
  dispatch_queue_t queue = dispatch_queue_create("com.facebook.fbxctest.multifilereader", DISPATCH_QUEUE_SERIAL);
  dispatch_group_t group = dispatch_group_create();
  NSArray<NSNumber *> *fileDescriptors = self.consumers.allKeys;
  NSMutableArray<FBIOReadInfo *> *infos = [NSMutableArray arrayWithCapacity:fileDescriptors.count];
  for (NSNumber *fileDescriptor in fileDescriptors) {
    FBIOReadInfo *info = [FBIOReadInfo alloc];
    [infos addObject:info];
    dispatch_group_enter(group);
    info.io = dispatch_io_create(DISPATCH_IO_STREAM, fileDescriptor.intValue, queue, ^(int errorCode) {
      if (errorCode) {
        NSLog(@"Failed to create IO channel for fd %@ with error code %d.", fileDescriptor, errorCode);
      }
    });
    if (info.io == NULL) {
      return [[FBControlCoreError describeFormat:@"Failed to create IO channel for fd %@.", fileDescriptor] failBool:error];
    }
    // Report partial results with as little as 1 byte read.
    dispatch_io_set_low_water(info.io, 1);
    dispatch_io_read(info.io, 0, SIZE_MAX, queue, ^(bool done, dispatch_data_t data, int errorCode) {
      if (info.done) {
        return;
      }
      if (done) {
        dispatch_group_leave(group);
        info.done = YES;
      }
      if (errorCode != 0) {
        if (errorCode != ECANCELED) {
          info.errorCode = errorCode;
        }
        return;
      }
      if (data != NULL) {
        const void *buffer;
        size_t size;
        __unused dispatch_data_t map = dispatch_data_create_map(data, &buffer, &size);
        void (^consumer)(NSData *) = self.consumers[fileDescriptor];
        consumer([NSData dataWithBytes:buffer length:size]);
      }
    });
  }

  // Wait until the specified block stops running.
  block();

  dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_MSEC * 500);
  dispatch_group_wait(group, timeout);

  FBControlCoreError *errorObject = nil;
  for (FBIOReadInfo *info in infos) {
    dispatch_sync(queue, ^{
      if (!info.done) {
        dispatch_group_leave(group);
        info.done = YES;
      }
      dispatch_io_close(info.io, DISPATCH_IO_STOP);
      info.io = NULL;
    });
    if (info.errorCode != 0) {
      errorObject = [FBControlCoreError describeFormat:@"Reading from file descriptor failed with error %d.", info.errorCode];
    }
  }

  if (errorObject != nil) {
    return [errorObject failBool:error];
  }

  return YES;
}

@end
