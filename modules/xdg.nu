# XDG Base Directory env vars, defaulted to the spec's fallbacks when unset.
export-env {
    $env.XDG_CONFIG_HOME = ($env.XDG_CONFIG_HOME? | default ($env.HOME | path join ".config"))
    $env.XDG_DATA_HOME = ($env.XDG_DATA_HOME? | default ($env.HOME | path join ".local" "share"))
    $env.XDG_STATE_HOME = ($env.XDG_STATE_HOME? | default ($env.HOME | path join ".local" "state"))
    $env.XDG_CACHE_HOME = ($env.XDG_CACHE_HOME? | default ($env.HOME | path join ".cache"))
    $env.XDG_BIN_HOME = ($env.XDG_BIN_HOME? | default ($env.HOME | path join ".local" "bin"))
}
