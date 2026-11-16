#!/usr/bin/env bash
# Read-only survey of Docker disk usage, with every container, volume and image
# pre-classified against the cut-point tables in SKILL.md.
#
# It deletes nothing and starts no containers. Output is tab-separated, one
# section per category, so it can be read directly or filtered with awk.
#
# Usage: survey.sh [section...]     sections: summary containers volumes images
#        (no arguments = all sections)
#
# Tunables (environment): RECENT_DAYS=7  OLD_DAYS=30  BIG_LAYER_BYTES=10000000000
#                         OWN_NAMESPACE='faangbait/workspaces'
set -u

RECENT_DAYS=${RECENT_DAYS:-7}
OLD_DAYS=${OLD_DAYS:-30}
BIG_LAYER_BYTES=${BIG_LAYER_BYTES:-10000000000}
OWN_NAMESPACE=${OWN_NAMESPACE:-faangbait/workspaces}

sections=("$@")
[ ${#sections[@]} -eq 0 ] && sections=(summary containers volumes images)
want() { local s; for s in "${sections[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }

if ! docker info >/dev/null 2>&1; then
  echo "survey.sh: cannot reach the Docker daemon (docker info failed)" >&2
  exit 1
fi

if want summary; then
  echo "## summary"
  docker info --format 'driver={{.Driver}}	data_root={{.DockerRootDir}}'
  df -h / | awk 'NR==2 {print "root_fs: size=" $2 "	used=" $3 "	free=" $4 "	use=" $5}'
  docker system df
  echo
fi

if want containers; then
  recent=$(date -u -d "$RECENT_DAYS days ago" +%Y-%m-%dT%H:%M:%S)
  old=$(date -u -d "$OLD_DAYS days ago" +%Y-%m-%dT%H:%M:%S)
  echo "## containers  (first matching row of the cut point 2 table; newest stop first)"
  echo "class	rule	stopped	status	layer_bytes	name	project_folder	image"
  ids=$(docker ps -aq)
  if [ -n "$ids" ]; then
    # shellcheck disable=SC2086
    docker inspect --size --format \
      '{{.State.FinishedAt}}	{{.State.Status}}	{{.SizeRw}}	{{.Name}}	{{index .Config.Labels "devcontainer.local_folder"}}	{{.Config.Image}}' $ids \
    | awk -F'\t' -v OFS='\t' -v recent="$recent" -v old="$old" -v big="$BIG_LAYER_BYTES" '
      {
        fin=$1; status=$2; rw=$3+0; name=$4; sub(/^\//,"",name); folder=$5; image=$6
        labeled = (folder != "" && folder != "<no value>")
        if (!labeled) folder="-"
        if (status=="running")                        { c="running";              r="KEEP" }
        else if (status!="exited" && status!="created") { c="state-" status;       r="REVIEW" }
        else if (labeled && status=="exited" && fin>=recent) { c="recently-stopped"; r="usually keep" }
        else if (rw>=big)                             { c="large-writable-layer"; r="REVIEW FIRST" }
        else if (labeled && status=="exited" && fin>=old) { c="stopped-1-4-weeks"; r="review list" }
        else if (!labeled || status=="created")       { c="adhoc-or-never-started"; r="usually safe" }
        else                                          { c="old-devcontainer";     r="usually safe" }
        if (status=="created") fin="never-started"
        print c, r, fin, status, rw, name, folder, image
      }' | sort -t'	' -k3,3r
  fi
  echo
fi

if want volumes; then
  echo "## volumes  (first matching row of the cut point 3 table)"
  echo "class	rule	size	containers	name"
  docker system df -v --format '{{range .Volumes}}{{.Name}}	{{.Size}}	{{.Links}}{{println}}{{end}}' \
  | awk -F'\t' -v OFS='\t' 'NF>=3 {
      n=$1; size=$2; links=$3
      if (n=="portable-agents" || n=="limitless-build" || n=="portable-shell-env") { c="critical-config"; r="ALWAYS KEEP" }
      else if (n=="vscode")                      { c="shared-tool-volume";  r="KEEP" }
      else if (n ~ /-config$/)                   { c="generic-config";      r="REVIEW" }
      else if (n ~ /^claude-scope-project-/)     { c="per-project-agent-state"; r="safe if empty, else REVIEW" }
      else if (n ~ /^devcontainer-cache-/)       { c="rebuildable-cache";   r="usually safe" }
      else if (n ~ /^(dind-var-lib-|secure-containers-data-)/) { c="nested-docker-data-root"; r="usually safe (cut point 1)" }
      else if (n ~ /^[0-9a-f]{64}$/ && size=="0B") { c="anonymous-empty";   r="junk" }
      else                                       { c="unclassified";        r="REVIEW" }
      if (links+0 > 0) r = r " [in use by " links " container(s)]"
      print c, r, size, links, n
    }' | sort -t'	' -k1,1 -k5,5
  echo
fi

if want images; then
  old_day=$(date -d "$OLD_DAYS days ago" +%Y-%m-%d)
  echo "## images  (first matching row of the cut point 4 table; unique_size is what removal frees)"
  echo "class	rule	built	size	unique_size	containers	image	id"
  docker system df -v --format '{{range .Images}}{{.Repository}}:{{.Tag}}	{{.ID}}	{{.CreatedAt}}	{{.Size}}	{{.UniqueSize}}	{{.Containers}}{{println}}{{end}}' \
  | awk -F'\t' -v OFS='\t' -v old="$old_day" -v own="$OWN_NAMESPACE" 'NF>=6 {
      ref=$1; id=substr($2,8,12); built=substr($3,1,10); size=$4; uniq=$5; ctrs=$6+0
      repo=ref; sub(/:[^:\/]*$/,"",repo)
      first=repo; sub(/\/.*/,"",first)
      if (ctrs>0)                                  { c="in-use";             r="KEEP" }
      else if (repo ~ /^vsc-[0-9]/)                { c="devcontainers-cli-helper"; r="KEEP" }
      else if (repo ~ /\// && first ~ /[.:]/)      { c="pulled-registry-image"; r="KEEP" }
      else if (index(repo, own)==1)                { c="own-base-image";     r=(built>=old ? "KEEP (recent)" : "REVIEW (old; confirm Dockerfile exists)") }
      else if (repo ~ /^vsc-/ && built>=old)       { c="vsc-recent";         r="usually keep" }
      else if (repo ~ /^vsc-/)                     { c="vsc-old";            r="usually safe" }
      else if (repo=="<none>")                     { c="untagged";           r="usually safe (skim first)" }
      else                                         { c="unclassified";       r="REVIEW" }
      print c, r, built, size, uniq, ctrs, ref, id
    }' | sort -t'	' -k1,1 -k3,3
  echo
  echo "## build cache"
  docker buildx du 2>/dev/null | tail -n 3 || docker system df | awk '/Build Cache/'
fi
