---
name: docker-cleanup
description: Reclaim disk space used by Docker on a development machine - build cache, stopped containers (especially VS Code Dev Containers), volumes and images - using tested cut-point rules that decide in bulk what is safe to remove and what needs review. Use this skill whenever the user wants to free Docker disk space, asks what is eating space under /var/lib/docker, says the disk is full or low on a machine that runs Docker or devcontainers, asks which containers, volumes or images are safe to delete, or mentions docker prune, docker system df, dangling images or old devcontainers - even if they only ask "what can I delete?" and never say "cleanup". Use it before running any docker prune or rm command for space reasons.
---

# Docker disk cleanup

Reclaim Docker disk space on a development machine by sorting everything into classes with known rules, so the user reviews short lists and exceptions and not every item one by one.

**Status: pre-production.** The rules below are a record of what was safe in earlier cleanups, not guarantees. Treat every rule as a proposal. Nothing is deleted until the user has seen exactly what will go and said yes.

## Why confirmation is not optional

Most of what Docker holds is rebuildable, and a small part is not: a database in an ad hoc container, unpushed commits in a config volume, per-project agent state that exists nowhere else. From the outside the two look alike. The rules catch the known cases, and the user catches the rest, which only works if they see the list before it is gone. So:

- Show the exact items (name, class, size, what is lost) before each batch and wait for a clear yes. A yes covers that batch only. Approval for old containers is not approval for volumes.
- A general instruction such as "clean up Docker" or "free as much as you can" is a request to run this process, not consent to delete. Present the plan first.
- Remove by explicit name or ID from the approved list. Avoid the broad `prune` forms noted below, because they select by different criteria than the tables and take Keep items with them.
- "Usually safe" means approve as a group. "Review" means the user decides per item, after you have looked inside. "Keep" and "Always keep" are not offered for deletion at all; if the user asks to remove one, say what depends on it first.

## Check the environment first

The rules were tested in one environment:

- Fedora Linux, Docker with the `overlay2` driver, data root `/var/lib/docker`. That directory needs root, so `du` on it fails; use Docker's own accounting (`docker system df -v`, `docker inspect --size`).
- Containers are almost all VS Code Dev Containers: images named `vsc-<project>-<hash>-uid` or `...-features-uid`, containers with random names such as `eloquent_germain`.
- Each devcontainer bind-mounts its workspace from the host (`~/dev/<project>` to `/workspaces/<project>`). Source code lives on the host. The writable layer holds only what was installed or written outside the mounts.
- The label `devcontainer.local_folder` maps a container to its project. Containers without it come from ad hoc `docker run`.
- Shared named volumes are mounted into many devcontainers: the VS Code server, agent config and state, per-language caches.

If the machine differs (other driver, Docker Desktop, compose stacks, databases in containers, no devcontainer labels), say so and lean toward Review: the "safe" classes assume code lives on the host, which may not hold there.

## Workflow

1. **Survey.** Run the bundled script. It is read-only and classifies every container, volume and image against the tables below:

   ```
   scripts/survey.sh                 # all sections
   scripts/survey.sh containers      # one section: summary | containers | volumes | images
   ```

   Its classes are a first pass from names, dates and sizes. It cannot see inside anything, so every Review class still needs the checks described in its cut point.

2. **Rank and plan.** From the summary, tell the user how much space each category holds and how much is realistically reclaimable, then give the plan in cut-point order. If one category dominates, say so; a cleanup that needs 5 GB may stop after cut point 1.

3. **Work the cut points in order: 1 build cache, 2 containers, 3 volumes, 4 images.** The order matters because each step unlocks the next: removing containers releases the volumes and images they reference. Rerun the relevant survey section after each step, since classes change (an in-use image becomes a candidate once its container is gone).

   For each cut point: list the candidates by class, do the look-inside checks for Review items, propose, get the yes, remove by name, report what was freed.

4. **Confirm the result.** Run `df -h /` and `docker system df` again and report before and after.

5. **Report what did not fit.** List items that landed in Unclassified or surprised you, and suggest a rule for each. The point of this skill is that the next cleanup needs less review, so new patterns are worth capturing. Offer to add them to this file; do not edit it unasked.

### Presenting a batch

Use a table per cut point, grouped by class, so the user can approve a group at a glance:

```
Cut point 2: stopped containers

Proposed for removal (old devcontainer, stopped > 30 days, layer < 10 GB), 6 containers, ~8.2 GB:
| Container | Project | Stopped | Layer |
...
Lost: packages and files written inside these containers. Code is on the host. VS Code rebuilds each on next open.

Needs your decision (review):
| Container | Why | What I found |
...

Keeping: 2 running, 4 stopped within 7 days.

Remove the 6 listed? (yes / no / pick)
```

## Cut points

### 1. Build cache: delete all of it

Often the largest single item and the safest. Nothing is lost except rebuild time.

```
docker buildx du                                  # size the cache first
docker builder prune -a -f                        # everything (-f skips Docker's prompt, so ask the user first)
docker builder prune -a -f --filter until=720h    # only entries unused for 30 days or more
```

**Nested Docker volumes and the containers that hold them.** A devcontainer that runs a nested Docker daemon keeps that daemon's data root in a named volume. Known case: the `dev/devcontainer` project, with a `secure-containers-data-*` volume mounted at `/var/lib/secure-containers` (36.7 GB when measured, mostly a `containerd/` store). That is build cache by another name and can usually go with the builder cache.

- Docker refuses to remove a volume while any container references it, stopped or not. Find the holders with `docker ps -a --filter volume=<volume>`, remove them first, then the volume. Ask permission per container here, by name. These are the only containers removed in this step; all others wait for cut point 2.
- VS Code rebuilds the container the next time the project is opened, and the inner daemon starts with an empty store.
- The cost is re-pulling or rebuilding those images. Check first that no image exists only in that store, because a locally built one would need rebuilding from its Dockerfile.

### 2. Stopped devcontainers: delete the old ones

Removing a devcontainer leaves the code alone, because the workspace is bind-mounted from the host. The loss is anything installed or written inside the container: apt packages, global tool installs, shell history, files in the home directory. VS Code recreates the container when the project is next opened.

Match each container against the rows from the top. The first row that matches decides.

| Pattern | Class | Rule | Notes |
|---|---|---|---|
| State `running` | Running | Keep | Not a candidate. |
| Labeled, exited within the last 7 days | Recently stopped | Usually keep | Low payoff and more likely to be active. Review one at a time. |
| Writable layer of 10 GB or more | Large writable layer | **Review first** | Look with `docker diff <container>`. A layer that size usually holds build output or data written outside the mounts, and may hold something worth keeping. Applies to every container not matched above, whatever its age. |
| Labeled, exited 7 to 30 days ago | Stopped 1-4 weeks ago | Review the list | Skim by project and remove the ones no longer worked on. |
| No `devcontainer.local_folder` label, or state `Created` (never started) | Ad hoc `docker run` or never started | Usually safe to remove | Never-started containers have nothing to lose. A used ad hoc container can hold data (a database, for example), so check it first. Most free almost nothing. |
| Labeled, exited more than 30 days ago | Old devcontainer | Usually safe to remove | Remove as a group once the list is approved. |

Remove with `docker rm <name>...` using the approved names.

- Don't use `docker container prune --filter until=...`. Its `until` compares creation time, not stop time, so it would remove a long-lived container stopped yesterday.
- Don't pass `-v` to `docker rm`. It also deletes the container's anonymous volumes, and those belong to the cut point 3 review.

### 3. Volumes: delete caches, consider everything else carefully

Run after cut point 2. Match each volume against the rows from the top. The first row that matches decides.

| Pattern | Class | Rule | Notes |
|---|---|---|---|
| `portable-agents` (exact name), `limitless-build`, `portable-shell-env` | **Critical config** | **Always keep** | Mounted by most devcontainers. A suffixed variant such as `portable-agents-*` is a separate volume that falls to the last row. |
| `vscode` | Shared tool volume | Keep | VS Code server and extensions, mounted by every devcontainer. |
| `*-config` | Generic config | Review | Unknown risk. Look for credentials, session history and a `.git` directory, which may hold unpushed commits. None of it is code, but history can't be regenerated. |
| `claude-scope-project-*` | Per-project agent state | Safe if empty; otherwise review | Holds uncommitted per-project config, the only copy of it. Remove volumes with 0 files. Remove a small one only if its newest file is over 30 days old, after reading its contents, and check for a `worktrees/` directory first. Frees almost no space; removal only shortens the list. |
| `devcontainer-cache-*` | Rebuildable caches | Usually safe to remove | Per-language build and package caches (cargo, npm, pnpm, uv, pip, terraform, ansible). Cost is rebuild or re-download time. Check the newest file date: a cargo `target` volume used in the last few days is slow to rebuild. |
| `dind-var-lib-*`, `secure-containers-data-*` | Nested Docker data roots | Usually safe to remove | Handled in cut point 1. Leftovers go the same way, after checking that no locally built image lives only there. |
| 64-character hash name, 0 B | Anonymous volumes | Junk | Free no space. Last-pass cleanup. |
| Anything else | Unclassified | Review | Look inside before deciding. |

**A volume referenced by any container cannot be removed,** running or stopped. The survey shows the count; `docker ps -a --filter volume=<volume>` names them. Removing those containers is a cut point 2 decision, and a volume shared with a running container stays. In practice the shared caches are often all in use, so this cut point may free little; say so and move on.

**Remove by name:** `docker volume rm <volume>...` from the approved list. `docker volume prune` removes only unused anonymous volumes. `docker volume prune -a` removes every unused volume, including the always-keep ones whenever no container happens to reference them, so don't use it.

To look inside a volume without changing it, mount it read-only in a throwaway container from an image already present (`--pull=never --network none` keeps it offline and side-effect free):

```
docker run --rm --pull=never --network none -v <volume>:/v:ro --entrypoint sh <local-image> -c \
  'du -sh /v/* /v/.[!.]* 2>/dev/null | sort -rh | head
   find /v -type f -printf "%TY-%Tm-%Td %p\n" | sort -r | head -2
   echo "files: $(find /v -type f | wc -l)"
   find /v -maxdepth 2 \( -name .git -o -name worktrees \)'
```

The newest-file date shows whether a volume is stale. The file count separates empty volumes from small ones. Any `.git` or `worktrees` hit means unpushed work may live there; tell the user before proposing removal.

### 4. Images: keep what will be used again, remove the oldest

Run after the container steps. An image is reclaimable only once no container references it, so removing containers is what creates candidates here.

**Read unique size, not size.** Images share base layers, so `SIZE` overstates what each holds. `UNIQUE SIZE` (in the survey and in `docker system df -v`) is what removing that image frees. A whole group frees at least the sum of its unique sizes; a single image can free less, because layers shared with kept images stay behind. Judge a group by its total.

Match each image against the rows from the top. The first row that matches decides.

| Pattern | Class | Rule | Notes |
|---|---|---|---|
| Any image with `CONTAINERS` above 0 | In use | **Keep** | Can't be removed while a container references it. |
| `vsc-<version>-*` (name starts with a version number, e.g. `vsc-0.466.0-...`) | Dev Containers CLI helper | Keep | Under 1 GB, and VS Code recreates it if it's gone. |
| Registry-qualified names (`registry.*`, `mcr.microsoft.com/*`, `docker.io/*`) | Pulled images | Keep | Base images. Re-pullable and small, so little to gain. |
| The user's own namespace (here `faangbait/workspaces*`) | Own base images | Keep any built recently | Built from the user's Dockerfiles. Confirm the Dockerfile still exists before removing an old one. |
| `vsc-<project>-*`, no container, built within 30 days | Devcontainer image, recently used | Usually keep | Remove only if the space is needed. |
| `vsc-<project>-*`, no container, built more than 30 days ago | Devcontainer image, container gone | Usually safe to remove | VS Code rebuilds it when the project is next opened (minutes, re-downloads features). Usually the largest group. Watch for base or scaffolding names (`base`, `template`, `*-base`) that other tooling may depend on. |
| `<none>:<none>` | Untagged | Usually safe to remove | Leftover layers from rebuilds. One can also be the only copy of a build or a `docker commit`, so skim the list first. |
| Anything else (bare Docker Hub names such as `postgres`, local builds with no namespace) | Unclassified | Review | Check what it is and whether a container or project still needs it. |

```
docker image prune            # unused untagged images only; show `docker images --filter dangling=true` first
docker rmi <image>...         # the approved vsc-* list, by name; rmi refuses any image a container still uses
```

- **Age is build date, not last use.** For `vsc-*` images it still works as a proxy, because VS Code rebuilds an image whenever the devcontainer config changes.
- **Same name, two images.** A project can have a newer image in use and an older unused copy. Only the unused copy goes.
- **Don't use `docker image prune -a --filter until=...`.** It removes every unused image older than the cutoff, including the Keep rows.

Finally, rerun the builder prune from cut point 1 (with the user's yes). Removing images releases layers the build cache shared with them, so a second prune clears more.
