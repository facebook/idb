---
id: architecture
title: Architecture
---

idb is formed of two components that have different responsibilities.

## The idb cli

This is a python3 cli that exposes all of the functionality that idb has to offer. As it is written in Python, we can run this basically anywhere.
The cli itself just wraps a client class which can also be imported elsewhere. It talks to an idb daemon over gRPC.

## The idb_companion

The companion is a gRPC server in Objective-C and C++. It talks to the native APIs that are used for automating Simulators and Devices. It links FBSimulatorControl and FBDeviceControl to perform these tasks.
The companion is paired with a single iOS target (a device/simulator), handles executing the requested commands.

![](https://www.fbidb.io/docs/assets/idb_architecture.png)
