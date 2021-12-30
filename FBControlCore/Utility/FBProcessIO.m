/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBProcessIO.h"

#import "FBProcessStream.h"
#import "FBControlCoreError.h"

@interface FBProcessIO ()

@property (nonatomic, assign, readwrite) BOOL attached;
@property (nonatomic, nullable, readwrite) FBMutableFuture<NSNull *> *detachment;

- (FBFuture<NSNull *> *)detach;

@end

@interface FBProcessIOAttachment ()

@property (nonatomic, strong, readonly) FBProcessIO *io;

@end

@implementation FBProcessIOAttachment

- (instancetype)initWithIO:(FBProcessIO *)io stdIn:(nullable FBProcessStreamAttachment *)stdIn stdOut:(nullable FBProcessStreamAttachment *)stdOut stdErr:(nullable FBProcessStreamAttachment *)stdErr
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _io = io;
  _stdIn = stdIn;
  _stdOut = stdOut;
  _stdErr = stdErr;

  return self;
}

- (FBFuture<NSNull *> *)detach
{
  return [self.io detach];
}

@end

@interface FBProcessFileAttachment ()

@property (nonatomic, strong, readonly) FBProcessIO *io;

@end

@implementation FBProcessFileAttachment

- (instancetype)initWithIO:(FBProcessIO *)io stdOut:(nullable id<FBProcessFileOutput>)stdOut stdErr:(nullable id<FBProcessFileOutput>)stdErr
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _io = io;
  _stdOut = stdOut;
  _stdErr = stdErr;

  return self;
}

- (FBFuture<NSNull *> *)detach
{
  return [self.io detach];
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
  _queue = dispatch_queue_create("com.facebook.FBControlCore.FBProcessIO", DISPATCH_QUEUE_SERIAL);

  return self;
}

+ (instancetype)outputToDevNull
{
  return [[self alloc] initWithStdIn:nil stdOut:FBProcessOutput.outputForNullDevice stdErr:FBProcessOutput.outputForNullDevice];
}

#pragma mark Methods

- (FBFuture<FBProcessIOAttachment *> *)attach
{
  return [[[self
    startExclusiveAttachment]
    onQueue:self.queue fmap:^(id _) {
      return [FBFuture futureWithFutures:@[
        [self wrapAttachment:self.stdIn],
        [self wrapAttachment:self.stdOut],
        [self wrapAttachment:self.stdErr],
      ]];
    }]
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
      return [FBFuture futureWithResult:[[FBProcessIOAttachment alloc] initWithIO:self stdIn:stdIn stdOut:stdOut stdErr:stdErr]];
    }];
}

- (FBFuture<FBProcessFileAttachment *> *)attachViaFile
{
  return [[[self
    startExclusiveAttachment]
    onQueue:self.queue fmap:^(id _) {
      return [FBFuture futureWithFutures:@[
        [self wrapFileAttachment:self.stdOut],
        [self wrapFileAttachment:self.stdErr],
      ]];
    }]
    onQueue:self.queue fmap:^ FBFuture * (NSArray<id> *attachments) {
      id stdOut = attachments[0];
      if ([stdOut isKindOfClass:NSError.class]) {
        return [self detachRepropogate:stdOut];
      }
      if ([stdOut isKindOfClass:NSNumber.class]) {
        stdOut = nil;
      }
      id stdErr = attachments[1];
      if ([stdErr isKindOfClass:NSError.class]) {
        return [self detachRepropogate:stdErr];
      }
      if ([stdErr isKindOfClass:NSNumber.class]) {
        stdErr = nil;
      }
      // Everything is setup, launch the process now.
      return [FBFuture futureWithResult:[[FBProcessFileAttachment alloc] initWithIO:self stdOut:stdOut stdErr:stdErr]];
    }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)detach
{
  return [FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSNull *> * {
      if (self.attached == NO) {
        return [[FBControlCoreError
          describeFormat:@"Cannot detach when -attach has not been called"]
          failFuture];
      }
      FBMutableFuture<NSNull *> *detachment = self.detachment;
      if (detachment) {
        return detachment;
      }
      detachment = FBMutableFuture.future;
      self.detachment = detachment;
      [detachment resolveFromFuture:[self performDetachment]];
      return detachment;
    }];
}

- (FBFuture<NSNull *> *)startExclusiveAttachment
{
  return [FBFuture
    onQueue:self.queue resolve:^ FBFuture<NSNull *> * {
      if (self.attached) {
        return [[FBControlCoreError
          describeFormat:@"Cannot -attach twice"]
          failFuture];
      }
      self.attached = YES;
      return FBFuture.empty;
    }];
}

- (FBFuture<NSNull *> *)performDetachment
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

- (FBFuture *)wrapFileAttachment:(id<FBProcessOutput>)output
{
  if (!output) {
    return [FBFuture futureWithResult:@YES];
  }
  return [[output
    providedThroughFile]
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
