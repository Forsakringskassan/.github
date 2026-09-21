# Adoption and migration

Copy-paste snippets per kind of repository, followed by migration instructions
for the repositories that do not follow the pattern yet.

## Snippets

Each kind needs exactly two files. Keep the file names `ci.yaml` and
`release.yaml` so that a repository's pipeline is recognisable at a glance.

### Quarkus service, Maven library, Gradle library, API contract

These four kinds differ only in which bundle they name. The shape is identical:

`.github/workflows/ci.yaml`

```yaml
name: CI
on: [workflow_dispatch, workflow_call, push, pull_request]

jobs:
  ci:
    uses: Forsakringskassan/.github/.github/workflows/BUNDLE-ci.yaml@main
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
    uses: Forsakringskassan/.github/.github/workflows/BUNDLE-release.yaml@main
    secrets:
      PACKAGES_RW_ACTOR: ${{ secrets.PACKAGES_RW_ACTOR }}
      PACKAGES_RW_TOKEN: ${{ secrets.PACKAGES_RW_TOKEN }}
```

Replace `BUNDLE` with `bundle-maven-quarkus`, `bundle-maven-lib`,
`bundle-gradle` or `bundle-api-npm`.

### Web application

```yaml
name: CI
on: [workflow_dispatch, workflow_call, push, pull_request]

jobs:
  ci:
    uses: Forsakringskassan/.github/.github/workflows/bundle-app-npm-ci.yaml@main
    with:
      runtime-env: true      # omit for apps built with a baked-in config
    secrets:
      PACKAGES_RW_ACTOR: ${{ secrets.PACKAGES_RW_ACTOR }}
      PACKAGES_RW_TOKEN: ${{ secrets.PACKAGES_RW_TOKEN }}
```

```yaml
name: Release
on: [workflow_dispatch]

jobs:
  release:
    uses: Forsakringskassan/.github/.github/workflows/bundle-app-npm-release.yaml@main
    with:
      runtime-env: true      # must match ci.yaml
    secrets:
      PACKAGES_RW_ACTOR: ${{ secrets.PACKAGES_RW_ACTOR }}
      PACKAGES_RW_TOKEN: ${{ secrets.PACKAGES_RW_TOKEN }}
```

### npm library / tooling package

These release through a GitHub App and semantic-release rather than
`PACKAGES_RW_*`, so the permissions block matters.

```yaml
name: CI
on: [workflow_dispatch, push, pull_request]

permissions:
  contents: read

jobs:
  ci:
    uses: Forsakringskassan/.github/.github/workflows/bundle-npm-ci.yaml@main
    with:
      node-versions: '["22.x", "24.x"]'
      linter: fk-actions
      npm-pkg-lint-folders: packages/*
      npm-pkg-lint-allow-dependencies: eslint,vue
```

```yaml
name: Release
concurrency: release-${{ github.ref }}
on:
  push:
    branches: [main]

permissions:
  contents: write
  issues: write
  pull-requests: write
  id-token: write

jobs:
  release:
    uses: Forsakringskassan/.github/.github/workflows/bundle-npm-release.yaml@main
    with:
      app-id: ${{ vars.RELEASE_APP_ID }}
    secrets:
      app-key: ${{ secrets.RELEASE_APP_KEY }}
```

### Helm chart

```yaml
name: CI
on: [workflow_dispatch, push, pull_request]

jobs:
  ci:
    uses: Forsakringskassan/.github/.github/workflows/bundle-helm-ci.yaml@main
```

### Something the bundle does not cover

Add it as another job in the same file. This is the supported way to extend a
pipeline:

```yaml
jobs:
  ci:
    uses: Forsakringskassan/.github/.github/workflows/bundle-npm-ci.yaml@main
  cypress-e2e:
    runs-on: ubuntu-latest
    steps:
      # ...
```

---

## Where the organisation stands

Measured across all 149 non-archived repositories in the organisation.

| Situation | Repositories |
| --- | --- |
| Call a `bundle-*` workflow | 76 |
| Call internal workflows directly, never a bundle | 46 |
| Hand-written pipeline, no shared workflows | 7 |
| No workflows at all | 20 |

Bundle adoption per kind, today:

| Bundle | Callers |
| --- | --- |
| `bundle-gradle-ci` / `-release` | 29 / 30 |
| `bundle-maven-ci` / `-release` (deprecated aliases) | 28 / 28 |
| `bundle-app-npm-release` | 6 |
| `bundle-maven-quarkus-ci` / `-release` | 2 / 3 |
| `bundle-helm-ci` | 3 |
| `bundle-maven-lib-ci` / `-release` | 2 / 2 |
| `bundle-npm-ci` | 2 |
| `bundle-app-npm-ci` / `-ci-runtime-env` | 1 / 2 |
| `bundle-api-npm-ci` / `-release` | 1 / 1 |
| `bundle-npm-release` | 0 |

The 46 direct callers fall into exactly two groups, and both are mechanical to
fix.

### Group 1 — 26 Maven library repositories

`rimfrost-adapter-*`, `rimfrost-framework-*`, `rimfrost-*-subprocess`,
`rimfrost-process-asyncapi`, `rimfrost-referensdata-erbjudande`,
`rimfrost-ersattning-data`, `rimfrost-template-referensdata-erbjudande`,
`rimfrost-template-regel-subprocess`.

These already have files named `bundle-maven-lib-ci.yaml` and
`bundle-maven-lib-release.yaml` — but the files contain a *copy* of the bundle
body instead of a call to it. All 26 copies are byte-identical. They call
`maven-ci`, `pnr-scanner`, `generic-conventional-release`, `maven-release` and
`publish-release-on-tag-push` directly, which means every change to the
bundle's job graph has to be replayed 26 times by hand.

Replace both files with the standard two-file caller, naming
`bundle-maven-lib-ci` / `bundle-maven-lib-release`. The resulting pipeline is
identical — the shared bundle composes exactly the same jobs in the same order.

### Group 2 — 22 npm package repositories

`apimock-express`, `cloneman`, `commitlint-config`, `cypress-axe`,
`cypress-config`, `cypress-visual-regression`, `designsystem`,
`designsystem-user-lib`, `devindex-menu`, `docs-generator`,
`docs-live-example`, `eslint-config`, `get-application-slug`, `jest-config`,
`openapi-node-client-generator-cli`, `prettier-config`,
`sass-module-importer`, `stylelint-config`, `vite-lib-config`,
`vitest-config`, `vue-config`, `vue-lib-template`.

These have hand-written `build.yml` + `lint.yml` and call the internal
`npm-release.yaml` directly for the release. The jobs are near-identical
between repositories; they differ only in Node version, which linter form they
use, and the `npm-pkg-lint` arguments.

`bundle-npm-ci` now takes all of those as inputs, so `build.yml` and `lint.yml`
collapse into a single `ci.yaml`. `release.yml` becomes a call to
`bundle-npm-release` instead of `npm-release`.

Before migrating, check the repository against the two limits below.

### What cannot be migrated, and why

**`designsystem`** — the FKUI monorepo. Its build is genuinely specific: Lerna
scope-limited partial builds (`--include-dependencies --scope=@fkui/vue ...`),
a four-way Cypress component-test split, and an HTML-Validate job that
reinstalls a minimum peer version to test compatibility. Parameterising all of
that would push the bundle's complexity past the point where it is worth
sharing. It stays hand-written, and pulls in the shared pieces at step level
instead — `actions/pnr-scan` rather than a copy of the script.

**`eslint-config`, `prettier-config`** — these repositories *are* the shared
lint actions. Their own lint job runs `uses: ./` so that a change is tested
against itself before it is released. A bundle cannot express that without
hard-coding a self-reference. They can adopt `bundle-npm-release` for the
release half; the lint half stays local.

The same applies to `designsystem`, `designsystem-user-lib`, `docs-generator`
and `semantic-release-config`, whose documentation and release workflows call
`uses: ./.github/workflows/...` to chain their own local workflows. That is a
valid pattern next to a bundle — but the chained workflow has to stay local.

**`atlcli`** — Python. There is no bundle for that kind, and one repository
does not justify one.

**Forks (`github-ulf`, `fk-maven-ulf`, `rimfrost-service-folkbokforing-ulf`)** —
personal sandboxes. `github-ulf` is a fork of this repository containing a copy
of every workflow here; nothing outside it calls those copies.

### Repositories with no workflows at all

Four of the twenty have something to build and should get the two caller files
plus the `PACKAGES_RW_*` secrets:

| Repository | Bundle |
| --- | --- |
| `fk-datakarta` (Quarkus, `pom.xml`) | `bundle-maven-quarkus-*` |
| `fk-datakarta-konsoll` (Vite app) | `bundle-app-npm-*` |
| `rimfrost-datamodels` (Gradle, `build.gradle`) | `bundle-gradle-*` |
| `create-fkui-vue-minimal` (npm app) | `bundle-app-npm-*` |

`atlcli` is Python and has no bundle. The remaining fifteen hold documentation,
a licence, a `README.md` placeholder or nothing at all, and need no CI:
`allman_handling`, `create-fkui-vue`, `devutils`, `fkds-pnr`,
`fortigate_exporter`, `rdl-fke-registerutdrag`, `repository`,
`riktlinje-oppenkallkod`, `rimfrost`, `rimfrost-framework-bff`,
`rimfrost-regel-maskinell-subprocess`,
`rimfrost-regel-rtf-manuell-komplettering-fe`,
`rimfrost-regel-rtf-maskinell-bff`, `safos-jitsi`, `testrepo`.

### Hand-written pipelines that are fine as they are

`actions` and `dummy-action` are action repositories, `renovate-config` is
configuration only, `fkui-sandbox` is a sandbox, `fk-demo-app` is a demo, and
`jitsi-outlook` is an external open-source project with its own CodeQL,
Scorecard and dependency-review setup. None of them match a bundle kind.
