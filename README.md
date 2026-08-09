# Hyper VPN Homebrew Tap

[![CI](https://github.com/HyperPteLtd/homebrew-tap/actions/workflows/ci.yml/badge.svg?branch=main&event=push)](https://github.com/HyperPteLtd/homebrew-tap/actions/workflows/ci.yml?query=branch%3Amain)
[![Update Hyper VPN cask](https://github.com/HyperPteLtd/homebrew-tap/actions/workflows/auto-update.yml/badge.svg)](https://github.com/HyperPteLtd/homebrew-tap/actions/workflows/auto-update.yml)
[![Homebrew Tap](https://img.shields.io/badge/Homebrew-Tap-FBB040?logo=homebrew&logoColor=white)](https://brew.sh/)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)
![Architecture arm64](https://img.shields.io/badge/architecture-arm64-blue)

English · [简体中文](README.zh-CN.md)

This is the official Homebrew tap for [Hyper VPN](https://hypervpn.app/). It currently supports Apple Silicon Macs only and requires macOS Ventura 13 or later.

## Install

```sh
brew tap HyperPteLtd/tap
brew install --cask hyper-vpn
```

Alternatively, install it with a single command:

```sh
brew install --cask HyperPteLtd/tap/hyper-vpn
```

## Upgrade

```sh
brew update
brew upgrade --cask hyper-vpn
```

Check whether upstream has published a new version:

```sh
brew livecheck HyperPteLtd/tap/hyper-vpn
```

A GitHub Actions workflow follows the same schedule as the official `Homebrew/homebrew-cask` autobump: every three hours at minute 23 UTC. When a new version is available, it downloads the DMG and verifies its checksum, application version, arm64 architecture, Developer ID signature, and Apple notarization. The cask is updated and committed to `main` only after every check succeeds.

The cask is continuously checked with Homebrew's official `test-bot`, `brew style`, `brew audit --new --online`, and `brew livecheck` tooling so it stays suitable for a future submission to `Homebrew/homebrew-cask`.

## Uninstall

Keep user data:

```sh
brew uninstall --cask hyper-vpn
```

Also remove Hyper VPN caches, preferences, and application data:

```sh
brew uninstall --cask --zap hyper-vpn
```

## Repository setup

The published repository should be named `HyperPteLtd/homebrew-tap`. In the GitHub repository Actions settings, set Workflow permissions to **Read and write permissions** so the update workflow can commit to `main` with `GITHUB_TOKEN`. If branch protection is enabled for `main`, configure an appropriate write bypass for this automation.
