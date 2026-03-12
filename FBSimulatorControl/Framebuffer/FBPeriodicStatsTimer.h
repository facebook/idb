/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Private header — not part of the public FBSimulatorControl API.
// Shared timing logic for periodic stats logging across framebuffer and encoder.

#ifndef FBPeriodicStatsTimer_h
#define FBPeriodicStatsTimer_h

#import <CoreFoundation/CoreFoundation.h>

typedef struct {
    CFAbsoluteTime startTime;
    CFAbsoluteTime lastLogTime;
    CFTimeInterval interval;
} FBPeriodicStatsTimer;

/// Initialize with a log interval (e.g. 5.0 seconds).
static inline FBPeriodicStatsTimer FBPeriodicStatsTimerCreate(CFTimeInterval interval) {
    return (FBPeriodicStatsTimer){0, 0, interval};
}

/// Call on each event. Returns YES and populates outIntervalDuration/outTotalElapsed
/// if enough time has elapsed since the last log. On the very first call, initializes
/// the timer and returns NO.
static inline BOOL FBPeriodicStatsTimerTick(FBPeriodicStatsTimer *timer, CFTimeInterval *outIntervalDuration, CFTimeInterval *outTotalElapsed) {
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (timer->startTime == 0) {
        timer->startTime = now;
        timer->lastLogTime = now;
        return NO;
    }
    if (now - timer->lastLogTime < timer->interval) {
        return NO;
    }
    *outIntervalDuration = now - timer->lastLogTime;
    *outTotalElapsed = now - timer->startTime;
    timer->lastLogTime = now;
    return YES;
}

#endif /* FBPeriodicStatsTimer_h */
