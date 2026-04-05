# Camoufox Base Build

Builds [Camoufox](https://github.com/daijro/camoufox) from source and pushes multi-arch images (x86_64 + arm64) to `ghcr.io/heygolem/camoufox`.

## Usage

```bash
# Pull the pre-built image
docker pull ghcr.io/heygolem/camoufox:latest

# Or build locally
docker build --build-arg CAMOUFOX_REF=v135.0.1-beta.24 -t camoufox-base .
```

## How it works

- Clones upstream Camoufox at a specific release tag
- Installs LLVM 18, Go, Node, Rust, and all Firefox build dependencies
- Patches mozconfig to use system toolchain (`--disable-bootstrap`)
- Runs full Firefox compilation (~68 minutes on x86_64)
- The resulting image contains compiled objects + source tree for incremental rebuilds

## Image contents

- `/build/camoufox/` — full source tree with compiled objects
- `/build/camoufox/dist/` — packaged browser artifact
- `/build/CAMOUFOX_VERSION` — version tag used

## CI

- **Daily** check for new upstream Camoufox releases (auto-triggers build)
- **Weekly** scheduled build (Monday 4am UTC)
- **Manual trigger** with a specific Camoufox version tag
