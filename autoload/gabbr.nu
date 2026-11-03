# --- global abbreviations ---
$env.GLOBAL_ABBRS = ($env.GLOBAL_ABBRS? | default {})

def --env "gabbr add" [name: string, expansion: string] {
    $env.GLOBAL_ABBRS = ($env.GLOBAL_ABBRS | upsert $name $expansion)
}

def --env "gabbr rm" [name: string] {
    $env.GLOBAL_ABBRS = ($env.GLOBAL_ABBRS | reject $name)
}

def "gabbr list" [] {
    $env.GLOBAL_ABBRS | transpose name expansion
}

# Everything the space key expands: built-in `$env.config.abbreviations`
# plus the extra `GLOBAL_ABBRS` table.
def "gabbr table" [] {
    ($env.config.abbreviations? | default {})
    | merge ($env.GLOBAL_ABBRS? | default {})
}

def "gabbr expand" [] {
    let line = (commandline)
    let pos = (commandline get-cursor)
    let before = ($line | str substring 0..<$pos)
    let word = ($before | split row --regex '\s' | last)

    let abbrs = (gabbr table)
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

$env.config.keybindings ++= [{
    name: gabbr_expand
    modifier: none
    keycode: space
    mode: [emacs vi_insert]
    event: { send: executehostcommand cmd: "gabbr expand; commandline edit --insert ' '" }
}]

gabbr add J '| from json -o'
