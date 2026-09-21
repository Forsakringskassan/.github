#!/usr/bin/env node
/**
 * Enforces the structure described in README.md.
 *
 * The workflows in this repository are the CI environment for the whole
 * organisation, so a mistake here lands in every repository at once. This
 * script is the machine-readable version of the rules, and runs on every push.
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { parse } from "yaml";

const WORKFLOWS = ".github/workflows";
const ACTIONS = "actions";
const ACTION_PREFIX = "Forsakringskassan/.github/actions/";

const problems = [];

function fail(where, message) {
  problems.push(`${where}: ${message}`);
}

/** Walk every nested value of a parsed YAML document. */
function* walk(node) {
  if (Array.isArray(node)) {
    for (const value of node) yield* walk(value);
  } else if (node && typeof node === "object") {
    yield node;
    for (const value of Object.values(node)) yield* walk(value);
  }
}

/** The `on:` block. Some YAML versions read the bare key `on` as `true`. */
function onBlock(doc) {
  return doc?.on ?? doc?.true;
}

/** Normalise the `on:` block, which may be a string, a list or a mapping. */
function triggers(doc) {
  const on = onBlock(doc);
  if (typeof on === "string") return [on];
  if (Array.isArray(on)) return on;
  if (on && typeof on === "object") return Object.keys(on);
  return [];
}

function checkNoSubdirectories() {
  for (const entry of readdirSync(WORKFLOWS)) {
    if (!statSync(join(WORKFLOWS, entry)).isDirectory()) continue;
    fail(
      `${WORKFLOWS}/${entry}`,
      "GitHub ignores subdirectories of .github/workflows, so nothing in " +
        "here can run or be called. Put shared steps in actions/ instead.",
    );
  }
}

function checkWorkflow(file, doc, source) {
  const isBundle = file.startsWith("bundle-");
  const isSelf = file.startsWith("self-");
  const on = triggers(doc);

  if (!isBundle && !isSelf) {
    fail(
      file,
      "must be named bundle-*.yaml (public API, callable by other " +
        "repositories) or self-*.yaml (runs in this repository only)",
    );
  }

  if (isBundle) {
    if (on.length !== 1 || on[0] !== "workflow_call") {
      fail(file, `must be triggered by workflow_call only, got [${on}]`);
    }
    if (!source.split("name:")[0].includes("PUBLIC API")) {
      fail(file, "is missing the '# PUBLIC API' header comment");
    }
    const inputs = onBlock(doc)?.workflow_call?.inputs ?? {};
    for (const [name, input] of Object.entries(inputs)) {
      if (!input?.type) {
        fail(file, `input '${name}' is missing a type`);
      }
      if (!input?.description) {
        fail(file, `input '${name}' is missing a description`);
      }
      if (String(input?.description).includes("${{")) {
        // GitHub evaluates descriptions and then rejects the file, as a
        // run that fails after 0s with no job and no log.
        fail(file, `input '${name}' has an expression in its description`);
      }
    }
  }

  if (isSelf && on.includes("workflow_call")) {
    fail(file, "must not be reusable; rename it bundle-* if it is public API");
  }

  for (const node of walk(doc)) {
    const uses = node.uses;
    if (typeof uses !== "string") continue;
    if (uses.startsWith("./")) {
      fail(
        file,
        `uses '${uses}'; a relative path resolves against the calling ` +
          "repository, not this one. Use the full " +
          `${ACTION_PREFIX}<name>@main form.`,
      );
    }
    if (!uses.startsWith(ACTION_PREFIX)) continue;
    const [name, ref] = uses.slice(ACTION_PREFIX.length).split("@");
    if (!actionNames.has(name)) {
      fail(file, `uses missing action ${ACTIONS}/${name}`);
    }
    if (ref !== "main") {
      fail(file, `uses ${name}@${ref}; actions in this repository are @main`);
    }
  }
}

function checkAction(name, doc) {
  const where = `${ACTIONS}/${name}/action.yml`;
  if (!doc?.name) fail(where, "is missing a name");
  if (!doc?.description) fail(where, "is missing a description");
  if (doc?.runs?.using !== "composite") {
    fail(where, "must be a composite action (runs.using: composite)");
  }
  for (const [input, definition] of Object.entries(doc?.inputs ?? {})) {
    if (!definition?.description) {
      fail(where, `input '${input}' is missing a description`);
    }
  }
  for (const step of doc?.runs?.steps ?? []) {
    if (step?.run !== undefined && !step?.shell) {
      fail(where, `step '${step.name ?? step.run}' is missing a shell`);
    }
  }
}

const actionNames = new Set(
  readdirSync(ACTIONS).filter((name) =>
    statSync(join(ACTIONS, name)).isDirectory(),
  ),
);

checkNoSubdirectories();

const workflows = readdirSync(WORKFLOWS).filter((file) =>
  /\.ya?ml$/.test(file),
);
for (const file of workflows) {
  const source = readFileSync(join(WORKFLOWS, file), "utf8");
  try {
    checkWorkflow(file, parse(source), source);
  } catch (error) {
    fail(file, `is not valid YAML: ${error.message}`);
  }
}

for (const name of actionNames) {
  const path = join(ACTIONS, name, "action.yml");
  try {
    checkAction(name, parse(readFileSync(path, "utf8")));
  } catch (error) {
    fail(
      `${ACTIONS}/${name}/action.yml`,
      `is not valid YAML: ${error.message}`,
    );
  }
}

console.log(
  `Checked ${workflows.length} workflows and ${actionNames.size} actions.`,
);

if (problems.length > 0) {
  console.error("\nThese break the structure documented in README.md:\n");
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}

console.log("Structure OK.");
