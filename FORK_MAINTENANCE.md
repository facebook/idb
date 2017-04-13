### Maintenance

The master branch of our fork will be kept in step with the upstream
master. Periodically, we create a branch that _rebases our changes over
the upstream master_. The artifact of this rebase will be a git tag.
This strategy several advantages over periodically merging
upstream/master into our fork (the pull/merge strategy).

Our changes are always at the top so they are easily separable from
upstream changes. Using a merge strategy would mean our changes mingled
with the upstream changes.

Creating a tag makes provenance easy to track and builds to be
reproducible.

There will be times where we have an open pull request on the upstream
repository that contains a critical fix that must be released before the
pull request is merged.  Using a pull/merge strategy, we would have
perform an upstream/master merge and then rebase our open pull
request on top of the merge.   See **Xcode 8.3 support rebased onto
week 12 Facebook: 0.3.0 5c0e277 Thu Mar 16**
[#26](https://github.com/calabash/FBSimulatorControl/pull/26) for an
example of this. The rebase strategy avoid the additional rebase:  the
change set form the PR already exists in our set of changes.  If the PR
in question is merged to upstream/master, we can easy drop our existing
changes during the next rebase (because they will already be in
upstream/master).

You can see this strategy at work in our xamarin/appium fork:

* [master](https://github.com/xamarin/appium)
* [tags](https://github.com/xamarin/appium/tags)

The `develop` branch is where we make incremental changes prior to
creating a release tag and it is where we make new tags from.


### Example

```
$ git remote -v
origin  git@github.com:calabash/FBSimulatorControl.git (fetch)
origin  git@github.com:calabash/FBSimulatorControl.git (push)
upstream        git@github.com:facebook/FBSimulatorControl.git (fetch)
upstream        git@github.com:facebook/FBSimulatorControl.git (push)

$ git co master
$ git pull origin master
$ git fetch upstream master

$ git co develop
$ git pull origin develop

$ git co -b feature/0.4.0-99e9b49-Jul-12-2017

# Replay our commits over master.
$ git rebase -i master
```
