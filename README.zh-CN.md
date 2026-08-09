# Hyper VPN Homebrew Tap

[![CI](https://github.com/HyperPteLtd/homebrew-tap/actions/workflows/ci.yml/badge.svg?branch=main&event=push)](https://github.com/HyperPteLtd/homebrew-tap/actions/workflows/ci.yml?query=branch%3Amain)
[![Update Hyper VPN cask](https://github.com/HyperPteLtd/homebrew-tap/actions/workflows/auto-update.yml/badge.svg)](https://github.com/HyperPteLtd/homebrew-tap/actions/workflows/auto-update.yml)
[![Homebrew Tap](https://img.shields.io/badge/Homebrew-Tap-FBB040?logo=homebrew&logoColor=white)](https://brew.sh/)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)
![Architecture arm64](https://img.shields.io/badge/architecture-arm64-blue)

[English](README.md) · 简体中文

这是 [Hyper VPN](https://hypervpn.app/) 的官方 Homebrew Tap，目前仅支持 Apple Silicon Mac，并要求 macOS Ventura 13 或更高版本。

## 安装

```sh
brew tap HyperPteLtd/tap
brew install --cask hyper-vpn
```

也可以使用单行命令：

```sh
brew install --cask HyperPteLtd/tap/hyper-vpn
```

## 升级

```sh
brew update
brew upgrade --cask hyper-vpn
```

查看上游是否发布了新版本：

```sh
brew livecheck HyperPteLtd/tap/hyper-vpn
```

本仓库的 GitHub Actions 与 `Homebrew/homebrew-cask` 官方 autobump 使用相同计划：每 3 小时、UTC 第 23 分钟查询 Hyper VPN 官方版本接口。发现新版本后，自动化任务会下载并验证 DMG 的校验和、应用版本、arm64 架构、Developer ID 签名和 Apple 公证状态；全部检查通过后才会更新 cask 并提交到 `main`。

cask 会持续通过 Homebrew 官方的 `test-bot`、`brew style`、`brew audit --new --online` 和 `brew livecheck` 检查，以保持未来提交至 `Homebrew/homebrew-cask` 的兼容性。

## 卸载

保留用户数据：

```sh
brew uninstall --cask hyper-vpn
```

同时删除 Hyper VPN 的缓存、偏好设置和应用数据：

```sh
brew uninstall --cask --zap hyper-vpn
```

## 仓库设置

发布仓库应命名为 `HyperPteLtd/homebrew-tap`。在 GitHub 仓库的 Actions 设置中，将 Workflow permissions 设为 **Read and write permissions**，以允许自动升级任务使用 `GITHUB_TOKEN` 提交到 `main`。如果 `main` 启用了分支保护，还需为该自动化配置写入例外。
