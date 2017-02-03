/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/NSError.h>

@interface NSError (SimulatorKitNSErrorAdditions)
+ (id)simkit_errorWithLocalizedDescription:(id)arg1 failureReason:(id)arg2;
+ (id)simkit_errorWithLocalizedDescriptionFormat:(id)arg1;
+ (id)simkit_errorWithLocalizedDescription:(id)arg1;
+ (id)simkit_errorWithUnderlyingError:(id)arg1 localizedDescriptionFormat:(id)arg2;
+ (id)simkit_errorWithUnderlyingError:(id)arg1 localizedDescription:(id)arg2;
+ (id)simkit_errorWithUnderlyingError:(id)arg1 localizedDescription:(id)arg2 failureReason:(id)arg3;
@end

