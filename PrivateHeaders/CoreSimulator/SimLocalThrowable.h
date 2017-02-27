/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@interface SimLocalThrowable : NSObject
{
    id _data;
}

+ (id)throwableWithData:(id)arg1;
@property (retain, nonatomic) id data;

- (id)initWithData:(id)arg1;

@end
