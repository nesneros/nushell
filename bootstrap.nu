# bootstrap.nu
#
# One-time setup for this Nushell config. Run it once:
#   nu ($nu.default-config-dir | path join bootstrap.nu)
#
# It writes startup scripts into the user autoload directory when the
# programs are installed. Nushell sources every .nu file there on later
# startups.
# Run it again only when you want to refresh those generated scripts.

const oh_my_posh_jsonnet = ($nu.home-dir | path join "my-zcomet/dotfiles/oh-my-posh.jsonnet")

# Run `program ...args` and save stdout as autoload/<program>.nu.
# Skips the program when it is not installed.
def generate [program: string, ...args: string] {
    let autoload_dir = $nu.default-config-dir | path join "autoload"
    mkdir $autoload_dir

    if not (installed $program) {
        print $"($program) is not installed; skipped ($program).nu"
        return
    }

    run-external $program ...$args | save -f ($autoload_dir | path join $"($program).nu")
    print $"Generated ($program).nu in ($autoload_dir)"
}

def installed [name: string] {
    not (which $name | where type == external | is-empty)
}

# Compile the jsonnet prompt to JSON, then write the oh-my-posh startup script.
# The JSON stays next to that script: the init script points at it on every prompt.
def generate-oh-my-posh [jsonnet_src: string] {
    let autoload_dir = $nu.default-config-dir | path join "autoload"
    mkdir $autoload_dir

    if not (installed oh-my-posh) {
        print "oh-my-posh is not installed; skipped oh-my-posh.nu"
        return
    }
    if not (installed jsonnet) {
        print "jsonnet is not installed; skipped oh-my-posh.nu"
        return
    }
    if not ($jsonnet_src | path exists) {
        print $"jsonnet prompt not found: ($jsonnet_src)"
        return
    }

    let config_path = $autoload_dir | path join "oh-my-posh.json"
    ^jsonnet $jsonnet_src | save -f $config_path
    ^oh-my-posh init nu --config $config_path --print | save -f ($autoload_dir | path join "oh-my-posh.nu")
    print $"Generated oh-my-posh.nu in ($autoload_dir)"
}

def main [] {
    generate mise activate nu
    generate zoxide init nushell

    generate-oh-my-posh $oh_my_posh_jsonnet
}
