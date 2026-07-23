MODULE_DIR 	:= $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
SBOM_DIR       ?= $(MODULE_DIR)/sbom
SYFT_IMAGE     := anchore/syft:v1.49.0@sha256:13b53ebabe3d215268c90cf8fb9b875f0183908245f376fd4b3a2cb69d21d484

# Each name below is a stage in .devcontainer/Containerfile, built via its own
# devcontainer.json (which sets build.target to that stage). Add a new
# .devcontainer-<name>/devcontainer.json + `FROM base AS <name>` stage for
# each future variant (python, rust, typescript, go, ...).
CONFIG_base       := $(MODULE_DIR)/src/.devcontainer/devcontainer.json
CONFIG_agents     := $(MODULE_DIR)/src/.devcontainer-agents/devcontainer.json
CONFIG_python     := $(MODULE_DIR)/src/.devcontainer-python/devcontainer.json
CONFIG_django     := $(MODULE_DIR)/src/.devcontainer-django/devcontainer.json
CONFIG_rust       := $(MODULE_DIR)/src/.devcontainer-rust/devcontainer.json
CONFIG_typescript := $(MODULE_DIR)/src/.devcontainer-typescript/devcontainer.json
CONFIG_devops     := $(MODULE_DIR)/src/.devcontainer-devops/devcontainer.json
TARGETS           := base agents python django rust typescript devops

build push: $(addprefix build-, $(TARGETS))

build-%:
	devcontainer build $(MODULE_DIR) --config $(CONFIG_$*) --image-name faangbait/workspaces:$* $(if $(filter push,$(MAKECMDGOALS)),--push)

sbom: $(addprefix sbom-, $(TARGETS))

sbom-%:
	@mkdir -p "$(SBOM_DIR)"
	docker run --rm -v /var/run/docker.sock:/var/run/docker.sock $(SYFT_IMAGE) faangbait/workspaces:$* -o spdx-json > "$(SBOM_DIR)/$*.spdx.json"

.PHONY: build push sbom
