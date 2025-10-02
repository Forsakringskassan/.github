# Usage

Re-usable workflows

## Gradle CI

```yaml
name: Call Gradle CI

on: [workflow_dispatch, push, pull_request]

jobs:
  call-workflow:
    uses: Forsakringskassan/.github/.github/workflows/gradle-ci.yaml@main
```

## Gradle Release

```yaml
name: Call Gradle Release

on: [workflow_dispatch]

jobs:
  call-workflow:
    uses: Forsakringskassan/.github/.github/workflows/gradle-release.yaml@main
```

## Draft releases

```yaml
name: Draft release

on: [workflow_dispatch, push]

jobs:
  call-workflow:
    uses: Forsakringskassan/.github/.github/workflows/draft-release.yaml@main
```

## Publish release on push

```yaml
name: Publish release on tag push

on:
  workflow_dispatch:
  workflow_call:
  push:
    tags:
      - "*"

jobs:
  call-workflow:
    uses: Forsakringskassan/.github/.github/workflows/publish-release-on-tag-push.yaml@main
```
