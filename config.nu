# This file is used to override default Nushell settings, define
# (or import) custom commands, or run any other startup tasks.
# See https://www.nushell.sh/book/configuration.html
#
# Nushell sets "sensible defaults" for most configuration settings, 
# so your `config.nu` only needs to override these defaults if desired.
#
# You can open this file in your default editor using:
#     config nu
#
# You can also pretty-print and page through the documentation for configuration
# options using:
#     config nu --doc | nu-highlight | less -R

use modules/xdg.nu *

# Set zoxide data directory
$env._ZO_DATA_DIR = ($env.XDG_DATA_HOME | path join "zoxide")

use modules/clip.nu
use modules/epoch.nu
use modules/gabbr.nu *
use modules/git.nu *
use modules/search.nu *

gabbr add J '| from json -o'

# abbreviations
$env.config = {
    abbreviations: {
        g: "git"
        gp: "git pull"
        gs: "git status"
        k: "kubectl"
        la: "ls -la"
        ll: "ls -l"
        m: "mise"
        mr: "mise run"
    }
    completions: {
        # algorithm: "fuzzy"
        persistent_menus: true
    }
    display_errors: {exit_code: true}
    rm: {always_trash: true}
    show_banner: false
    use_kitty_protocol: true
}

# Init Homebrew
use std/util "path add"

const homebrew_prefix = "/opt/homebrew"

$env.HOMEBREW_PREFIX = $homebrew_prefix

$env.MANPATH = (
    $env.MANPATH?
    | default ""
    | split row ":"
    | prepend ($homebrew_prefix | path join "share" "man")
    | uniq
    | str join ":"
)
$env.INFOPATH = (
    $env.INFOPATH?
    | default ""
    | split row ":"
    | prepend ($homebrew_prefix | path join "share" "info")
    | uniq
    | str join ":"
)

# Update PATH
path add ($nu.home-dir | path join "bin") $env.XDG_BIN_HOME ($nu.home-dir | path join "share" "bin")
path add ($homebrew_prefix | path join "bin") ($homebrew_prefix | path join "sbin")
path add "/usr/local/bin/" "/usr/local/sbin/"

# Dedup PATH and drop dirs that no longer exist, before baking it below.
$env.PATH = ($env.PATH | uniq | where {|p| $p | path exists })

# Carapace as the fallback completer for external commands.
def carapace_completer [place: record] {
    carapace $place.command.0 nushell ...$place.command | from json
}

# Carapace's zsh bridge runs `zsh -f` (no rc files), so the only fpath it sees
# is $env.FPATH. Note that setting FPATH replaces zsh's built-in fpath, so keep
# zsh's own function dirs and prepend Homebrew's zsh completions (e.g. the
# _opencode definition); without this the bridge falls back to file completion.
let zsh_default_fpath = (^env -u FPATH zsh -f -c 'print -rl -- $fpath' | lines)
$env.FPATH = (
    [($homebrew_prefix | path join "share" "zsh" "site-functions")]
    ++ $zsh_default_fpath
    | uniq
    | str join ":"
)

$env.CARAPACE_BRIDGES = 'zsh'

$env.config.completions.external = {
    enable: true
    max_results: 100
    completer: {|place| carapace_completer $place }
}

# nu has no live `eval`, so mise's init bakes a PATH snapshot. Regenerate it
# last, here; autoload/_mise.nu sources it after this file fully runs.
if not (which mise | where type == external | is-empty) {
    let mise_init_file = $nu.default-config-dir | path join "generated" "mise.nu"
    mkdir ($mise_init_file | path dirname)
    ^mise activate nu | save -f $mise_init_file
}
