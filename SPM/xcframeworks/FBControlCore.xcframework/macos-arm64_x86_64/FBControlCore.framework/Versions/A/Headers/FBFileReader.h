/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBDataConsumer.h>
#import <FBControlCore/FBFuture.h>

/**
 The File Reader States
 */
typedef NS_ENUM(NSUInteger, FBFileReaderState) {
  FBFileReaderStateNotStarted = 0,
  FBFileReaderStateReading = 1,
  FBFileReaderStateFinishedReadingNormally = 2,
  FBFileReaderStateFinishedReadingInError = 3,
  FBFileReaderStateFinishedReadingByCancellation = ECANCELED,
};

// Protocol defined in Swift (FBFileReaderProtocol.swift)
@protocol FBFileReaderProtocol;
