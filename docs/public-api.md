# Public API reference

Every `bundle-*` workflow in `.github/workflows/`. These are the only workflows
other repositories may call.

All of them are `workflow_call`-only and contain no build logic of their own —
they compose [internal workflows](internals.md). Inputs all have defaults
unless marked **required**.

---

## `bundle-maven-quarkus-ci`

Quarkus service built with Maven and shipped as a Docker image.

| Secret | |
| --- | --- |
| `PACKAGES_RW_ACTOR` | required |
| `PACKAGES_RW_TOKEN` | required |

Runs `maven-ci` (build, test, static analysis to code scanning) and
`pnr-scanner`. On `main`/`master` it also builds and pushes a `snapshot`
container image.

## `bundle-maven-quarkus-release`

Derives the next version from the conventional commits since the last tag. If
there is nothing to release it stops. Otherwise it tags, writes `CHANGELOG.md`,
builds and pushes `<version>` and `latest` images and publishes a GitHub
release.

| Secret | |
| --- | --- |
| `PACKAGES_RW_ACTOR` | required |
| `PACKAGES_RW_TOKEN` | required |

## `bundle-maven-ci` / `bundle-maven-release` — deprecated

Aliases that forward to the Quarkus bundles above. Point at
`bundle-maven-quarkus-*` instead; the aliases exist only so the repositories
still using them keep working.

---

## `bundle-maven-lib-ci`

Maven library published to GitHub Packages, no container image.

| Secret | |
| --- | --- |
| `PACKAGES_RW_ACTOR` | required |
| `PACKAGES_RW_TOKEN` | required |

Runs `maven-ci` and `pnr-scanner`.

## `bundle-maven-lib-release`

Conventional-commit version bump, `mvn deploy` to GitHub Packages, GitHub
release.

| Secret | |
| --- | --- |
| `PACKAGES_RW_ACTOR` | required |
| `PACKAGES_RW_TOKEN` | required |

---

## `bundle-gradle-ci`

Gradle library or API contract (openapi, asyncapi, plain jar).

| Secret | |
| --- | --- |
| `PACKAGES_RW_ACTOR` | required |
| `PACKAGES_RW_TOKEN` | required |

Runs `spotlessJavaCheck`, `gradle build`, static analysis to code scanning, and
`pnr-scanner`.

## `bundle-gradle-release`

`./gradlew updateVersion && ./gradlew release`, then publishes a GitHub release
from the pushed tag.

| Secret | |
| --- | --- |
| `PACKAGES_RW_ACTOR` | required |
| `PACKAGES_RW_TOKEN` | required |

---

## `bundle-api-npm-ci`

API contract built with Gradle and additionally published to npm.

| Secret | |
| --- | --- |
| `PACKAGES_RW_ACTOR` | required |
| `PACKAGES_RW_TOKEN` | required |

Runs the Gradle build, the npm build (`./gradlew processResources` then
`npm run build` and `npm pack`) and `pnr-scanner`.

## `bundle-api-npm-release`

Gradle release, GitHub release, and `npm publish --provenance`.

| Secret | |
| --- | --- |
| `PACKAGES_RW_ACTOR` | required |
| `PACKAGES_RW_TOKEN` | required |

---

## `bundle-app-npm-ci`

Web application built with npm and shipped as a Docker image.

| Input | Default | |
| --- | --- | --- |
| `runtime-env` | `false` | Ship a `runtime-config.js` placeholder and make the image usable under an arbitrary OpenShift UID |
| `node-versions` | `["24.x"]` | JSON array; the first entry is used for the container build |
| `build-command` | `npm run --if-present build` | |
| `test-command` | `npm run --if-present test` | |
| `registry` | `ghcr.io` | |

| Secret | |
| --- | --- |
| `PACKAGES_RW_ACTOR` | required |
| `PACKAGES_RW_TOKEN` | required |

Runs `npm ci`/build/test, `pnr-scanner`, and on `main`/`master` builds a
`snapshot` image and deploys the app to GitHub Pages.

## `bundle-app-npm-release`

| Input | Default | |
| --- | --- | --- |
| `runtime-env` | `false` | Must match the value used in the CI bundle |
| `node-version` | `24.x` | |
| `registry` | `ghcr.io` | |

| Secret | |
| --- | --- |
| `PACKAGES_RW_ACTOR` | required |
| `PACKAGES_RW_TOKEN` | required |

## `bundle-app-npm-ci-runtime-env` — deprecated

Forwards to `bundle-app-npm-ci` with `runtime-env: true`. Pass the input
instead.

---

## `bundle-npm-ci`

npm library or tooling package published to a registry.

| Input | Default | |
| --- | --- | --- |
| `node-versions` | `["24.x"]` | JSON array, becomes the build matrix |
| `build-command` | `npm run --if-present build` | |
| `test-command` | `npm run --if-present test` | |
| `linter` | `npm-scripts` | `npm-scripts` runs the `prettier:check` / `eslint` scripts from `package.json`; `fk-actions` runs the shared `Forsakringskassan/prettier-config` and `Forsakringskassan/eslint-config` actions, which do not require the scripts to exist |
| `npm-pkg-lint` | `true` | |
| `npm-pkg-lint-folders` | `.` | Space separated folders, e.g. `packages/*` |
| `npm-pkg-lint-allow-dependencies` | `""` | Comma separated |
| `npm-pkg-lint-build` | `build` | npm script run before packing, or `false` to skip |

No secrets.

Runs build/test across the matrix, lint, `npm-pkg-lint`, `pnr-scanner`, the
pull request documentation preview, and the tagged documentation deploy. The
documentation jobs skip themselves when the repository has no `build:docs`
script.

> `npm-scripts` mode skips Prettier and ESLint silently when the scripts are
> missing. Prefer `fk-actions` in repositories that use the shared configs.

## `bundle-npm-release`

| Input | Default | |
| --- | --- | --- |
| `app-id` | **required** | `${{ vars.RELEASE_APP_ID }}` |
| `config-preset` | — | semantic-release shareable config |
| `build-command` | `npm run --if-present build` | |
| `node-version` | `24.x` | |

| Secret | |
| --- | --- |
| `app-key` | required — `${{ secrets.RELEASE_APP_KEY }}` |

Runs semantic-release with the organisation's shared configuration and
publishes with npm provenance. Requires `permissions: contents: write,
issues: write, pull-requests: write, id-token: write` on the calling job.

---

## `bundle-helm-ci`

Helm chart.

| Input | Default | |
| --- | --- | --- |
| `helm-version` | `3.13.0` | |
| `chart-path` | `helm-chart` | |

No secrets. Runs `helm dependency build`, `helm lint` and `helm template`.

There is no release bundle for this kind: charts are applied from the cluster
repositories rather than published from CI.
