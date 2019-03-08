/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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

