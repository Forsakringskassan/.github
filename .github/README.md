# Forsakringskassan CI

Shared GitHub Actions workflows for the organisation. A repository gets its
build, test and release pipeline from here instead of maintaining its own.

## The pattern

Two layers, and nothing else:

| Layer                            | Lives in             | Who uses it                    |
| -------------------------------- | -------------------- | ------------------------------ |
| **Bundles** — reusable workflows | `.github/workflows/` | Any repository in the org      |
| **Actions** — composite actions  | `actions/`           | The bundles in this repository |

A bundle is a **public API**: it is what other repositories call, it is named
`bundle-<kind>-<ci|release>.yaml`, and changing its inputs or secrets breaks
every repository that calls it. An action is an implementation detail: it holds
the actual steps, and bundles compose them.

```
caller repo                    this repo
─────────────────────────────  ───────────────────────────────────────────
.github/workflows/             .github/workflows/
  npm-lib-ci.yaml ──────────►    bundle-npm-lib-ci.yaml      ← public API
                                   ├─► actions/npm-setup     ← implementation
                                   ├─► actions/npm-build
                                   └─► actions/npm-lint

  npm-lib-release.yaml ─────►    bundle-npm-lib-release.yaml ← public API
                                   ├─► actions/npm-setup
                                   └─► actions/npm-release
```

The caller workflow is named after the bundle it calls, so you can tell what
kind of repository it is from the filename.

### Why actions and not internal workflows

Shared steps go in `actions/`, never in a second layer of reusable workflows.

GitHub ignores subdirectories of `.github/workflows`, so there is no way to put
a workflow somewhere other repositories cannot reach it — anything in
`.github/workflows/` is either callable by the whole organisation or not
callable at all. `.github/workflows/internal/` does not work: files there never
run and cannot be called, not even from this repository.

Composite actions have no such problem, and they compose better: a bundle reads
as a list of steps instead of a tree of workflows calling workflows.

## Available bundles

| Kind of repository                   | CI bundle           | Release bundle           |
| ------------------------------------ | ------------------- | ------------------------ |
| npm library or CLI, published to npm | `bundle-npm-lib-ci` | `bundle-npm-lib-release` |

## Use it in your repository

Two files, copied as they are. The defaults are the point — a caller that
passes no inputs is a caller that keeps working when the defaults improve.

`.github/workflows/npm-lib-ci.yaml`

```yaml
name: CI

on: [push, pull_request]

permissions:
  contents: read

jobs:
  ci:
    uses: Forsakringskassan/.github/.github/workflows/bundle-npm-lib-ci.yaml@main
```

`.github/workflows/npm-lib-release.yaml`

```yaml
name: Release
concurrency: release-${{ github.ref }}

on: [workflow_dispatch]

permissions:
  contents: write
  issues: write
  pull-requests: write
  id-token: write

jobs:
  release:
    uses: Forsakringskassan/.github/.github/workflows/bundle-npm-lib-release.yaml@main
    secrets:
      app-key: ${{ secrets.RELEASE_APP_KEY }}
```

Releasing also needs the repository variable `RELEASE_APP_ID`, the client ID of
the GitHub App that authors the release commit. The bundle reads it itself —
`vars` in a called workflow resolves against the calling repository — so you
only pass the secret.

### What the npm bundles run

`bundle-npm-lib-ci` runs every step as `npm run --if-present <script>`, so
**your `package.json` is the configuration**. A script you do not have is a
step that does not run. Nothing to opt out of, nothing to pass.

| Job     | What it runs, in order                                                                |
| ------- | ------------------------------------------------------------------------------------- |
| `build` | `npm run build`, the tests, `npm run integration-test`                                |
| `lint`  | `npm run build`, prettier, eslint, `stylelint`, `html-validate`, npm-pkg-lint, `attw` |

Where the organisation already has an action, the bundle uses it rather than
its own steps:

| Step         | Action                                                                                                                                                                         |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Tests        | [`vitest-config`](https://github.com/Forsakringskassan/vitest-config) or [`jest-config`](https://github.com/Forsakringskassan/jest-config), chosen from your `devDependencies` |
| Prettier     | [`prettier-config`](https://github.com/Forsakringskassan/prettier-config)                                                                                                      |
| ESLint       | [`eslint-config`](https://github.com/Forsakringskassan/eslint-config)                                                                                                          |
| npm-pkg-lint | [`ext/npm-pkg-lint`](https://github.com/ext/npm-pkg-lint)                                                                                                                      |
| Release      | [`semantic-release-config`](https://github.com/Forsakringskassan/semantic-release-config)                                                                                      |

So the test job publishes its results as a check, and it drops `pretest` first
— a failing lint no longer stops the tests from running, because linting is a
separate job anyway. The remaining steps are plain npm scripts and run only if
you have them. Steps run in order and stop at the first failure.

`bundle-npm-lib-release` builds and then runs
[semantic-release](https://github.com/Forsakringskassan/semantic-release-config).

### Inputs

Both bundles work with no inputs at all. Override one only when the default is
genuinely wrong for your repository.

`bundle-npm-lib-ci`

| Input           | Default                               | Meaning                                      |
| --------------- | ------------------------------------- | -------------------------------------------- |
| `node-versions` | `["22.x", "24.x"]`                    | JSON array of Node.js versions to build with |
| `runs-on`       | `["ubuntu-latest", "windows-latest"]` | JSON array of runners to build on            |

`bundle-npm-lib-release`

| Input           | Default                      | Meaning                                 |
| --------------- | ---------------------------- | --------------------------------------- |
| `config-preset` | empty                        | semantic-release preset, empty = detect |
| `build-command` | `npm run --if-present build` | Build command run before releasing      |

Secret: `app-key`, required. Variable: `RELEASE_APP_ID`, required for release.

### Pinning

Pin to a commit SHA with a `# main` comment, which is what Renovate maintains
for you:

```yaml
uses: Forsakringskassan/.github/.github/workflows/bundle-npm-lib-ci.yaml@<sha> # main
```

**A pinned bundle is reproducible.** Everything a bundle reaches for is itself
pinned to a SHA, including the actions in this repository — that is why the
bundles say `actions/npm-setup@<sha> # main` and not `@main`. `uses:` cannot
take an expression, so a bundle has no way to pass its own ref down to an
action; pinning each one by hand is what closes that hole. Renovate keeps every
pin, here and in your repository, up to date.

A plain `@main` also works if you would rather always have the latest.

### Something the bundle does not cover

Add an extra job next to the `uses:` job in your own workflow. If several
repositories of the same kind need it, it belongs in the bundle instead — open
a pull request here.

Never call an `actions/` action from your own repository. They are
implementation details and change without notice.

## Working on this repository

```sh
npm ci
npm run lint          # prettier + structure check
npm run prettier:write
```

`self-lint.yaml` runs the same checks on every push. The structure check is
[`scripts/check-workflows.mjs`](../scripts/check-workflows.mjs) and enforces:

- every workflow is `bundle-*.yaml` (public API) or `self-*.yaml` (this
  repository only), and nothing else
- a bundle is `workflow_call`-only, carries a `# PUBLIC API` header comment,
  and gives every input a `type` and a `description`
- a `self-*` workflow is not reusable
- every `uses:` is pinned to a 40-character commit SHA and carries a
  `# <ref>` comment saying what that SHA is, so a pinned bundle builds the same
  way tomorrow
- every `Forsakringskassan/.github/actions/<name>` reference resolves — a
  relative `./actions/...` would resolve against the _calling_ repository, so
  it is rejected
- every action is a composite action with a description, and every `run:` step
  in it declares a `shell:`
- there are no subdirectories under `.github/workflows/`

### Adding a bundle for a new kind of repository

1. Add the steps to a composite action under `actions/<name>/action.yml`, or
   reuse the ones that exist.
2. Add `.github/workflows/bundle-<kind>-ci.yaml` and
   `bundle-<kind>-release.yaml` that compose those actions. Start from
   `bundle-npm-lib-ci.yaml`.
3. Give every input a default that suits the common case, so callers can pass
   nothing.
4. Add the bundle to the table above, and run `npm run lint`.

Changing an action takes two steps, because the bundles pin it: merge the
change to the action, then bump the SHA in the bundles that use it. Renovate
opens that second pull request on its own, or you can do it by hand.

Guidance for agents is in [AGENTS.md](../AGENTS.md).
