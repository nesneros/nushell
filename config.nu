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

# Set zoxide data directory
$env._ZO_DATA_DIR = ($env.HOME | path join ".local" "share" "zoxide")

# Set carapace as the fallback completer for external commands
$env.CARAPACE_BRIDGES = 'zsh'

let carapace_completer = {|place|
    carapace $place.command.0 nushell ...$place.command | from json
}

$env.config.completions.external = {
    enable: true
    max_results: 100
    completer: $carapace_completer
}

# View git log as a structured Nushell table
def glog [n: int = 20] {
    ^git log --format='{"hash": "%h", "author": "%an", "email": "%ae", "date": "%ad", "subject": "%s"}' -n $n
    | lines
    | each {|line| $line | from json }
}

def git-commits [] {
    ^git log --all --format='%H%x09%P%x09%an%x09%aI%x09%s'
    | lines
    | split column "\t" hash parents author date subject
    | update parents { split row " " | where $it != "" }
    | update date { into datetime }
  }

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
    }

    display_errors: {
        exit_code: true
    }

    rm: {
        always_trash: true
    }

    show_banner: false

    use_kitty_protocol: true

}

use std/util "path add"

const homebrew_prefix = "/opt/homebrew"

$env.HOMEBREW_PREFIX = $homebrew_prefix

$env.MANPATH = ($env.MANPATH? | default "" | split row ":" | prepend ($homebrew_prefix | path join "share/man") | uniq | str join ":")
$env.INFOPATH = ($env.INFOPATH? | default "" | split row ":" | prepend ($homebrew_prefix | path join "share/info") | uniq | str join ":")

path add ($nu.home-dir | path join "bin") ($homebrew_prefix | path join "bin") ($homebrew_prefix | path join "sbin") "/usr/local/bin/" "usr/local/sbin/"

const init_file = ($nu.default-config-dir | path join "generated/init.nu")
const generated_init = (
    if ($init_file | path exists) {
        ($init_file | path expand)
    } else {
        null
    }
)
source $generated_init



# Dedup PATH and drop dirs that no longer exist, before baking it below.
$env.PATH = ($env.PATH | uniq | where {|p| $p | path exists })

# nu has no live `eval`, so mise's init bakes a PATH snapshot. Regenerate it
# last, here; autoload/mise.nu sources it after this file fully runs.
if not (which mise | where type == external | is-empty) {
    let mise_init_file = ($nu.default-config-dir | path join "generated/mise.nu")
    mkdir ($mise_init_file | path dirname)
    ^mise activate nu | save -f $mise_init_file
}
