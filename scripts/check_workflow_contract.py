#!/usr/bin/env python3
"""Enforce the CI contract of this repository.

The workflows in ``.github/workflows`` are split into three tiers:

``bundle-*.yaml``
    The public API. Other repositories may only call these. A bundle composes
    internal workflows and must not contain build logic of its own.

``self-*.yaml``
    Automation for this repository only. Never reusable.

everything else
    Internal building blocks. Reusable, but only from inside this repository.

This script verifies those rules, that every intra-repository ``uses:``
reference resolves, and -- most importantly -- that the inputs and secrets a
caller passes actually match the interface the callee declares. That last
check is what catches a bundle drifting away from the building block it wraps.
"""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
WORKFLOWS = REPO / ".github" / "workflows"
ACTIONS = REPO / "actions"

WORKFLOW_PREFIX = "Forsakringskassan/.github/.github/workflows/"
ACTION_PREFIX = "Forsakringskassan/.github/actions/"

problems: list[str] = []


def fail(where: str, message: str) -> None:
    problems.append(f"{where}: {message}")


def load(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def triggers(doc: dict) -> dict:
    """Return the ``on:`` block. PyYAML parses the bare key ``on`` as True."""
    raw = doc.get("on", doc.get(True))
    if raw is None:
        return {}
    if isinstance(raw, str):
        return {raw: None}
    if isinstance(raw, list):
        return {name: None for name in raw}
    return raw


def call_spec(doc: dict) -> dict:
    spec = triggers(doc).get("workflow_call")
    return spec if isinstance(spec, dict) else {}


def declared(spec: dict, kind: str) -> dict:
    block = spec.get(kind)
    return block if isinstance(block, dict) else {}


def is_required(definition, kind: str) -> bool:
    """A callee input is required only when it has no default to fall back on."""
    if not isinstance(definition, dict):
        return False
    if not definition.get("required"):
        return False
    return kind == "secrets" or "default" not in definition


def check_interface(caller: Path, job_name: str, job: dict, callee_path: Path) -> None:
    where = f"{caller.name} -> job '{job_name}'"
    callee = load(callee_path)
    spec = call_spec(callee)
    if not spec and "workflow_call" not in triggers(callee):
        fail(where, f"{callee_path.name} is not callable (no workflow_call trigger)")
        return

    for kind, key in (("inputs", "with"), ("secrets", "secrets")):
        passed = job.get(key)
        if passed == "inherit":
            continue
        passed = passed if isinstance(passed, dict) else {}
        available = declared(spec, kind)

        for name in passed:
            if name not in available:
                fail(
                    where,
                    f"passes {kind[:-1]} '{name}' which {callee_path.name} "
                    f"does not declare",
                )

        for name, definition in available.items():
            if is_required(definition, kind) and name not in passed:
                fail(
                    where,
                    f"does not pass required {kind[:-1]} '{name}' of "
                    f"{callee_path.name}",
                )


def check_reference(caller: Path, job_name: str, job: dict) -> None:
    uses = job.get("uses")
    if not isinstance(uses, str) or not uses.startswith(WORKFLOW_PREFIX):
        return
    target = uses[len(WORKFLOW_PREFIX) :].split("@", 1)[0]
    callee_path = WORKFLOWS / target
    if not callee_path.is_file():
        fail(f"{caller.name} -> job '{job_name}'", f"calls missing workflow {target}")
        return
    if caller.name.startswith("bundle-") and not target.startswith("bundle-"):
        pass  # bundles wrapping internals is exactly the intended direction
    check_interface(caller, job_name, job, callee_path)


def check_action_references(path: Path, doc: dict) -> None:
    def walk(node) -> None:
        if isinstance(node, dict):
            uses = node.get("uses")
            if isinstance(uses, str) and uses.startswith(ACTION_PREFIX):
                name = uses[len(ACTION_PREFIX) :].split("@", 1)[0]
                if not (ACTIONS / name / "action.yml").is_file():
                    fail(path.name, f"uses missing composite action actions/{name}")
            for value in node.values():
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(doc)


def check_declaration(path: Path, doc: dict) -> None:
    """Guard two ways a workflow_call block silently becomes unloadable.

    GitHub rejects the whole file in both cases, and reports it as a run that
    fails after 0s with no job and no log -- easy to miss.
    """
    spec = call_spec(doc)
    for kind in ("inputs", "secrets"):
        for name, definition in declared(spec, kind).items():
            if not isinstance(definition, dict):
                continue
            description = definition.get("description")
            if isinstance(description, str) and "${{" in description:
                fail(
                    path.name,
                    f"{kind[:-1]} '{name}' has an expression in its "
                    f"description; GitHub evaluates those and rejects the file",
                )
            if kind == "inputs" and "type" not in definition:
                fail(path.name, f"input '{name}' is missing a type")


def check_tier(path: Path, doc: dict) -> None:
    name = path.name
    jobs = doc.get("jobs") or {}
    callable_ = "workflow_call" in triggers(doc)

    if name.startswith("bundle-"):
        if set(triggers(doc)) != {"workflow_call"}:
            fail(name, "a bundle must be triggered by workflow_call only")
        for job_name, job in jobs.items():
            if "steps" in job:
                fail(
                    name,
                    f"job '{job_name}' declares steps; a bundle must only compose "
                    f"internal workflows via uses:",
                )
        header = path.read_text(encoding="utf-8").split("name:", 1)[0]
        if "PUBLIC API" not in header:
            fail(name, "missing '# PUBLIC API.' header comment")
    elif name.startswith("self-"):
        if callable_:
            fail(name, "self-* workflows must not be reusable (drop workflow_call)")
    else:
        if not callable_:
            fail(
                name,
                "internal workflows must declare workflow_call, or be renamed "
                "self-* if they only run in this repository",
            )
        header = path.read_text(encoding="utf-8").split("name:", 1)[0]
        if "INTERNAL building block" not in header:
            fail(name, "missing '# INTERNAL building block' header comment")


def main() -> int:
    paths = sorted(
        p for p in WORKFLOWS.iterdir() if p.suffix in (".yaml", ".yml")
    )
    if not paths:
        print(f"No workflows found in {WORKFLOWS}", file=sys.stderr)
        return 1

    for path in paths:
        try:
            doc = load(path)
        except yaml.YAMLError as error:
            fail(path.name, f"is not valid YAML: {error}")
            continue

        check_tier(path, doc)
        check_declaration(path, doc)
        check_action_references(path, doc)
        for job_name, job in (doc.get("jobs") or {}).items():
            if isinstance(job, dict):
                check_reference(path, job_name, job)

    for action in sorted(ACTIONS.glob("*/action.yml")):
        try:
            load(action)
        except yaml.YAMLError as error:
            fail(str(action.relative_to(REPO)), f"is not valid YAML: {error}")

    print(f"Checked {len(paths)} workflows and "
          f"{len(list(ACTIONS.glob('*/action.yml')))} composite actions.")

    if problems:
        print("\nWorkflow contract violations:\n", file=sys.stderr)
        for problem in problems:
            print(f"  - {problem}", file=sys.stderr)
        print(
            "\nSee docs/internals.md for what the tiers mean.",
            file=sys.stderr,
        )
        return 1

    print("Workflow contract OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
