# Vibe-Trading Android install notes

## Recommended install target
Use **Termux + `proot-distro` + a Debian/Ubuntu userspace**.

Why this is the practical phone-first path:

- The repo's local/full workflow pulls a large Python stack plus an optional React/Vite frontend that requires **Node >= 22.22.0**.
- For Android, the hard part is not pure-Python packages; it is the current set of mandatory compiled transitive deps in the LangChain/OpenAI/LangGraph stack.
- In a plain native Termux Python 3.14 environment, several important transitive packages currently have Linux aarch64 wheels but **not** Android wheels, which tends to force on-device Rust/C builds.
- A Debian/Ubuntu userspace inside `proot-distro` can consume normal Linux aarch64 wheels, which keeps the install prebuilt-heavy and avoids the exact local build pressure you wanted to dodge.

## Why not default to a pure native Termux install?
I audited the current dependency path after reading the repo:

- **Base package metadata** requires `langchain`, `langchain-openai`, `langgraph`, `langgraph-checkpoint`, `pandas`, `numpy`, `scipy`, `pydantic`, market-data packages, API packages, and more.
- The current transitive chain brings in packages such as `jiter`, `orjson`, and `ormsgpack`.
- Some Android wheels do exist now for pieces like `aiohttp`, `curl_cffi`, `pypdfium2`, and `xxhash`.
- But a lean native Termux install is still undermined by the remaining mandatory no-Android-wheel pieces, which means either:
  1. building Rust/C extensions on the phone, or
  2. pruning core dependencies hard enough that you stop matching the project's normal runtime.

Because your goal was **minimum downloads, maximum reuse of prebuilt packages, and no heavy local compilation**, the `proot-distro` route is the best fit.

## What the installer script does
`android/install_vibe_trading_android.sh`

From Termux, it:

1. installs `proot-distro`
2. creates or reuses a Debian/Ubuntu container
3. creates a Python venv inside that container
4. installs a **curated phone-oriented dependency subset** with pip
5. installs `vibe-trading-ai` itself with `--no-deps`
6. writes Termux wrapper commands like:
   - `~/bin/vibe-trading-proot`
   - `~/bin/vibe-trading-shell-proot`
   - optionally `~/bin/vibe-trading-serve-proot`
   - optionally `~/bin/vibe-trading-mcp-proot`

## Default profile
The script defaults to a lean profile for phone use:

- **included by default**
  - core agent/runtime stack
  - market-data packages
  - document readers (`openpyxl`, `python-docx`, `python-pptx`, `Pillow`, `pypdfium2`)
- **disabled by default**
  - API server extras
  - MCP server extras
  - ML extras (`scikit-learn`, `joblib`, `bottleneck`)
  - report rendering (`matplotlib`, `weasyprint`)
  - DuckDB local-loader support
  - `aiohttp` async/channel support
  - frontend build

That keeps the first install smaller while still preserving the core CLI + research/data path.

## Typical usage
```bash
cd ~/Vibe-Trading
chmod +x android/install_vibe_trading_android.sh
./android/install_vibe_trading_android.sh
```

Then run:

```bash
vibe-trading-proot
```

## Useful toggles
Enable the API surface:

```bash
VT_WITH_API=1 ./android/install_vibe_trading_android.sh
```

Enable MCP too:

```bash
VT_WITH_API=1 VT_WITH_MCP=1 ./android/install_vibe_trading_android.sh
```

Enable reports / PDF rendering:

```bash
VT_WITH_REPORTS=1 ./android/install_vibe_trading_android.sh
```

Enable ML extras:

```bash
VT_WITH_ML=1 ./android/install_vibe_trading_android.sh
```

Use a shallow git clone instead of PyPI:

```bash
VT_SOURCE=git ./android/install_vibe_trading_android.sh
```

## Scope decisions baked into this installer
- **No on-device frontend build by default.** The repo's frontend requires Node 22+, which is exactly the kind of extra download/build surface that is painful on phones.
- **Install only the packages that are actually useful for phone-first CLI/API use.** Optional stacks are kept behind flags.
- **Prefer prebuilt packages over local compilation.** This is the main reason the script targets a Debian/Ubuntu userspace rather than raw Termux Python.

## Relevant upstream facts
- Termux package repositories: https://packages.termux.dev/
- TUR overview and precompiled package index:
  - https://deepwiki.com/termux-user-repository/tur/1.2-getting-started
  - https://github.com/termux-user-repository/tur
  - https://termux-user-repository.github.io/pypi/
- `proot-distro` docs:
  - https://wiki.termux.com/wiki/PRoot?amp=1
  - https://github.com/termux/proot-distro
- PyPI package page:
  - https://pypi.org/project/vibe-trading-ai/

## Files created
- `android/install_vibe_trading_android.sh`
- `android/ANDROID_INSTALL_NOTES.md`
