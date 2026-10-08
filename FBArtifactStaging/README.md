# FBArtifactStaging

A macOS library that turns whatever a client sends to install — a local path, a URL, or an archive arriving on a stream — into a bundle on disk that a target can install.

The target frameworks only install what is already a bundle: `ApplicationCommands.install(atPath:)` takes an `.app`. Everything between the client's bytes and that path lives here, built on `FBControlCore`. `idb_companion` uses it for every install route, and it can be linked directly by other tools that install onto Simulators or Devices.

## What it provides

- **Installing from a source.** `ApplicationCommands.install(from:)` downloads, extracts and installs an `InstallSource` in one call, reporting each stage as an `InstallProgressEvent`.
- **Staging.** `Staging.withMaterialized` stages a source into a temporary directory for the duration of a closure, and `Artifact` identifies the application, test bundle, framework, dylib or dSYM inside the result.
- **Downloads.** URL sources are fetched with `URLSession` and extracted as they arrive (a zip is spooled to disk first, since its index is at the end), with progress and a `DownloadReport` of the transfer.
- **Archive extraction.** Tar (plain, gzip or zstd) and zip archives are extracted in process, sniffing the format from the first bytes rather than trusting what the client declared. Zip archives keep their file modes and symlinks, including when they arrive as a stream. `bsdtar` remains as a fallback for archives the in-process extractors do not support.
- **Archive creation.** `TarSource`, `GzippingSource` and `FBArchiveOperations` write the archives the companion sends back to clients, such as pulled files and test results.
