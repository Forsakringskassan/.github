#!/usr/bin/env node
/**
 * Rewrites every reference to this repository's own actions to a version.
 *
 * The bundles pin the actions they compose, so that a caller pinning a bundle
 * gets the same build tomorrow. Pinning them to a commit SHA does not work:
 * the SHA of the commit is not known while writing the commit, and Renovate
 * would chase its own tail, since every update it pushes moves `main` and
 * makes the pin stale again. A version tag has neither problem — you know the
 * next version in advance, and it stops moving once it is created.
 *
 *   npm run pin -- v1.0.1
 *   git commit -am "chore: release v1.0.1"
 *   git tag v1.0.1 && git push --follow-tags
 */
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const WORKFLOWS = ".github/workflows";
const PREFIX = "Forsakringskassan/.github/actions/";

const version = process.argv[2];
if (!/^v\d+\.\d+\.\d+$/.test(version ?? "")) {
  console.error("Usage: npm run pin -- v1.0.1");
  process.exit(1);
}

let changed = 0;
for (const file of readdirSync(WORKFLOWS).filter((f) => /\.ya?ml$/.test(f))) {
  const path = join(WORKFLOWS, file);
  const before = readFileSync(path, "utf8");
  const after = before.replace(
    new RegExp(`(${PREFIX}[a-z0-9-]+)@\\S+[^\\n]*`, "g"),
    `$1@${version}`,
  );
  if (after === before) continue;
  writeFileSync(path, after);
  console.log(`${path} -> ${version}`);
  changed += 1;
}

console.log(changed === 0 ? "Nothing to pin." : `Pinned ${changed} workflows.`);
