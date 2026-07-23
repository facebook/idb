/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 An Option Set for Process Termination.
 */
typedef NS_ENUM(NSUInteger, FBProcessTerminationStrategyOptions) {
  FBProcessTerminationStrategyOptionsCheckProcessExistsBeforeSignal = 1 << 2, /** Checks for the process to exist before signalling **/
  FBProcessTerminationStrategyOptionsCheckDeathAfterSignal = 1 << 3, /** Waits for the process to die before returning **/
  FBProcessTerminationStrategyOptionsBackoffToSIGKILL = 1 << 4, /** Whether to backoff to SIGKILL if a less severe signal fails **/
};

/**
 A Configuration for the Strategy.
 */
typedef struct {
  int signo;
  FBProcessTerminationStrategyOptions options;
} FBProcessTerminationStrategyConfiguration;
