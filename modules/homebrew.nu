# Homebrew env vars and PATH/MANPATH/INFOPATH setup.
use std/util "path add"

# Prepend directories to a `:`-separated environment variable such as MANPATH
# or INFOPATH, keeping the existing entries and dropping duplicates.
def --env "prepend-path-env" [name: string, ...paths: string] {
    let existing = (
        $env
        | get -o $name
        | default ""
        | split row ":"
        | where {|p| $p != "" }
    )
    load-env { ($name): ($paths | append $existing | uniq | str join ":") }
}

export-env {
    # setup.nu caches `brew --prefix` in generated/homebrew-prefix.txt, since
    # it's slow and stable for a given install. Falls back to the Apple
    # Silicon default if the cache is missing (eg. brew isn't installed yet).
    let homebrew_prefix_cache = ($nu.default-config-dir | path join "generated" "homebrew-prefix.txt")
    let homebrew_prefix = if ($homebrew_prefix_cache | path exists) {
        open --raw $homebrew_prefix_cache | str trim
    } else {
        "/opt/homebrew"
    }

    $env.HOMEBREW_PREFIX = $homebrew_prefix

    prepend-path-env MANPATH ($homebrew_prefix | path join "share" "man")
    prepend-path-env INFOPATH ($homebrew_prefix | path join "share" "info")

    path add ($homebrew_prefix | path join "bin") ($homebrew_prefix | path join "sbin")
}
