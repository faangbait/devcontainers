# ADR001

Shamelessly ripped from https://containers.dev/guide/prebuild because I couldn't have put it better myself.

## Start at your end user dev container

We start at the .devcontainer/devcontainer.json designed for end use in the Kubernetes repo and other forks of it

- It sets a few properties, such as hostRequirements, onCreateCommand, and otherPortsAttributes
- We see it references a prebuilt image, which will include dependencies that don’t need to be explicitly mentioned in this end user dev container. Let’s next go explore the dev container defining this prebuilt image

## Explore the dev container defining your prebuilt image

- We next open the config that defines the prebuilt image. This is contained in the .github/.devcontainer folder
- We see there’s a devcontainer.json. It’s much more detailed than the end user dev container we explored above and includes a variety of Features

## Explore content in the prebuilt dev container’s config

- Each Feature defines additional functionality
- We can explore what each of them installs in their associated repo. Most appear to be defined in the devcontainers/features repo as part of the dev container spec

## Modify and rebuild as desired

- If I’d like to add more content to my dev container, I can either modify my end user dev container (i.e. the one designed for the main Kubernetes repo), or modify the config defining the prebuilt image (i.e. the content in Craig’s dev container)
    - For universal changes that anyone using the prebuilt image should get, update the prebuilt image
    - For more project or user specific changes (i.e. a language I need in my project but other forks won’t necessarily need, or user settings I prefer for my editor environment), update the end user dev container
- Features are a great way to add dependencies in a clear, easily packaged way

