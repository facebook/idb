/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDataDownloadInput.h"

@interface FBDataDownloadInput () <NSURLSessionDataDelegate>

@property (nonatomic, strong, readonly) NSURLSessionTask *task;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBDataDownloadInput

#pragma mark Initializers

+ (instancetype)dataDownloadWithURL:(NSURL *)url logger:(id<FBControlCoreLogger>)logger
{
  FBDataDownloadInput *download = [[self alloc] initWithURL:url logger:logger];
  [download.task resume];
  return download;
}

- (instancetype)initWithURL:(NSURL *)url logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logger = logger;
  NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.defaultSessionConfiguration;
  NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:NSOperationQueue.new];
  _input = FBProcessInput.inputFromConsumer;
  _task = [session dataTaskWithURL:url];

  return self;
}

#pragma mark NSURLSessionDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data
{
  [self.input.contents consumeData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
  if (error) {
    [self.logger.error logFormat:@"Download task %@ failed with error %@", task, error];
  }
  [self.input.contents consumeEndOfFile];
}

@end
