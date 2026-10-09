/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#include <TargetConditionals.h>
#include <stdbool.h>
#include <stdint.h>

#include <CoreAudio/CoreAudioTypes.h>

/// CoreAudio's audio objects, which the iOS SDK uses internally but does not declare.
typedef UInt32 IDBAudioObjectID;

typedef struct {
  UInt32 selector;
  UInt32 scope;
  UInt32 element;
} IDBAudioObjectPropertyAddress;

typedef OSStatus (*IDBAudioDeviceIOProc)(
  IDBAudioObjectID device,
  const AudioTimeStamp *now,
  const AudioBufferList *inputData,
  const AudioTimeStamp *inputTime,
  AudioBufferList *outputData,
  const AudioTimeStamp *outputTime,
  void *clientData);

/// Lock-free counters for the audio thread, which may not take a lock or allocate.
static inline uint64_t IDBAtomicLoad(uint64_t *value)
{
  return __atomic_load_n(value, __ATOMIC_SEQ_CST);
}

static inline uint64_t IDBAtomicExchange(uint64_t *value, uint64_t replacement)
{
  return __atomic_exchange_n(value, replacement, __ATOMIC_SEQ_CST);
}

static inline uint64_t IDBAtomicAdd(uint64_t *value, int64_t delta)
{
  return __atomic_fetch_add(value, (uint64_t)delta, __ATOMIC_SEQ_CST);
}

static inline bool IDBAtomicCompareExchange(uint64_t *value, uint64_t expected, uint64_t replacement)
{
  return __atomic_compare_exchange_n(value, &expected, replacement, false, __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
}

#if TARGET_OS_SIMULATOR

extern OSStatus AudioDeviceCreateIOProcID(
  IDBAudioObjectID device,
  IDBAudioDeviceIOProc proc,
  void *clientData,
  void **outIOProcID);
extern OSStatus AudioDeviceDestroyIOProcID(IDBAudioObjectID device, void *ioProcID);
extern OSStatus AudioObjectGetPropertyData(
  IDBAudioObjectID object,
  const IDBAudioObjectPropertyAddress *address,
  UInt32 qualifierDataSize,
  const void *qualifierData,
  UInt32 *dataSize,
  void *data);
extern OSStatus AudioObjectGetPropertyDataSize(
  IDBAudioObjectID object,
  const IDBAudioObjectPropertyAddress *address,
  UInt32 qualifierDataSize,
  const void *qualifierData,
  UInt32 *dataSize);
extern Boolean AudioObjectHasProperty(IDBAudioObjectID object, const IDBAudioObjectPropertyAddress *address);
extern OSStatus AudioObjectAddPropertyListener(
  IDBAudioObjectID object,
  const IDBAudioObjectPropertyAddress *address,
  void *listener,
  void *clientData);
extern OSStatus AudioObjectAddPropertyListenerBlock(
  IDBAudioObjectID object,
  const IDBAudioObjectPropertyAddress *address,
  void *queue,
  void *listener);

/// Whether this process's simulator was armed for injection when the shim loaded. Unarmed, every
/// replacement below only calls the original.
bool IDBAudioInjectionIsArmed(void);

/// The replacements dyld is pointed at, implemented in `AudioInjectionBootstrap.swift`.
OSStatus IDBAudioDeviceCreateIOProcID(
  IDBAudioObjectID device,
  IDBAudioDeviceIOProc proc,
  void *clientData,
  void **outIOProcID);
OSStatus IDBAudioDeviceDestroyIOProcID(IDBAudioObjectID device, void *ioProcID);
OSStatus IDBAudioObjectGetPropertyData(
  IDBAudioObjectID object,
  const IDBAudioObjectPropertyAddress *address,
  UInt32 qualifierDataSize,
  const void *qualifierData,
  UInt32 *dataSize,
  void *data);
OSStatus IDBAudioObjectGetPropertyDataSize(
  IDBAudioObjectID object,
  const IDBAudioObjectPropertyAddress *address,
  UInt32 qualifierDataSize,
  const void *qualifierData,
  UInt32 *dataSize);
Boolean IDBAudioObjectHasProperty(IDBAudioObjectID object, const IDBAudioObjectPropertyAddress *address);
OSStatus IDBAudioObjectAddPropertyListener(
  IDBAudioObjectID object,
  const IDBAudioObjectPropertyAddress *address,
  void *listener,
  void *clientData);
OSStatus IDBAudioObjectAddPropertyListenerBlock(
  IDBAudioObjectID object,
  const IDBAudioObjectPropertyAddress *address,
  void *queue,
  void *listener);

#endif
