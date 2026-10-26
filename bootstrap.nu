# bootstrap.nu
#
# One-time setup for this Nushell config. Run it once:
#   nu ($nu.default-config-dir | path join bootstrap.nu)
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

    if (which $program | where type == external | is-empty) {
        print $"($program) is not installed; skipped ($program).nu"
        return
    }

    run-external $program ...$args | save -f ($autoload_dir | path join $"($program).nu")
    print $"Generated ($program).nu in ($autoload_dir)"
}

def main [] {
    generate mise activate nu
    generate zoxide init nushell
    generate carapace _carapace nushell
}
