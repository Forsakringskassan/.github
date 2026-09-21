# Working in this repository

This is the shared CI environment for the Forsakringskassan organisation. Read
[.github/README.md](.github/README.md) first — it describes the pattern. This
file is the short version of the rules.

## Layout

```
.github/workflows/bundle-*.yaml   public API, called by other repositories
.github/workflows/self-*.yaml     runs in this repository only
actions/<name>/action.yml         composite actions, the implementation
scripts/check-workflows.mjs       enforces everything below
```

## Rules

1. **A bundle is a public API.** Other repositories call it. Removing or
   renaming an input, a secret or a job breaks them. Add inputs with a default
   instead; if a breaking change is unavoidable, say so in the commit message
   with a `breaking:` prefix.
2. **Give every input a default that suits the common case**, so callers can
   pass nothing. A caller that passes no inputs is a caller that keeps working
   when the defaults improve. Prefer a new default over a new input.
3. **Reuse the organisation's actions.** `prettier-config`, `eslint-config`,
   `vitest-config`, `jest-config` and `semantic-release-config` already exist
   and already handle detection and reporting. Check for one before writing
   steps by hand.
4. **Pin every `uses:` to a commit SHA with a `# <ref>` comment**, including
   the actions in this repository. A caller that pins a bundle expects the same
   build tomorrow, and `uses:` cannot take an expression, so a bundle cannot
   pass its own ref down to the actions it composes. Pinning by hand is what
   makes it reproducible. Renovate maintains the pins.
5. **Changing an action takes two commits**, because of rule 4: change the
   action, then bump the SHA in the bundles that use it.
6. **Put steps in an action, not in a second workflow.** Reusable workflows
   calling reusable workflows is not the pattern here. `.github/workflows/`
   only contains bundles and `self-*`, and GitHub ignores subdirectories of it,
   so `.github/workflows/internal/` is not an option — files there never run.
7. **Never use a relative `./actions/<name>`.** It resolves against the
   _calling_ repository, not this one, and will fail there.
8. **The caller's `package.json` is the configuration.** Steps are npm scripts
   run with `--if-present`. Prefer relying on a script name over adding a
   workflow input.
9. **Bundles declare `type` and `description` on every input**, and never put
   a `${{ }}` expression in a description — GitHub evaluates descriptions and
   then rejects the whole file, showing up as a run that fails after 0s with no
   log.
10. **`run:` steps inside a composite action need `shell: bash`.**

## Before you finish

```sh
npm ci
npm run lint
```

`npm run lint` is prettier plus the structure check, and is exactly what
`self-lint.yaml` runs in CI. Fix what it reports; do not weaken the check to
make it pass.

## Changing behaviour for every repository

Roughly 130 repositories build on these workflows. Treat every change here as a
change that ships to someone else's repository.
