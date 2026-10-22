# Appcircle CocoaPods Mirror

This step points CocoaPods at the CocoaPods repository on your artifact proxy (for example a Sonatype Nexus CocoaPods proxy), so iOS, React Native and Flutter iOS builds work on runners without internet access.

Place it **after Git Clone** and before Cocoapods Install. If `AC_MIRROR_COCOAPODS` is empty, the step does nothing.

## Optional Input Variables

- `$AC_MIRROR_COCOAPODS`: URL of a CocoaPods proxy on your artifact proxy. It serves the CDN protocol of `https://cdn.cocoapods.org/` and rewrites each pod's download to itself.
- Podfile Source (`update`, `fail` or `warn`, default `update`): what the step does when a Podfile of the project uses the public CocoaPods trunk. Set it on the step: it depends on the project.

## Why the Podfile

CocoaPods has no mirror setting. It finds the public trunk by its URL, `https://cdn.cocoapods.org/`, whether the Podfile names it or has no `source` line at all; a local repository with another URL is not used instead (tested with `pod repo add-cdn trunk <proxy>`). The proxy therefore has to be the `source` of the Podfile.

## What the Step Does

- Checks every `Podfile` of the cloned project (`Pods`, `node_modules` and build folders excluded):
  - A Podfile that already uses the proxy, or only other sources (for example your private spec repository), is left as it is.
  - A Podfile on the public trunk (`source 'https://cdn.cocoapods.org/'`, `source 'https://github.com/CocoaPods/Specs.git'`, or no `source` line) depends on the Podfile Source input:
    - `update` (default): the step replaces the public source with the proxy (or adds the proxy when there was no `source` line) in the cloned copy and logs the change. Other sources stay. Nothing is pushed back to your repository.
    - `fail`: the build stops at once and names the file, instead of failing later in Cocoapods Install on connection timeouts.
    - `warn`: the step prints a warning and the build continues.
  - A summary line gives the mode and the counts.
- Sets `COCOAPODS_DISABLE_STATS=true` for the later steps.

To keep the project and your developers' machines on the proxy as well, put the proxy in the Podfile:

```ruby
source 'https://nexus.example.com/repository/cocoapods-proxy/'
```

## Limits

- The step reads literal `source '<url>'` lines. A Podfile that builds its sources in Ruby code is not changed; set the source in the project.
- Pods with a `:git` source, and the pod sources the CocoaPods proxy cannot serve, are fetched with git: add the git mirror step.
- The Cocoapods Install step runs `pod install` without `--deployment`, so the change of source in `Podfile.lock` does not fail the build.
