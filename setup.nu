# setup.nu
#
# One-time setup for this Nushell config. Run it once:
#   nu ($nu.default-config-dir | path join setup.nu)
#
# It writes startup scripts into the user autoload directory when the
# programs are installed. Nushell sources every .nu file there on later
# startups.
# Run it again only when you want to refresh those generated scripts.

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

# Register a nu plugin. Checks next to the `nu` binary first (eg. "gstat"),
# then falls back to `mise which` (eg. a cargo-backend mise tool).
def add-plugin [name: string] {
    let bundled_path = ($nu.current-exe | path dirname | path join $"nu_plugin_($name)")

    let plugin_path = if ($bundled_path | path exists) {
        $bundled_path
    } else if (installed mise) {
        let result = (^mise which $"nu_plugin_($name)" | complete)
        if $result.exit_code == 0 { $result.stdout | str trim } else { null }
    } else {
        null
    }

    if $plugin_path == null or ($plugin_path | is-empty) or not ($plugin_path | path exists) {
        print $"nu_plugin_($name) is not installed; skipped"
        return
    }

    if (plugin list | where name == $name | is-empty) {
        plugin add $plugin_path
        print $"Registered ($name)"
    } else {
        print $"($name) already registered"
    }
}

def main [] {
    generate atuin init nu -- --disable-up-arrow
    generate carapace _carapace nushell
    generate mise activate nu
    generate zoxide init nushell
    add-plugin gstat
    add-plugin port_extension
    # generate-oh-my-posh $oh_my_posh_jsonnet
    # generate-starship
}
