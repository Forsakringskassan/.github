# Internals

Everything below the `bundle-*` line. Other repositories must not call any of
it directly: these files change whenever a bundle needs them to.

## Layers

**Bundles** (`bundle-*.yaml`) know *what a kind of repository needs*: which
jobs run, in which order, under which conditions. They contain no `steps:` —
the contract checker rejects a bundle that does.

**Internal workflows** (everything else in `.github/workflows/`) know *how one
job is done*. One workflow, one job, one concern. They are the unit of reuse
between bundles — `maven-ci.yaml` is shared by the Quarkus bundle and the
library bundle, `pnr-scanner.yaml` by almost all of them.

**Composite actions** (`actions/<name>/action.yml`) know *how one step is
done*. They exist because several internal workflows need the same steps, and
because steps — unlike workflows — can be dropped into a job a repository
already has.

**Self workflows** (`self-*.yaml`) are not reusable at all. They run in this
repository.

## Internal workflows

| Workflow | Used by |
| --- | --- |
| `maven-ci.yaml` | `bundle-maven-quarkus-ci`, `bundle-maven-lib-ci` |
| `maven-release.yaml` | `bundle-maven-lib-release` |
| `app-maven-docker-quarkus.yaml` | `bundle-maven-quarkus-ci`, `bundle-maven-quarkus-release` |
| `gradle-ci.yaml` | `bundle-gradle-ci`, `bundle-api-npm-ci` |
| `gradle-release.yaml` | `bundle-gradle-release`, `bundle-api-npm-release` |
| `npm-ci.yaml` | `bundle-npm-ci`, `bundle-app-npm-ci` |
| `npm-lint.yaml` | `bundle-npm-ci` |
| `npm-pkg-lint.yaml` | `bundle-npm-ci` |
| `npm-release.yaml` | `bundle-npm-release` |
| `npm-ghpages-app.yaml` | `bundle-app-npm-ci`, `bundle-app-npm-release` |
| `npm-ghpages-docs.yaml` | `bundle-npm-ci`, `bundle-npm-release` |
| `npm-pr-preview.yaml` | `bundle-npm-ci` |
| `app-npm-docker.yaml` | `bundle-app-npm-ci`, `bundle-app-npm-release` |
| `api-npm-ci.yaml` | `bundle-api-npm-ci` |
| `api-npm-release.yaml` | `bundle-api-npm-release` |
| `helm-ci.yaml` | `bundle-helm-ci` |
| `generic-conventional-release.yaml` | every release bundle that is not Gradle-driven |
| `publish-release-on-tag-push.yaml` | every release bundle |
| `pnr-scanner.yaml` | every CI bundle |

## Composite actions

| Action | Does |
| --- | --- |
| `actions/maven-settings` | Writes `settings.xml` for the `github--Forsakringskassan--repository` server and exports its path as `$MAVEN_SETTINGS`. The credentials stay in `MAVEN_USERNAME` / `MAVEN_PASSWORD` environment variables and are never written to disk, so the calling job must set them. |
| `actions/docker-build-push` | Builds one image per architecture, pushes them and assembles the multi-arch manifests. Always produces `snapshot`; with `release: true` also `<version>` and `latest`. |
| `actions/violations-to-sarif` | Converts Checkstyle/PMD/SpotBugs/JUnit reports to SARIF and uploads them to code scanning. Takes `build-tool: maven` or `gradle`. |
| `actions/pnr-scan` | Fails the build on anything that looks like a personnummer. Use this when you need the check as a step inside an existing job; use `pnr-scanner.yaml` when you want it as its own job. |

## Rules for changing things

**A change to an internal workflow reaches every repository at `@main` on the
next run.** There is no staging. Treat the internal layer as production.

1. *Never* change a bundle's input or secret names without a deprecation path.
   Repositories pin by name, not by version.
2. When an internal workflow's interface changes, the bundles that call it must
   change in the same commit. The contract checker enforces this — it exists
   because exactly this drift silently broke `bundle-npm-release` once.
3. New behaviour goes in behind an input with a default that preserves what
   happens today.
4. Prefer a composite action over a new internal workflow when the logic is
   steps rather than a job. Actions can be reused inside a repository's own
   jobs; reusable workflows cannot.

### Referencing a composite action from an internal workflow

Use the full path:

```yaml
- uses: Forsakringskassan/.github/actions/maven-settings@main
```

A relative `./actions/...` will not work. When a reusable workflow runs, the
checked out repository is the *caller's*, not this one.

This also means a repository that pins a workflow to a SHA still picks up
composite actions from `main`. Keep composite actions backwards compatible.

## The contract checker

`scripts/check_workflow_contract.py` runs on every push and verifies:

- every workflow parses as YAML;
- `bundle-*` files are `workflow_call`-only, carry a `# PUBLIC API.` header and
  declare no `steps:`;
- internal workflows are callable and carry an `# INTERNAL building block`
  header;
- `self-*` files are not callable;
- every `Forsakringskassan/.github/...` reference resolves to a file that
  exists;
- **every input and secret passed to an internal workflow is declared by it,
  and every required one is passed;**
- every declared input has a `type`, and no input or secret description
  contains a `${{ ... }}` expression.

The last two look pedantic but are the two ways a `workflow_call` block becomes
unloadable. GitHub rejects the whole file and reports it as a run that fails
after 0s with no job and no log, which is easy to miss — both have happened
here.

Run it locally with `python3 scripts/check_workflow_contract.py` (needs
PyYAML).
