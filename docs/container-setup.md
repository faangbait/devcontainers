# Container Setup Decisions

## Shared post-create behavior

Node.js/npm and Python/pip are universal image tooling. Project dependency
installation remains conditional because not every workspace contains the
corresponding project files.

`src/.devcontainer/post-create.sh` is packaged in the base image and called by
every devcontainer profile. It currently:

- Prepares mounted agent configuration directories when agent configuration is
  enabled.
- Runs `npm install` when `package.json` exists at `PROJECT_ROOT`.
- Installs `requirements.txt`, `dev_requirements.txt`, or both when present at
  `PROJECT_ROOT`.
- Owns cache-volume targets to the runtime user and prepares tool-specific
  nested paths (see [Cache volumes](#cache-volumes)).

This replaces repeated inline lifecycle commands. The old Ansible installers
were composed from templates, so apparently stack-specific conditions may be
merged here as more source templates are reviewed.

The split between build and runtime is deliberate: shared CLI tools and
system-wide config are baked into the image as root at build time; anything
that must resolve against the runtime user's `$HOME` or the mounted workspace
(`package.json`, `requirements.txt`, `~/.npmrc`, ownership of freshly mounted
volumes) happens here.

## AWS boundaries

**Status: deferred.** AWS CLI installation and the SSO layer are blocked until
`devcontainers/features` PR [#1690](https://github.com/devcontainers/features/pull/1690)
lands — it adds RedHat/Alpine package-manager support to the `aws-cli` feature,
which is the path we will consume rather than hand-installing `awscli` via
`microdnf`. `AWS_PROFILE` is already wired per-variant in `containerEnv`; the
rest is not yet implemented. The placeholder note in
`src/.devcontainer/Containerfile` carries this same block.

AWS support is shared by every image variant, not owned by the Django stage.
Keep installation and configuration separate in `src/.devcontainer/Containerfile`:

- Install AWS CLI with stable base tooling before copying the shared
  post-create script.
- Add the more changeable SSO profiles and SSH configuration in a later layer.
- Store shared AWS configuration at `/etc/aws/config` and set
  `AWS_CONFIG_FILE=/etc/aws/config` in the image.
- Store the optional auto-login shell function at
  `/etc/profile.d/aws-sso-login.sh`.
- Store shared SSH hosts at `/etc/ssh/ssh_config.d/limitless.conf`.

This ordering is a build-cache boundary, not runtime sequencing. Copying
`post-create.sh` does not execute it. AWS CLI reads `AWS_PROFILE` natively;
post-create does not activate AWS or select an account.

Every devcontainer JSON defines this guard:

```json
{
  "containerEnv": {
    "AWS_PROFILE": ""
  }
}
```

The value is an empty string, not `null`. Some clients passed JSON `null`
through as the literal string `"null"`, which then shadowed the unset state
inside the shell. An empty string is a true unset. Account-specific consumers
override it with `account-one` or `account-two`. The shared AWS config must
contain named profiles only, with no `[default]` profile, so the empty value
leaves automatic account selection disabled. Explicit `--profile` arguments
remain valid.

Both accounts use the same SSO session, role, start URL, and region. Only the
account ID differs:

The AWS configuration should contain one named profile per account. Both
profiles reference the same SSO session because the role, start URL, and SSO
region are shared:

```ini
[profile account-one]
region = us-east-1
output = json
sso_session = limitless-sso
sso_account_id = 133652389253
sso_role_name = SuperAdmin

[profile account-two]
region = us-east-1
output = json
sso_session = limitless-sso
sso_account_id = ACCOUNT_ID
sso_role_name = SuperAdmin

[sso-session limitless-sso]
sso_start_url = https://d-9067ee3c43.awsapps.com/start/#
sso_region = us-east-1
sso_registration_scopes = sso:account:access
```

An account-specific consumer selects one profile:

```json
{
  "containerEnv": {
    "AWS_PROFILE": "account-one"
  }
}
```

Use `AWS_PROFILE`, not a custom account-ID variable. It is understood natively
by AWS CLI, the auto-login wrapper, and SSH `ProxyCommand` calls. The auto-login
wrapper must honor explicit `--profile` arguments and remain inactive when
neither `AWS_PROFILE` nor an explicit profile is present.

## VS Code extensions and settings

Default extensions and settings are baked into the images as an OCI image
label rather than repeated in every devcontainer JSON. The dev container spec
defines a `devcontainer.metadata` label whose value is a JSON string holding
the same `customizations` shape as `devcontainer.json`. Docker labels inherit
through `FROM`, so a label on the `base` stage reaches every downstream stage;
VS Code unions `extensions` arrays without duplicates and deep-merges
`settings` objects across all inherited labels, with the user's
`devcontainer.json` merged last. Net effect: a stage adds extensions or
settings without losing what its parents contributed, and a consuming project
can only ever extend, never clobber, the image defaults.

There must be only one `devcontainer.metadata` label per stage; Docker keeps
only the last when a key repeats, so edits extend the existing JSON rather
than adding a second label.

Current defaults:

- `base` (inherited by every variant): `EditorConfig.EditorConfig`,
  `timonwong.shellcheck`, `mikestead.dotenv`, `KevinRose.vsc-python-indent`.
- `agents` (adds): `ankurmathur.opencode-provider-bridge`.
- `rust` (adds): `vadimcn.vscode-lldb`.
- `python` (adds): `ms-python.debugpy`, plus settings
  (`python.testing.unittestArgs`, `pytestEnabled: false`,
  `unittestEnabled: true`, `python.defaultInterpreterPath`,
  `python.analysis.autoFormatStrings`).
- `django` (adds): `batisteo.vscode-django`, `junstyle.vscode-django-support`,
  plus analysis settings (`autoImportCompletions`, `diagnosticMode: workspace`,
  `typeCheckingMode: basic`).
- `devops` (adds): `4ops.terraform`, `redhat.vscode-yaml`.

The Python interpreter path is `/usr/local/bin/python`. That symlink to
`python3.14` is created in the `base` stage. Do not use the Microsoft
devcontainer-feature path `/usr/local/python/current/bin/python`; it does not
exist in this image, and pointing the extension at it leaves the interpreter
unresolved.

Launch configurations (`launch.json`) cannot ride this label: the spec defines
no `launch` property under `customizations.vscode`. See
[Deferred and intentionally skipped](#deferred-and-intentionally-skipped).

## Per-stage tooling

- `django`: `npm install -g sass` provides dart-sass, the official Sass
  compiler. This replaces sassc/libsass, which the Sass team deprecated in
  2020. The npm `sassc` package is not a substitute; it was unpublished in
  2021 and no longer exists on the registry.
- `typescript`: `npm install -g typescript tsx eslint` provides the `tsc`
  compiler, the `tsx` ESM runner, and the ESLint CLI. `ts-node` is not
  installed; `tsx` supersedes it.
- `devops`: the following binaries are pinned and installed from their
  upstream release sources:
  - `terraform` 1.15.8 from `releases.hashicorp.com`.
  - `kubectl` v1.36.2 from `dl.k8s.io`.
  - `ansible` via `pip` (no version pin; pip resolves the latest release
    compatible with `python3.14`).
  - `tflint` v0.64.0 from the `terraform-linters/tflint` GitHub releases.
  - `terraform-mcp-server` 1.1.0 from `releases.hashicorp.com`.
- `devops`: the `tf` alias (`alias tf=terraform`) is written to
  `/etc/profile.d/tf-alias.sh` at build time. `/etc/profile.d/*.sh` is sourced
  by `/etc/profile` (bash) and by `/etc/zshrc` (zsh), so the alias loads under
  both shells. It is not written to `~/.bash_aliases` (the devops variant
  defaults to zsh, which does not source that file) and not to `/etc/aliases`
  (the sendmail/Postfix mail-alias file, which no shell sources).

HashiCorp distributes `terraform` and `terraform-mcp-server` as zip only.
`ADD --unpack` only handles tar archives (per the Dockerfile reference), so
zip artifacts are `ADD`ed and then `unzip`ped in a `RUN` step. `unzip` ships
in the base image. Single-binary artifacts like `kubectl` and `yq` use a
direct `ADD --chmod=+x`.

## Cache volumes

Each language cache has three legs, and all three must be present or the cache
is dead weight: a volume mount, an environment variable pointing the tool at
the mount, and ownership of the freshly mounted (root-owned) directory handed
to the runtime user in `post-create.sh`. The earlier state had mounts without
the env vars or the chown, so the caches were unused.

- `python` and `django`: `devcontainer-cache-pip` at
  `/opt/devcontainer-cache/pip` (`PIP_CACHE_DIR`), `devcontainer-cache-uv` at
  `/opt/devcontainer-cache/uv` (`UV_CACHE_DIR`).
- `typescript`: `devcontainer-cache-npm` at `/opt/devcontainer-cache/npm`
  (`NPM_CONFIG_CACHE`), `devcontainer-cache-pnpm` at
  `/opt/devcontainer-cache/pnpm` (store location written to `~/.npmrc`).
- `rust`: `devcontainer-cache-cargo-registry` at `/usr/local/cargo/registry`,
  `devcontainer-cache-cargo-git` at `/usr/local/cargo/git`, and a per-project
  `devcontainer-cache-cargo-target-<basename>` at `<workspace>/target`.
  `CARGO_HOME` is set in the image; the volume mounts override the image
  directory permissions, so the chown is still required.
- `devops`: `devcontainer-cache-terraform` at
  `/opt/devcontainer-cache/terraform` (`TF_PLUGIN_CACHE_DIR`),
  `devcontainer-cache-ansible` at `/opt/devcontainer-cache/ansible`
  (`ANSIBLE_COLLECTIONS_PATH`, which also lists the system path
  `/usr/share/ansible/collections`).

`post-create.sh` chowns every mount target to the runtime user. Each path is
guarded by a `-d` test, so the shared script is a no-op for caches a variant
does not mount. Two paths need extra handling: the ansible volume gets a
nested `collections/` directory created inside it, and the pnpm volume gets
`store-dir=/opt/devcontainer-cache/pnpm` written idempotently to `~/.npmrc`.

## Stack-specific behavior

- Rust includes Python and pip because Python project files commonly accompany
  Rust workspaces; the shared post-create conditions handle those files.
- Do not install NVM; the image installs Node.js 24 and npm directly.
- Do not set the Chicago timezone.
- Do not write AWS or SSH configuration into an arbitrary user's home during
  image build.

The Context Mode Copilot hook belongs in the consuming project's
`.github/hooks/context-mode.json`; it is workspace configuration, not image
content.

## Deferred and intentionally skipped

These were considered and deliberately not done. They are recorded so the
reasoning survives and the next pass does not re-litigate them.

- **Missing launch configs.** Awaiting a good method for "inject this file into userland". Might move outside the container space entirely, so deferred. `.vscode/launch.json` 
```
vscode_launch_configurations:
    - name: "Python Debugger: Current File"
    type: debugpy
    request: launch
    program: "${file}"
    console: integratedTerminal
    - name: "Python Debugger: Attach"
    type: debugpy
    request: attach
    connect:
        host: localhost
        port: 5678  
  
  rust:
    vscode_launch_configurations:
      - name: "Attach"
        type: lldb
        request: attach
        pid: "${command:pickProcess}"
  ```

- **Missing AWS SSH configurations**
We have a handful of these we like in certain envs

(general)
 - printf 'Host *\n  User ec2-user\n  IdentityFile %s/.ssh/id_rsa\n  StrictHostKeyChecking no\n' "${containerWorkspaceFolder}" > ~/.ssh/config

(django)
- printf 'Host postgres\n  ProxyCommand nc $(aws ec2 describe-instances --filters Name=tag:Name,Values=postgres-db Name=instance-state-name,Values=running --query Reservations[0].Instances[0].PublicIpAddress --output text) 22\n\n' >> ~/.ssh/config

printf 'Host mkdir\n  ProxyCommand nc $(aws ec2 describe-instances --filters Name=tag:Name,Values=django-mkdirfoo Name=instance-state-name,Values=running --query Reservations[0].Instances[0].PublicIpAddress --output text) 22\n\n' >> ~/.ssh/config

printf 'Host shared\n  ProxyCommand nc $(aws ec2 describe-instances --filters Name=tag:Name,Values=django-shared Name=instance-state-name,Values=running --query Reservations[0].Instances[0].PublicIpAddress --output text) 22\n\n' >> ~/.ssh/config

printf 'Host mail\n  HostName 54.161.146.186\n\n' >> ~/.ssh/config

- **Global `@typescript-eslint`.** Not installed globally. ESLint resolves
  parser and plugin packages per-project from the local `node_modules`
  resolved upward from the config file, so a global copy is silently ignored
  by most project configs. Each project declares
  `@typescript-eslint/parser` and `@typescript-eslint/eslint-plugin` as
  devDependencies; `post-create.sh`'s existing `npm install` picks them up
  from `package.json`. --- similar to launch configs. We'd like it to be a
  standard devdependency, but maybe we're at the wrong surface. Deferred.

- **Unpinned `pip install django` in the image.** Removed. A named stage must
  not pin a fast-moving application framework at build time; the consuming
  project pins Django in `requirements.txt`, which `post-create.sh` installs.
  The stage provides the toolchain (sass, Python, extensions), not the app.

- **Node and Python caches on `base` and `agents`.** Not added. Caches are
  scoped to the variant's primary stack to avoid volume clutter; `base` and
  `agents` carry no language caches by design.

## Verification discipline

Package and URL claims made during setup were checked against their sources
before being committed to the build, after an early miss where a package was
assumed to exist on npm and turned out to have been unpublished. The standing
rule: before hardcoding a registry name, release URL, or "X ships as Y"
claim, fetch the registry entry, `HEAD` the exact artifact URL, or list the
release directory. Asserted-but-unverified facts are the dominant source of
silently broken image builds.


## cachy stuff
https://depot.dev/blog/ultimate-guide-to-docker-build-cache#cache-invalidation-for-add-and-copy-instructions

Python

- 76 — dnf install of python3.14-pip (installs pip itself)
- 165 — python3.14 -m pip install --no-cache-dir pipx
- 167 — python3.14 -m pipx install spec-kitty-cli --pip-args="--no-cache-dir"
- 168 — python3.14 -m pipx install code-review-graph --pip-args="--no-cache-dir"
- 246 — python3.14 -m pip install --no-cache-dir ansible

Node/TS package installers:

- 34 — symlink setup: ln -sf /usr/bin/npm-24 /usr/local/bin/npm
- 49 — npm install -g @anthropic-ai/claude-code opencode-ai bun
- 79 — dnf install nodejs24 nodejs24-npm chkconfig
- 120 — symlink again: ln -sf /usr/bin/npm-24 /usr/local/bin/npm
- 171 — npm install -g context-mode
- 172 — npx --yes opencode-openai-codex-auth@latest
- 173 — npx --yes @slkiser/opencode-quota init
- 177 — npm cache clean --force
- 202 — npm install -g sass && npm cache clean --force
- 230 — npm install -g typescript tsx eslint && npm cache clean --force

# Volumes

.devcontainer-devops (lines 29-30)
- devcontainer-cache-terraform → /opt/devcontainer-cache/terraform
- devcontainer-cache-ansible → /opt/devcontainer-cache/ansible

.devcontainer-rust (lines 27-29)
- devcontainer-cache-cargo-registry → /usr/local/cargo/registry
- devcontainer-cache-cargo-git → /usr/local/cargo/git
- devcontainer-cache-cargo-target-${localWorkspaceFolderBasename} → ${containerWorkspaceFolder}/target

.devcontainer-typescript (lines 28-29)
- devcontainer-cache-npm → /opt/devcontainer-cache/npm
- devcontainer-cache-pnpm → /opt/devcontainer-cache/pnpm

.devcontainer-python (lines 29-30)
.devcontainer-django (lines 30-31)
- devcontainer-cache-pip → /opt/devcontainer-cache/pip
- devcontainer-cache-uv → /opt/devcontainer-cache/uv

#
1. L2 ripgrep 15.2.0 → /mnt
2. L9 smart-tree install.sh → ./01_smart-tree
3. L10 https://chatgpt.com/codex/install.sh → ./02_codex
4. L29 rtk v0.43.0 → $INSTALL_DIR/
5. L187 yq (latest) → /usr/local/bin/yq
6. L221 rustup-init → /tmp/rustup-init
7. L236 terraform 1.15.8 → /tmp/terraform.zip
8. L242 kubectl v1.36.2 → /usr/local/bin/kubectl
9. L250 terraform-mcp-server 1.1.0 → /tmp/terraform-mcp-server.zip
10. L257 tflint v0.64.0 → /tmp/tflint.zip
