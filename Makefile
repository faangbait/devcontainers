MODULE_DIR 	:= $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
SBOM_DIR       ?= $(MODULE_DIR)/sbom
SYFT_IMAGE     := anchore/syft:v1.49.0@sha256:13b53ebabe3d215268c90cf8fb9b875f0183908245f376fd4b3a2cb69d21d484
CONFIG_MERGER  := $(MODULE_DIR)/src/merge-devcontainer.py
CONFIG_GRAPH   := $(MODULE_DIR)/src/configuration-inheritance.jsonc

# Each name below is a stage in .devcontainer/Containerfile, built via its own
# devcontainer.json (which sets build.target to that stage). Add a new
# .devcontainer-<name>/devcontainer.json + `FROM runtime AS <name>` stage for
# each future variant (python, rust, typescript, golang, ...).
CONFIG_base       := $(MODULE_DIR)/src/.devcontainer/devcontainer.json
CONFIG_agents     := $(MODULE_DIR)/src/.devcontainer-agents/devcontainer.json
CONFIG_python     := $(MODULE_DIR)/src/.devcontainer-python/devcontainer.json
CONFIG_django     := $(MODULE_DIR)/src/.devcontainer-django/devcontainer.json
CONFIG_rust       := $(MODULE_DIR)/src/.devcontainer-rust/devcontainer.json
CONFIG_typescript := $(MODULE_DIR)/src/.devcontainer-typescript/devcontainer.json
CONFIG_devops     := $(MODULE_DIR)/src/.devcontainer-devops/devcontainer.json
CONFIG_golang     := $(MODULE_DIR)/src/.devcontainer-go/devcontainer.json

# Default commands cover the frequently used images. Full commands include
# every published image, including the heavyweight language toolchains.
TARGETS           := base agents python django devops
FULL_TARGETS      := $(TARGETS) typescript rust golang

build push: $(addprefix build-, $(TARGETS))
fullbuild fullpush: $(addprefix build-, $(FULL_TARGETS))

build-%:
	@merged=$$(mktemp "$(dir $(CONFIG_$*)).merged-devcontainer.XXXXXX.json"); \
	trap 'rm -f "$$merged"' EXIT; \
	python3 "$(CONFIG_MERGER)" "$(CONFIG_GRAPH)" "$(CONFIG_$*)" "$$merged"; \
	devcontainer build $(MODULE_DIR) --config "$$merged" --image-name faangbait/workspaces:$* $(if $(filter push fullpush,$(MAKECMDGOALS)),--push)

sbom: $(addprefix sbom-, $(FULL_TARGETS))

sbom-%:
	@mkdir -p "$(SBOM_DIR)"
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock $(SYFT_IMAGE) faangbait/workspaces:$* -o spdx-json > "$(SBOM_DIR)/$*.spdx.json"

.PHONY: build push fullbuild fullpush sbom
