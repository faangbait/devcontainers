# Volume Migration Plan
This project is migrating from legacy Ansible-generated Dev Containers to independently maintained, modular container images and configurations under images/base-ubi.

1. Update `.devcontainer-agents/devcontainer.json`.
   - Keep `portable-agents`.
   - Attach the critical configuration volumes without reading or altering their contents:
     - `claude-code-config` at `/root/claude-code-config`
     - `opencode-config` at `/root/opencode-config`
     - `codex-config` at `/root/codex-config`
     - `agents-config` at `/root/agents-config`

2. Update `.devcontainer-python/devcontainer.json`.
   - Attach `devcontainer-cache-pip` at `/opt/devcontainer-cache/pip`.
   - Attach `devcontainer-cache-uv` at `/opt/devcontainer-cache/uv`.

3. Add empty `rust`, `typescript`, and `devops` Containerfile stages inheriting from `agents`.
   - Do not add language packages or other build steps.

4. Add `.devcontainer-rust/devcontainer.json` targeting the `rust` stage.
   - Attach `devcontainer-cache-cargo-registry` at `/usr/local/cargo/registry`.
   - Attach `devcontainer-cache-cargo-git` at `/usr/local/cargo/git`.
   - Attach `devcontainer-cache-cargo-target-${localWorkspaceFolderBasename}` at `${containerWorkspaceFolder}/target`.

5. Add `.devcontainer-typescript/devcontainer.json` targeting the `typescript` stage.
   - Attach `devcontainer-cache-npm` at `/opt/devcontainer-cache/npm`.
   - Attach `devcontainer-cache-pnpm` at `/opt/devcontainer-cache/pnpm`.

6. Add `.devcontainer-devops/devcontainer.json` targeting the `devops` stage.
   - Attach `devcontainer-cache-terraform` at `/opt/devcontainer-cache/terraform`.
   - Attach `devcontainer-cache-ansible` at `/opt/devcontainer-cache/ansible`.

7. Update `.devcontainer-django/devcontainer.json`.
   - Attach `limitless-build` at `${containerWorkspaceFolder}/build`.

8. Register `rust`, `typescript`, and `devops` in `images/base-ubi/Makefile`.

This migration only attaches volumes. It does not add cache environment variables, ownership changes, directory initialization, symlinks, or lifecycle behavior. Mounted-volume contents must not be read, moved, deleted, or altered. Shell-history storage is deferred because it is not a language cache.
