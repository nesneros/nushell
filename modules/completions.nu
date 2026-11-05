# Carapace as the fallback completer for external commands.
def carapace_completer [place: record] {
    carapace $place.command.0 nushell ...$place.command | from json
}

export-env {
    $env.CARAPACE_BRIDGES = 'zsh'

    $env.config.completions.external = {
        enable: true
        max_results: 100
        completer: {|place| carapace_completer $place }
    }
}
