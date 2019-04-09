## Maintenance

We have not merged FBSimulatorControl master to this fork since
18 Aug 2017.  Facebook has not been merging our pull requests
fast enough or at all.

We are working off our own /develop branch - creating tags as
new Xcode versions are introduced.

As of 2019, we are no longer attempting to sync with the upstream.  We
will treat this repo as a stand-alone project.

The `develop` branch is where we make incremental changes prior to
creating a release.  Releases will be created from the `develop` branch
and the master branch will be abandoned.

Use the git-tag.sh script to cut a release.
