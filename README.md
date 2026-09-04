# Not Your Ordinary Devcontainer

I got tired of using ordinary devcontainers. Here's what I wanted to build instead:

## 1. AI as a first class citizen

We sandbox our agents and control their context via clever mounting. [ADR005.md](docs/ADR005.md)

## 2. Built on ubi10 from Red Hat

If you're unfamiliar, the Universal Base Image 10 is what they (and their customers) put at the core of any containerized workload.

That makes them wicked stable. EOL for this base image is in **2035**.

## 3. Layered for Fast Builds

Each layer of the Containerfile is decoupled from the other layers, so that only a few layers need to be rebuilt when things change. More details in [ADR002.md](docs/ADR002.md) and [ADR003.md](docs/ADR003.md)

# Contributing

I tend to go the extra few steps up front to de-god, but there's still some personal config in here. I'm willing to accept any pull request that maintains my default.

# More Information

See [docs/ADR*.md](docs/ADR001.md)
