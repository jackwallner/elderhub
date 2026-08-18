fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios download_state

```sh
[bundle exec] fastlane ios download_state
```

Download current metadata + screenshots from App Store Connect into /tmp/asc-live

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload screenshots and metadata to App Store Connect

### ios submit_review

```sh
[bundle exec] fastlane ios submit_review
```

Submit the draft version for App Store review (metadata already uploaded)

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
