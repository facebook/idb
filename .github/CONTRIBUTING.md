# Contributing to idb
We want to make contributing to this project as easy and transparent as possible.

## Our Development Process
`idb` is formed of an Objective-C++ server (the "companion") and a python client. 

There's a number of goals that we had in mind when building this out:
- The companion is not optimized for APIs that are convenient for users to use, we're optimizing for making it as easy as possible to use with an RPC framework.
- As much of the core functionality of dealing with Simulators and Devices is pushed down into the `FBSimulatorControl` and `FBDeviceControl` projects. This means that the companion is as simple as possible and that we build sane and easy-to-use Objective-C APIs.
- `FBSimulatorControl` and `FBDeviceControl` are pure Objective-C. This makes interop with Swift as easy as possible.
- `FBSimulatorControl` and `FBDeviceControl` projects vend their public API via protocols on `FBSimulator` and `FBDevice` instances. These APIs should expose `FBFuture` instances so that they can operate asynchronously and propogate errors.
- The companion server into the APIs of the above and performs the neccessary coercions between Objective-C data models and gRPC's Protocol Buffers.
- Any rpc that is:
  * Long Lived (e.g. `instruments`)
  * Provides incremental output (e.g. `log`)
  * Pushes large amounts of data between the client/server.
  Should use streaming gRPC calls. This means that `idb` can be as responsive and performant as possible.
- `idb` client calls are in modules under `ipc`. The name of the module is the name of the call. The calls are then dynamically attached to the client object. The reasoning behind this is it prevents bloat in the client class and makes testing of individual client commands far easier.
- The command line interface to python client calls should perform as little work as possible, other than calling the python client API.
- `idb` does not aim to be backwards and forwards compatible over a long-period of time, but we do want to be able to deploy the client and server independently over a reasonable period of time. This is important because it means that the companion and client do not need to be kept in lock-step. In scenarios such as a "Device Lab" in a data center, it's reasonable to have the companion deployed on a schedule that may be different to the clients. Fortunately, gRPC has support for clients and servers talking with different versions of the underlying Protocol Buffers.

## Pull Requests
We actively welcome your pull requests.

1. Fork the repo and create your branch from `main`.
2. If you've changed the gRPC interface, the Pull Request should contain changes to the client and the server to support this.
3. Changes to the the gRPC interface in the companion should be backwards compatible with older clients as far as possible. Any breaking changes will be versioned in minor releases.
4. Changes to the CLI that are additive are fine, breaking changes will need to be backwards compatible.
5. If you haven't already, complete the Contributor License Agreement ("CLA").

## Contributor License Agreement ("CLA")
In order to accept your pull request, we need you to submit a CLA. You only need
to do this once to work on any of Facebook's open source projects.

[Complete your CLA here](https://code.facebook.com/cla)

## Issues
We use GitHub issues to track public bugs. Please ensure your description is clear and has sufficient instructions to be able to reproduce the issue.

All issues will default to being created with the issue template. Please fill in as much as makes sense.

## Coding Style  
* 2 spaces for indentation in the Objective-C++ companion and the python client.
* 80 character line length for python. Please run [`black` against python code](https://github.com/ambv/black).

## License
By contributing to `idb`, you agree that your contributions will be licensed under the LICENSE file in the root directory of this source tree.

