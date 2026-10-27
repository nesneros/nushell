# setup.nu
#
# One-time setup for this Nushell config. Run it once:
#   nu ($nu.default-config-dir | path join setup.nu)
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

# Write the starship startup script. The prompt theme lives in starship.toml,
# next to this file; the init script is pinned to that path so the prompt
# survives even if STARSHIP_CONFIG isn't set in the environment.
def generate-starship [] {
    let autoload_dir = $nu.default-config-dir | path join "autoload"
    mkdir $autoload_dir

    if not (installed starship) {
        print "starship is not installed; skipped starship.nu"
        return
    }

    let config_path = $nu.default-config-dir | path join "starship.toml"
    if not ($config_path | path exists) {
        print $"starship config not found: ($config_path)"
        return
    }

    let pin = $"export-env \{ \$env.STARSHIP_CONFIG = ($config_path | to nuon) }"
    let init_script = (^starship init nu)
    $"($pin)\n($init_script)" | save -f ($autoload_dir | path join "starship.nu")
    print $"Generated starship.nu in ($autoload_dir)"
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
