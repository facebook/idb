/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessIO.h"

#import "FBProcessStream.h"

@implementation FBProcessIOAttachment

- (instancetype)initWithStdIn:(nullable FBProcessStreamAttachment *)stdIn stdOut:(nullable FBProcessStreamAttachment *)stdOut stdErr:(nullable FBProcessStreamAttachment *)stdErr
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _stdIn = stdIn;
  _stdOut = stdOut;
  _stdErr = stdErr;

  return self;
}

@end

@implementation FBProcessIO

- (instancetype)initWithStdIn:(nullable FBProcessInput *)stdIn stdOut:(nullable FBProcessOutput *)stdOut stdErr:(nullable FBProcessOutput *)stdErr
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _stdIn = stdIn;
  _stdOut = stdOut;
  _stdErr = stdErr;
  _queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

  return self;
}

#pragma mark Methods

- (FBFuture<FBProcessIOAttachment *> *)attach
{
  return [[FBFuture
    futureWithFutures:@[
      [self wrapAttachment:self.stdIn],
      [self wrapAttachment:self.stdOut],
      [self wrapAttachment:self.stdErr],
    ]]
    onQueue:self.queue fmap:^ FBFuture * (NSArray<id> *attachments) {
      // Mount all the relevant std streams.
      id stdIn = attachments[0];
      if ([stdIn isKindOfClass:NSError.class]) {
        return [self detachRepropogate:stdIn];
      }
      if ([stdIn isKindOfClass:NSNumber.class]) {
        stdIn = nil;
      }
      id stdOut = attachments[1];
      if ([stdOut isKindOfClass:NSError.class]) {
        return [self detachRepropogate:stdOut];
      }
      if ([stdOut isKindOfClass:NSNumber.class]) {
        stdOut = nil;
      }
      id stdErr = attachments[2];
      if ([stdErr isKindOfClass:NSError.class]) {
        return [self detachRepropogate:stdErr];
      }
      if ([stdErr isKindOfClass:NSNumber.class]) {
        stdErr = nil;
      }
      // Everything is setup, launch the process now.
      return [FBFuture futureWithResult:[[FBProcessIOAttachment alloc] initWithStdIn:stdIn stdOut:stdOut stdErr:stdErr]];
    }];
}

- (FBFuture<NSNull *> *)detach
{
  return [[FBFuture
    futureWithFutures:@[
      [self.stdIn detach] ?: FBFuture.empty,
      [self.stdOut detach] ?: FBFuture.empty,
      [self.stdErr detach] ?: FBFuture.empty,
    ]]
    onQueue:self.queue fmap:^ FBFuture<NSNull *> * (id _) {
      for (id stream in @[self.stdIn ?: NSNull.null, self.stdOut ?: NSNull.null, self.stdErr ?: NSNull.null]) {
        NSError *error = [FBProcessIO extractErrorFromStream:stream];
        if (error) {
          return [FBFuture futureWithError:error];
        }
      }
      return FBFuture.empty;
    }];
}

#pragma mark Private

- (FBFuture *)wrapAttachment:(id<FBStandardStream>)stream
{
  if (!stream) {
    return [FBFuture futureWithResult:@YES];
  }
  return [[stream
    attach]
    onQueue:self.queue handleError:^(NSError *error) {
      return [FBFuture futureWithResult:error];
    }];
}

+ (NSError *)extractErrorFromStream:(id)stream
{
  if (![stream conformsToProtocol:@protocol(FBStandardStreamTransfer)]) {
      return nil;
  }
  return ((id<FBStandardStreamTransfer>) stream).streamError;
}

- (FBFuture<NSNull *> *)detachRepropogate:(NSError *)error
{
  return [[self
    detach]
    onQueue:self.queue chain:^(id _) {
      return [FBFuture futureWithError:error];
    }];
}


@end
