#!/bin/bash
#
# post-create.sh — backs `postCreateCommand` in every devcontainer variant.
# Fires ONCE per container creation (after onCreateCommand/updateContentCommand),
# NOT on every start or attach. Correct place for heavy work: project dep
# install (npm/pip), cache-volume ownership, codebase indexing.
#
set -euo pipefail

project_root="${PROJECT_ROOT:-$PWD}"

if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
  sudo mkdir -p /var/llms/claude /var/llms/codex /var/llms/opencode
  sudo chown -R "$(id -u):$(id -g)" /var/llms "$project_root/.claude"
fi

# Seed ~/.aws/config from the baked system default only when the user/project
# has not provided one. AWS reads ~/.aws/config by default (AWS_CONFIG_FILE is
# intentionally unset); a project overrides by writing its own.
if [ ! -f "$HOME/.aws/config" ] && [ -f /etc/aws/config ]; then
  mkdir -p "$HOME/.aws"
  cp /etc/aws/config "$HOME/.aws/config"
fi

if [ -f "$project_root/package.json" ]; then
  npm --prefix "$project_root" install
fi

set --
[ -f "$project_root/requirements.txt" ] && set -- "$@" -r "$project_root/requirements.txt"
[ -f "$project_root/dev_requirements.txt" ] && set -- "$@" -r "$project_root/dev_requirements.txt"
if [ "$#" -gt 0 ]; then
  python -m pip install "$@"
fi

# Cache volumes mount root-owned; chown to the runtime user so package writes
# succeed. Each dir is -d guarded so variants lacking a given mount skip it
# (post-create.sh is shared across all variants).
uid_gid="$(id -u):$(id -g)"
chown_if() { [ -d "$1" ] || return 0; sudo chown -R "$uid_gid" "$1"; }

chown_if /opt/devcontainer-cache/npm
chown_if /opt/devcontainer-cache/pip
chown_if /opt/devcontainer-cache/uv
chown_if /opt/devcontainer-cache/terraform
chown_if /usr/local/cargo/registry
chown_if /usr/local/cargo/git
chown_if "$project_root/target"

# ansible needs a nested collections dir created inside the volume root.
if [ -d /opt/devcontainer-cache/ansible ]; then
  sudo mkdir -p /opt/devcontainer-cache/ansible/collections
  sudo chown -R "$uid_gid" /opt/devcontainer-cache/ansible
fi

# pnpm: point ~/.npmrc at the mounted store so it persists, then own it.
if [ -d /opt/devcontainer-cache/pnpm ]; then
  touch "$HOME/.npmrc"
  grep -qxF 'store-dir=/opt/devcontainer-cache/pnpm' "$HOME/.npmrc" || \
    echo 'store-dir=/opt/devcontainer-cache/pnpm' >> "$HOME/.npmrc"
  sudo chown -R "$uid_gid" /opt/devcontainer-cache/pnpm
fi
