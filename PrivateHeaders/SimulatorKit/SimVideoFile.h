/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

struct opaqueCMSampleBuffer;
struct opaqueCMFormatDescription;
typedef void (^CDUnknownBlockType)(void);

@protocol OS_dispatch_io;

@interface SimVideoFile : NSObject
{
  NSObject<OS_dispatch_io> *_dispatch_io;
  double _timeScale;
}

+ (id)videoFileForDispatchIO:(id)arg1 fileType:(id)arg2 error:(id *)arg3;
@property (nonatomic, assign) double timeScale;
@property (nonatomic, retain) NSObject<OS_dispatch_io> *dispatch_io;

- (void)writeSampleBuffer:(struct opaqueCMSampleBuffer *)arg1 completionQueue:(id)arg2 completionHandler:(CDUnknownBlockType)arg3;
- (void)writeData:(id)arg1;
- (void)closeFile;
- (void)dealloc;
- (id)initVideoFileForDispatchIO:(id)arg1 error:(id *)arg2;

@end
