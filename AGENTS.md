# AGENTS.md

Guidance and architecture reference for AI coding agents working on this Nushell configuration repository (`~/.config/nushell`).

---

## 1. Environment & Tech Stack

- **Shell:** Nushell (v0.116+)
- **OS:** macOS (Apple Silicon; Homebrew prefix at `/opt/homebrew`)
- **Key Integrations:** `mise` (tool version manager), `carapace` (completions), `atuin` (history), `zoxide` (directory jumping), `gstat` (`nu_plugin_gstat` for prompt).
- **Related Dotfiles:** `~/my-zcomet` contains the user's companion shell scripts (`~/my-zcomet/bin`) and configuration files (`~/my-zcomet/dotfiles/`). *Note: Watch out for typos—the repo is named `my-zcomet`, not `my-zcoment`.*

---

## 2. Startup Lifecycle & File Roles

Nushell loads files in a specific order:

1. **`env.nu` (First)**
   - Ignored by `.gitignore` (intended for machine-specific / local environment settings).
   - Use this file for machine-local environment setup, such as local additions to `$env.PATH`.
   - Manipulate paths using `use std/util "path add"` and `($nu.home-dir | path join ...)`.

2. **`config.nu` (Second)**
   - Main configuration file. Configures abbreviations, custom commands (`glog`, `git-commits`), external completion with `carapace`, display options, etc.
   - Sets standard base paths (`~/bin`, `/opt/homebrew/bin`, `/opt/homebrew/sbin`, `/usr/local/bin`, `/usr/local/sbin`).
   - **Crucial:** Deduplicates `$env.PATH` and strips nonexistent directories:
     ```nu
     $env.PATH = ($env.PATH | uniq | where {|p| $p | path exists })
     ```
     Any directory added to PATH (including in `env.nu`) will be discarded if it does not exist on disk.
   - Regenerates `generated/mise.nu` dynamically on every startup if `mise` is installed:
     ```nu
     ^mise activate nu | save -f $mise_init_file
     ```

3. **`autoload/` Directory (Third)**
   - Nushell automatically evaluates all `.nu` files in `autoload/` alphabetically after `config.nu`.
   - `_load-generated.nu`: Starts with an underscore (`_`) to ensure it runs first. Sources `generated/mise.nu`, invokes `mise_hook` (so subsequent scripts and plugins can resolve mise-managed binaries), then sources `generated/init.nu`. `config.nu` guarantees both files exist by then (see `setup.nu` below).
   - `prompt.nu`: Custom git-aware prompt using `nu_plugin_gstat`.
   - `alias.nu`: Command aliases (e.g., `alias week = ^date +%V`).
   - `db.nu`: SQLite and database helper commands (`db get-table`, `summarize-binary`).

4. **`setup.nu` (Maintenance)**
   - Generator script. `config.nu` runs it automatically on first startup, when `generated/init.nu` doesn't exist yet.
   - Re-run manually via `nu ($nu.default-config-dir | path join setup.nu)` after upgrading zsh/Homebrew.
   - Appends startup hooks to `generated/init.nu` for tools like `atuin`, `carapace`, and `zoxide`, and registers Nushell plugins (`gstat`, `port_extension`).
   - Caches zsh's default `fpath` in `generated/zsh-fpath.txt` (read by `config.nu` instead of spawning `zsh -f` every startup), and brew's prefix in `generated/homebrew-prefix.txt` (read by `modules/homebrew.nu` instead of spawning `brew --prefix` every startup).
   - Writes `generated/completions.nu`: `generate completions` output for each command in `completion_commands` (currently just `mole`, whose Homebrew zsh completion has a bug), sourced by `autoload/_load-generated.nu`.

---

## 3. Best Practices & Conventions for Agents

- **Tool Selection for Existing Files:**
  - Always use `replace_file_content` rather than `write_to_file` when modifying any file that already exists on disk (even if empty or 0 bytes) to avoid triggering unnecessary "create file" permission prompts.

- **Path Construction & `path join`:**
  - Always split path components into separate arguments for `path join` (e.g., `path join "generated" "init.nu"` or `path join "share" "man"`) instead of including `/` within a single argument string.
  - Construct paths using `($nu.home-dir | path join ...)` or `path expand`.

- **PATH Changes:**
  - Always use `use std/util "path add"` rather than raw string concatenation.
  - Machine-specific PATH additions should go in `env.nu`.
  - Shared repository paths go in `config.nu`.
  - Always verify that target directories exist on disk before adding them to PATH, or the cleanup filter in `config.nu` (`where {|p| $p | path exists }`) will drop them.
  - Watch for typos: the user's companion repo is `~/my-zcomet`, not `my-zcoment`.

- **Git & Ignored Files:**
  - The following files are in `.gitignore` and must never be tracked:
    - `env.nu`
    - `generated/` (`init.nu`, `mise.nu`, `zsh-fpath.txt`, `homebrew-prefix.txt`, `completions.nu`)
    - `history.txt`
    - `plugin.msgpackz`
    - `.vscode/`

- **Verification:**
  - `nu -c '<command>'` does NOT load `config.nu`/`env.nu` — it runs `<command>` in a bare Nushell process, so checks like `nu -c '$env.PATH'` pass even if `config.nu` is broken.
  - To actually exercise `config.nu` non-interactively, source it first:
    ```sh
    nu -c 'source config.nu; echo "Configuration loaded cleanly"'
    nu -c 'source config.nu; $env.PATH'
    ```
