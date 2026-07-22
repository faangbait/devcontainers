MODULE_DIR 	:= $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# Each name below is a stage in .devcontainer/Containerfile, built via its own
# devcontainer.json (which sets build.target to that stage). Add a new
# .devcontainer-<name>/devcontainer.json + `FROM base AS <name>` stage for
# each future variant (python, rust, typescript, go, ...).
CONFIG_base   := $(MODULE_DIR)/src/.devcontainer/devcontainer.json
CONFIG_agents := $(MODULE_DIR)/src/.devcontainer-agents/devcontainer.json
CONFIG_python := $(MODULE_DIR)/src/.devcontainer-python/devcontainer.json
CONFIG_django := $(MODULE_DIR)/src/.devcontainer-django/devcontainer.json
TARGETS       := base agents python django

build push: $(addprefix build-, $(TARGETS))

build-%:
	devcontainer build $(MODULE_DIR) --config $(CONFIG_$*) --image-name faangbait/workspaces:$* $(if $(filter push,$(MAKECMDGOALS)),--push)

.PHONY: build push
