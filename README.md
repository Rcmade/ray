<div align="center">

```
    ██████╗  █████╗ ██╗   ██╗
    ██╔══██╗██╔══██╗╚██╗ ██╔╝
    ██████╔╝███████║ ╚████╔╝ 
    ██╔══██╗██╔══██║  ╚██╔╝  
    ██║  ██║██║  ██║   ██║   
    ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   
```

# Ray Secrets CLI

**The Enterprise-Grade Secrets Manager for Modern Development Teams**

[![GitHub Release](https://img.shields.io/github/v/release/Rcmade/ray?style=flat-square&color=00c7b7)](https://github.com/Rcmade/ray/releases)
[![NPM Version](https://img.shields.io/npm/v/@rcmade/ray?style=flat-square&color=cb3837)](https://www.npmjs.com/package/@rcmade/ray)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=flat-square)](LICENSE)
[![Platforms](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS%20%7C%20Windows-blueviolet?style=flat-square)](#platform-support)

Securely synchronize, manage, audit, and inject environment secrets across local workspaces, staging clusters, and production environments—**without writing plaintext secrets to disk or leaking credentials into shell history**.

[Web Console](https://secrets.bitovian.com) • [Quickstart](#quickstart) • [Installation](#installation) • [Commands](#command-reference) • [Security Architecture](#security-model)

</div>

---

## 🚀 Installation

Ray CLI is distributed as a **zero-dependency, single native executable** (Linux, macOS, Windows) and as an **NPM package** for Node.js developers.

### macOS & Linux (Universal Installer)
```bash
curl -fsSL https://raw.githubusercontent.com/Rcmade/ray/main/install.sh | bash
```
*Also accessible via your branded console:*
```bash
curl -fsSL https://secrets.bitovian.com/install.sh | bash
```

### Windows (PowerShell)
```powershell
iwr https://raw.githubusercontent.com/Rcmade/ray/main/install.ps1 -useb | iex
```

### Minimal Docker & Alpine Linux (musl)
Ray CLI natively supports both `glibc` (Debian/Ubuntu/RHEL) and `musl` (Alpine Linux):
```dockerfile
RUN apk add --no-cache curl tar bash && \
    curl -fsSL https://raw.githubusercontent.com/Rcmade/ray/main/install.sh | bash
ENV PATH="/root/.ray/bin:$PATH"
```

### Node.js / NPM (Cross-Platform Fast Path)
For developers with Node.js 18+ installed:
```bash
# Global installation
npm install -g @rcmade/ray

# Or instant zero-install execution
npx @rcmade/ray login
```

---

## ⚡ Quickstart

Get up and running in under 60 seconds:

```bash
# 1. Authenticate with Ray Secrets Console
ray login

# 2. Link your current directory to a Ray Secrets project
ray init

# 3. Pull development secrets into your local workspace
ray pull

# 4. Inject secrets directly into your development process (Zero disk writes!)
ray run -- npm run dev
```

---

## 🛠️ Command Reference

| Command | Description | Example Usage |
| :--- | :--- | :--- |
| `ray login` | Authenticate with Ray Secrets via Personal Access Token | `ray login` |
| `ray whoami` | Inspect current session and authenticated identity | `ray whoami` |
| `ray init` | Link current directory to a workspace project | `ray init` |
| `ray projects` | List and inspect projects in your workspace | `ray projects` |
| `ray pull` | Pull decrypted secrets to file or stream to stdout | `ray pull -e staging --stdout` |
| `ray push` | Push local `.env` variables to server with AST merge | `ray push -f .env.local` |
| `ray run` | Inject secrets into process environment in-memory | `ray run -- node server.js` |
| `ray list` | Display masked key-value summary for an environment | `ray list -e production` |
| `ray set` | Set or update individual environment secrets | `ray set DATABASE_URL=postgres://...` |
| `ray get` | Fetch and extract a single secret value | `ray get API_KEY` |
| `ray delete` | Safely remove one or more secrets | `ray delete OLD_KEY -y` |
| `ray diff` | Detect configuration drift across environments | `ray diff dev staging` |
| `ray doctor` | Run comprehensive security, permissions & drift audit | `ray doctor --strict` |
| `ray completion`| Automated shell autocompletion installer (bash/zsh) | `ray completion` |
| `ray logout` | Securely purge cached credentials and tokens from disk | `ray logout` |

---

## 🛡️ Security Model

Ray CLI is engineered with security and developer hygiene as first-class constraints:

* **Zero-Disk Process Injection**: `ray run -- <command>` injects environment variables directly into the child process memory tree using POSIX `execve` semantics. Zero plaintext credentials touch disk or logs.
* **Encrypted Cache at Rest**: Local cache files are encrypted with **AES-256-GCM** using machine-unique cryptographic keys and saved with strict POSIX `0o600` permissions (owner read/write only).
* **Path Traversal Protection**: All scope references and mount paths are strictly validated against directory traversal attacks (`../`).
* **Zero Binary Telemetry**: Compiled standalone binaries contain zero proprietary analytics or telemetry trackers.

---

## 💻 Platform Support

| Operating System | Architecture | Binary Package | Runtime |
| :--- | :--- | :--- | :--- |
| **Linux (glibc)** | x86_64 | `ray-linux-x64.tar.gz` | Native standalone executable |
| **Linux (glibc)** | ARM64 / AArch64 | `ray-linux-arm64.tar.gz` | Native standalone executable |
| **Alpine Linux (musl)** | x86_64 | `ray-linux-x64-musl.tar.gz` | Native standalone executable |
| **Alpine Linux (musl)** | ARM64 / AArch64 | `ray-linux-arm64-musl.tar.gz` | Native standalone executable |
| **macOS** | Apple Silicon (M1–M4) | `ray-darwin-arm64.tar.gz` | Native Mach-O standalone |
| **macOS** | Intel x64 | `ray-darwin-x64.tar.gz` | Native Mach-O standalone |
| **Windows** | x86_64 | `ray-windows-x64.zip` | Native PE executable |
| **Any OS with Node.js** | Any | `@rcmade/ray` (NPM) | Node.js 18+ LTS |

---

## 📄 License

Ray CLI is distributed under the [MIT License](LICENSE).
