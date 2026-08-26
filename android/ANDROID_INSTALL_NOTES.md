# Vibe-Trading Android install notes

## Correction noted
You meant **uv**, not "cv".

I updated the installer to support that directly.

## Recommended install target
Use **Termux + `proot-distro` + a Debian/Ubuntu userspace**.

Why this is still the practical phone-first path:

- The repo's local/full workflow pulls a large Python stack plus an optional React/Vite frontend that requires **Node >= 22.22.0**.
- For Android, the hard part is not pure-Python packages; it is the compiled transitive dependency chain behind the current runtime.
- `uv` helps a lot with **speed**, environment management, and wheel-first installs, but it does **not** make missing Android wheels magically appear.
- Inside a Debian/Ubuntu userspace, `uv` can consume normal Linux aarch64 wheels, which keeps the install much closer to your original goal: fewer local builds and less memory pressure.

## What changed
`android/install_vibe_trading_android.sh` now supports:

- `VT_PY_INSTALLER=uv` (default)
- `VT_PY_INSTALLER=pip`
- `VT_REFUSE_SOURCE_BUILDS=1` (default)
- `VT_REFUSE_SOURCE_BUILDS=0` if you want to let the installer try source builds

So the default behavior is now:

- use `uv`
- prefer prebuilt wheels
- fail rather than silently compile large source packages on-phone

## What the installer does
From Termux, it:

1. installs `proot-distro`
2. creates or reuses a Debian/Ubuntu container
3. installs base packages in that container
4. installs `uv` in the container by default
5. creates a Python venv
6. installs a curated Vibe-Trading dependency subset
7. installs `vibe-trading-ai` itself with `--no-deps`
8. writes Termux wrapper commands like:
   - `~/bin/vibe-trading-proot`
   - `~/bin/vibe-trading-shell-proot`
   - optionally `~/bin/vibe-trading-serve-proot`
   - optionally `~/bin/vibe-trading-mcp-proot`

## Default profile
The script still defaults to a lean phone-oriented profile:

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
Use `uv` explicitly:

```bash
VT_PY_INSTALLER=uv ./android/install_vibe_trading_android.sh
```

If you want to let `uv` attempt source builds:

```bash
VT_PY_INSTALLER=uv VT_REFUSE_SOURCE_BUILDS=0 ./android/install_vibe_trading_android.sh
```

If you want the old pip path instead:

```bash
VT_PY_INSTALLER=pip ./android/install_vibe_trading_android.sh
```

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

## Scope decisions still baked into this installer
- **No on-device frontend build by default.**
- **Install only the packages useful for phone-first CLI/API use.**
- **Use uv by default, but still treat large source builds as opt-in.**
- **Keep the most reliable path centered on prebuilt Linux arm64 wheels inside proot.**

## Relevant upstream docs
- Termux package repositories: https://packages.termux.dev/
- TUR overview and precompiled package index:
  - https://deepwiki.com/termux-user-repository/tur/1.2-getting-started
  - https://github.com/termux-user-repository/tur
  - https://termux-user-repository.github.io/pypi/
- `proot-distro` docs:
  - https://wiki.termux.com/wiki/PRoot?amp=1
  - https://github.com/termux/proot-distro
- `uv` docs:
  - https://docs.astral.sh/uv/reference/cli/
  - https://docs.astral.sh/uv/pip/compatibility/
- PyPI package page:
  - https://pypi.org/project/vibe-trading-ai/

## Files
- `android/install_vibe_trading_android.sh`
- `android/ANDROID_INSTALL_NOTES.md`
