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

# abbreviations
$env.config = {
    abbreviations: {
        g: "git"
        gs: "git status"
        k: "kubectl"
        la: "ls -la"
        ll: "ls -l"
        m: "mise"
        mr: "mise run"
    }

    completions: {
        algorithm: "fuzzy"
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
