This template uses the prebuilt `faangbait/workspaces:django` image and adds
two agents as Dev Container Features from
[faangbait/dnf-features](https://github.com/faangbait/dnf-features):

- `ghcr.io/faangbait/dnf-features/claude:1`, with the official Anthropic
  marketplace and four of its plugins installed on container creation.
- `ghcr.io/faangbait/dnf-features/codex:1`, pinned to Codex `0.169.0`. Drop
  `agentVersion` to take the newest release at build time instead.

Swap either for `ghcr.io/faangbait/dnf-features/grok:1` or
`ghcr.io/faangbait/dnf-features/opencode:1`, or list all four.

Agent credentials, plugins, and history live on the `portable-agents` volume
at `/var/llms`, which every image except `base` mounts, so they survive
rebuilds.
