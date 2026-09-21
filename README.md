# Forsakringskassan CI

This repository is the shared CI environment for the Forsakringskassan
organisation. Roughly 130 repositories get their build, test and release
pipelines from here.

Everything is organised around one rule:

> **`bundle-*` is the public API. Nothing else is.**

A repository picks the one bundle pair that matches what kind of repository it
is, and passes nothing but its secrets. Everything else — which Java version,
which Node version, how images are tagged, how versions are derived — is an
implementation detail that can change here without touching 130 repositories.

## The three tiers

| Tier | Lives in | Naming | Who may call it |
| --- | --- | --- | --- |
| **Public API** | `.github/workflows/` | `bundle-*.yaml` | Any repository in the organisation |
| **Internal workflows** | `.github/workflows/` | everything else | Only `bundle-*` workflows in this repository |
| **Internal actions** | `actions/<name>/` | — | Only workflows in this repository |
| **Self** | `.github/workflows/` | `self-*.yaml` | Nobody — these run *in* this repository |

GitHub requires all reusable workflows to sit directly in `.github/workflows/`,
so the tiers cannot be separated into folders. The naming convention *is* the
folder structure, and [`scripts/check_workflow_contract.py`](scripts/check_workflow_contract.py)
enforces it on every push.

```
caller repo             this repo
──────────────────────  ───────────────────────────────────────────────
.github/workflows/      .github/workflows/
  ci.yaml ───────────►    bundle-maven-quarkus-ci.yaml   ← public API
                            │
                            ├─► maven-ci.yaml            ← internal workflow
                            │     └─► actions/maven-settings
                            │     └─► actions/violations-to-sarif
                            ├─► app-maven-docker-quarkus.yaml
                            │     └─► actions/docker-build-push
                            └─► pnr-scanner.yaml
                                  └─► actions/pnr-scan
```

## Pick your bundle

One bundle pair per kind of repository. Repositories created from the same
template call the same bundle.

| Kind of repository | Template | CI bundle | Release bundle |
| --- | --- | --- | --- |
| Quarkus service, shipped as a container | `template-quarkus`, `template-bamoe` | `bundle-maven-quarkus-ci` | `bundle-maven-quarkus-release` |
| Maven library, published to GitHub Packages | — | `bundle-maven-lib-ci` | `bundle-maven-lib-release` |
| Gradle library / API contract (openapi, asyncapi, jar) | `template-jar`, `template-asyncapi`, `template-jar-api-generate` | `bundle-gradle-ci` | `bundle-gradle-release` |
| API contract also published to npm | `template-api` | `bundle-api-npm-ci` | `bundle-api-npm-release` |
| Web application, shipped as a container | `rimfrost-template-micro-fe` | `bundle-app-npm-ci` | `bundle-app-npm-release` |
| npm library / tooling package | `vue-lib-template` | `bundle-npm-ci` | `bundle-npm-release` |
| Helm chart | `template-kubernetes`, `template-openshift` | `bundle-helm-ci` | — |

Full input and secret reference: [docs/public-api.md](docs/public-api.md).

## Use it in your repository

Two files, and nothing else. `ci.yaml` runs on every push and pull request;
`release.yaml` is triggered by hand when you want to cut a release.

`.github/workflows/ci.yaml`

```yaml
name: CI
on: [workflow_dispatch, push, pull_request]

jobs:
  ci:
    uses: Forsakringskassan/.github/.github/workflows/bundle-maven-quarkus-ci.yaml@main
    secrets:
      PACKAGES_RW_ACTOR: ${{ secrets.PACKAGES_RW_ACTOR }}
      PACKAGES_RW_TOKEN: ${{ secrets.PACKAGES_RW_TOKEN }}
```

`.github/workflows/release.yaml`

```yaml
name: Release
on: [workflow_dispatch]

jobs:
  release:
    uses: Forsakringskassan/.github/.github/workflows/bundle-maven-quarkus-release.yaml@main
    secrets:
      PACKAGES_RW_ACTOR: ${{ secrets.PACKAGES_RW_ACTOR }}
      PACKAGES_RW_TOKEN: ${{ secrets.PACKAGES_RW_TOKEN }}
```

Per-kind snippets, including the npm variants that use a GitHub App instead of
`PACKAGES_RW_*`, are in [docs/adoption.md](docs/adoption.md).

### Pinning

Renovate in most repositories rewrites `@main` to a commit SHA with a `# main`
comment and keeps it up to date. Either form works; the SHA form is preferred
because it makes a change to this repository land as a reviewable pull request
in yours rather than silently.

Note that composite actions referenced *inside* an internal workflow always
resolve at `@main`, so pinning the workflow does not fully freeze the
behaviour. Pinning exists to make changes visible, not to freeze them.

### Adding a job the bundle does not cover

Add it as an extra job in your caller workflow next to the `uses:` job. Do not
call an internal workflow directly — those are free to change without notice.
If several repositories of the same kind need the same extra job, it belongs in
the bundle instead; open a pull request here.

## Working on this repository

- [docs/public-api.md](docs/public-api.md) — every bundle, its inputs and secrets
- [docs/internals.md](docs/internals.md) — the internal workflows and actions, and the rules for changing them
- [docs/adoption.md](docs/adoption.md) — copy-paste snippets and migration instructions per repository kind

Every push runs `self-lint.yaml`, which yamllints everything and runs the
contract checker. The contract checker verifies, among other things, that the
inputs and secrets a bundle passes actually match what the internal workflow
declares — a class of bug that has silently broken a bundle before.

`self-docker-cleanup.yaml` runs nightly and deletes untagged container versions
across the organisation. It is not part of the CI pipeline.
