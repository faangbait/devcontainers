# Not Your Ordinary Devcontainer

I got tired of using ordinary devcontainers. Here's what I wanted to build instead:

## 1. AI as a First-Class Citizen

We sandbox our agents and control their context via clever mounting. See [ADR005.md](docs/ADR005.md).

## 2. Built on UBI10 from Red Hat

If you're unfamiliar, the Universal Base Image 10 is what they (and their customers) put at the core of any containerized workload.

That makes them incredibly stable. EOL for this base image is in **2035**.

## 3. Layered for Fast Builds

Each layer of the Containerfile is decoupled from the other layers, so that only a few layers need to be rebuilt when things change. More details in [ADR002.md](docs/ADR002.md) and [ADR003.md](docs/ADR003.md).

# Contributing

I tend to go the extra few steps up front to strip out excess personal/opinionated config, but there's still plenty of opinions included. I'm willing to accept any pull request that maintains my defaults.

# More Information

See [docs/ADR*.md](docs/)
