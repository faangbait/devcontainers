#!/usr/bin/env python3
"""Compose inherited devcontainer JSONC files into one standard JSON file."""

import copy
import json
import sys
from pathlib import Path


def parse_jsonc(path):
    text = path.read_text()
    output = []
    i = 0
    quoted = escaped = line_comment = block_comment = False
    while i < len(text):
        char = text[i]
        following = text[i + 1] if i + 1 < len(text) else ""
        if line_comment:
            if char == "\n":
                line_comment = False
                output.append(char)
        elif block_comment:
            if char == "*" and following == "/":
                block_comment = False
                i += 1
            elif char == "\n":
                output.append(char)
        elif quoted:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
        elif char == '"':
            quoted = True
            output.append(char)
        elif char == "/" and following == "/":
            line_comment = True
            i += 1
        elif char == "/" and following == "*":
            block_comment = True
            i += 1
        else:
            output.append(char)
        i += 1

    cleaned = "".join(output)
    output = []
    quoted = escaped = False
    for i, char in enumerate(cleaned):
        if quoted:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                quoted = False
        elif char == '"':
            quoted = True
            output.append(char)
        elif char == "," and cleaned[i + 1 :].lstrip().startswith(("}", "]")):
            continue
        else:
            output.append(char)
    return json.loads("".join(output))


def merge(parent, child):
    if isinstance(parent, dict) and isinstance(child, dict):
        result = copy.deepcopy(parent)
        for key, value in child.items():
            result[key] = merge(result[key], value) if key in result else copy.deepcopy(value)
        return result
    if isinstance(parent, list) and isinstance(child, list):
        return copy.deepcopy(parent + child)
    return copy.deepcopy(child)


def remove_path(value, path):
    parts = path.removeprefix(".").split(".")
    if not path.startswith(".") or not all(parts):
        raise ValueError(f"invalid non-inheritable path: {path!r}")
    parent = value
    for part in parts[:-1]:
        if not isinstance(parent, dict) or part not in parent:
            return
        parent = parent[part]
    if isinstance(parent, dict):
        parent.pop(parts[-1], None)


def linearize(graph, target):
    order = []
    visited = set()
    active = []

    def visit(layer):
        if layer in active:
            cycle = " -> ".join(active[active.index(layer) :] + [layer])
            raise ValueError(f"configuration inheritance cycle: {cycle}")
        if layer in visited:
            return
        if layer not in graph:
            raise ValueError(f"unknown configuration layer: {layer}")
        active.append(layer)
        for parent in graph[layer]:
            visit(parent)
        active.pop()
        visited.add(layer)
        order.append(layer)

    visit(target)
    return order


def config_path(root, layer):
    directory = root / layer
    for name in ("devcontainer.json", ".devcontainer.json"):
        path = directory / name
        if path.is_file():
            return path
    raise ValueError(f"no devcontainer JSON found for layer {layer}")


def compose(manifest_path, leaf_path):
    manifest = parse_jsonc(manifest_path)
    graph = manifest["inheritance"]
    blocked = manifest.get("nonInheritable", [])
    root = manifest_path.parent
    target = leaf_path.resolve().parent.relative_to(root.resolve()).as_posix()
    order = linearize(graph, target)
    result = {}
    for layer in order:
        for path in blocked:
            remove_path(result, path)
        result = merge(result, parse_jsonc(config_path(root, layer)))
    return order, result


def self_test():
    assert merge({"a": {"x": 1}, "b": [1], "s": "old"}, {"a": {"y": 2}, "b": [2], "s": "new"}) == {
        "a": {"x": 1, "y": 2}, "b": [1, 2], "s": "new"
    }
    value = {"containerEnv": {"keep": "yes", "secret": "no"}}
    remove_path(value, ".containerEnv.secret")
    assert value == {"containerEnv": {"keep": "yes"}}
    value = merge(value, {"containerEnv": {"secret": "child"}})
    assert value["containerEnv"]["secret"] == "child"
    remove_path(value, ".containerEnv.secret")
    assert "secret" not in value["containerEnv"]
    assert linearize({"base": [], "agents": ["base"], "python": ["agents"], "django": ["python"]}, "django") == [
        "base", "agents", "python", "django"
    ]


def main():
    if sys.argv[1:] == ["--self-test"]:
        self_test()
        return
    if len(sys.argv) != 4:
        raise SystemExit(f"usage: {sys.argv[0]} MANIFEST LEAF_CONFIG OUTPUT")
    manifest, leaf, output = map(Path, sys.argv[1:])
    order, config = compose(manifest, leaf)
    print("configuration MRO: " + " -> ".join(order), file=sys.stderr)
    output.write_text(json.dumps(config, indent=4) + "\n")


if __name__ == "__main__":
    main()
