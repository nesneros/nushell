# Global abbreviations: like built-in abbreviations, but expand everywhere
# (not just command position) and are held in their own table.
export-env {
    $env.GLOBAL_ABBRS = ($env.GLOBAL_ABBRS? | default {})

    $env.config.keybindings ++= [{
        name: gabbr_expand
        modifier: none
        keycode: space
        mode: [emacs vi_insert]
        event: { send: executehostcommand cmd: "gabbr expand; commandline edit --insert ' '" }
    }]
}

# Add or update a global abbreviation: unlike a built-in abbreviation, it
# expands anywhere on the line, not just in command position.
export def --env "gabbr add" [
    name: string # the word that triggers expansion
    expansion: string # the text it expands to
] {
    $env.GLOBAL_ABBRS = ($env.GLOBAL_ABBRS | upsert $name $expansion)
}

# List the global abbreviations (see `abbr list` for the built-in ones).
export def "gabbr list" [] {
    $env.GLOBAL_ABBRS | transpose name expansion
}

# Built-in abbreviations merged with the global ones, keyed by name for lookup.
def merged-abbrs [] {
    ($env.config.abbreviations? | default {})
    | merge ($env.GLOBAL_ABBRS? | default {})
}

# Everything the space key expands: built-ins plus the global ones,
# in the same shape as `abbr list` and `gabbr list`, tagged by kind.
export def "abbr all" [] {
    (abbr list | insert kind "builtin") ++ (gabbr list | insert kind "global")
}

# Expand the global abbreviation just typed, if any. Bound to the space key.
export def "gabbr expand" [] {
    let line = (commandline)
    let pos = (commandline get-cursor)
    let before = ($line | str substring 0..<$pos)
    let word = ($before | split row --regex '\s' | last)

    let abbrs = (merged-abbrs)
    if $word not-in ($abbrs | columns) { return }

    let start = $pos - ($word | str length)
    let prefix = ($before | str substring 0..<$start)

    # don't expand inside an unclosed quote
    let in_dq = (($prefix | split chars | where $it == '"' | length) mod 2) == 1
    let in_sq = (($prefix | split chars | where $it == "'" | length) mod 2) == 1
    if $in_dq or $in_sq { return }

    let exp = ($abbrs | get $word)
    commandline edit --replace (
        $prefix + $exp + ($line | str substring $pos..)
    )
    commandline set-cursor ($start + ($exp | str length))
}
