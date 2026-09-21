# Working in this repository

This is the shared CI environment for the Forsakringskassan organisation. Read
[README.md](README.md) first — it describes the pattern. This file is the short
version of the rules.

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
2. **Put steps in an action, not in a second workflow.** Reusable workflows
   calling reusable workflows is not the pattern here. `.github/workflows/`
   only contains bundles and `self-*`, and GitHub ignores subdirectories of it,
   so `.github/workflows/internal/` is not an option — files there never run.
3. **Reference actions as
   `Forsakringskassan/.github/actions/<name>@main`.** A relative
   `./actions/<name>` resolves against the _calling_ repository, not this one,
   and will fail there.
4. **Every step is an npm script run with `--if-present`.** The caller's
   `package.json` is the configuration. Prefer adding a script name over adding
   a workflow input.
5. **Bundles declare `type` and `description` on every input**, and never put
   a `${{ }}` expression in a description — GitHub evaluates descriptions and
   then rejects the whole file, showing up as a run that fails after 0s with no
   log.
6. **`run:` steps inside a composite action need `shell: bash`.**

## Before you finish

```sh
npm ci
npm run lint
```

`npm run lint` is prettier plus the structure check, and is exactly what
`self-lint.yaml` runs in CI. Fix what it reports; do not weaken the check to
make it pass.

## Changing behaviour for every repository

Roughly 130 repositories build on these workflows. A change to an action takes
effect immediately in all of them — callers pin the _bundle_, but the actions a
bundle uses always resolve at `@main`. Treat every change to `actions/` as a
change that ships to production without review in someone else's repository.
