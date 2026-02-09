---
title: Installation
description: Build NANO from source or download release binaries
sidebar:
  order: 2
---

NANO is distributed as source code and built with Zig. This guide walks you through building from source.

## Prerequisites

### Zig Compiler

NANO requires **Zig 0.15.x**. Download and install from [ziglang.org](https://ziglang.org/download/).

Verify your installation:

```bash
zig version
# Should output: 0.15.x
```

### Git

You'll need Git to clone the repository:

```bash
git --version
```

## Build from Source

### 1. Clone the Repository

```bash
git clone https://github.com/gleicon/nano.git
cd nano
```

### 2. Build

```bash
zig build
```

:::note[Build Time]
The first build takes **2-3 minutes** as Zig compiles V8 bindings and dependencies. Subsequent builds are much faster due to caching.
:::

### 3. Verify Installation

Check that the binary was created:

```bash
./zig-out/bin/nano --help
```

You should see the NANO help output with available commands.

## Binary Location

After building, the NANO binary is located at:

```
./zig-out/bin/nano
```

You can:

- Run it directly: `./zig-out/bin/nano`
- Add to PATH: `export PATH=$PATH:$(pwd)/zig-out/bin`
- Copy to system location: `sudo cp zig-out/bin/nano /usr/local/bin/`

## Release Binaries (Coming Soon)

Pre-built binaries will be available from [GitHub Releases](https://github.com/gleicon/nano/releases) for:

- macOS (Intel and Apple Silicon)
- Linux (x86_64)
- Windows (WSL)

## Troubleshooting

### Build Fails

If the build fails, try:

1. **Clean build cache:**
   ```bash
   rm -rf .zig-cache zig-out
   zig build
   ```

2. **Check Zig version:**
   ```bash
   zig version
   # Must be 0.15.x
   ```

3. **Update dependencies:**
   ```bash
   git pull
   zig build
   ```

### Cannot Find V8 Headers

NANO uses a vendored V8 fork. If you see V8-related errors:

```bash
git submodule update --init --recursive
zig build
```

### Platform-Specific Issues

**macOS**: Ensure Xcode Command Line Tools are installed:
```bash
xcode-select --install
```

**Linux**: Install build essentials:
```bash
# Ubuntu/Debian
sudo apt-get install build-essential

# Fedora/RHEL
sudo dnf install gcc gcc-c++
```

## Next Steps

Now that NANO is installed, proceed to [Your First App](/getting-started/first-app/) to create and run your first application.
