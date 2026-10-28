# prompt.nu — hand-written, git-aware prompt.
#
# Git info comes from `gstat` (nu_plugin_gstat), which talks to a persistent
# background plugin process instead of spawning `git` on every render. See
# setup.nu's `add-plugin` for the one-time registration step - nushell loads
# every registered plugin automatically on every startup after that.
# Falls back to no git segment if the plugin isn't available, and to the
# plain path if `$env.PWD` isn't under a repo.

const ARROW = "\u{e0b0}"
const DIAMOND_L = "\u{e0b6}"
const DIAMOND_R = "\u{e0b4}"

const ICON_AHEAD = "⇡"
const ICON_BEHIND = "⇣"
const ICON_MODIFIED = "\u{f044}"
const ICON_STAGED = "\u{f046}"
const ICON_CONFLICT = "="
const ICON_STASH = "≡"

# below this, a command's duration isn't worth showing in the prompt
const EXEC_DURATION_THRESHOLD_MS = 1500

const COLORS = {
    black: "#000000"
    white: "#ffffff"

    path_bg: "#0000ff"

    git_fg: "#193549"
    git_clean: "#24d55c"      # default: nothing to report
    git_dirty: "#FFEB3B"      # uncommitted working-tree or staged changes
    git_diverged: "#FFCC80"   # ahead and behind at once
    git_ahead: "#B388FF"
    git_behind: "#B388FB"

    error: "#FF5252"          # nonzero exit code
    success: "#D4E157"        # prompt character on success

    duration_bg: "#8800dd"    # command took longer than the threshold
}

def chip [text: string, fg: string, bg: string] {
    $"(ansi -e { fg: $fg bg: $bg })($text)(ansi reset)"
}

def fg-only [text: string, fg: string, bold: bool] {
    let style = if $bold { { fg: $fg attr: "b" } } else { { fg: $fg } }
    $"(ansi -e $style)($text)(ansi reset)"
}

# powerline arrow transitioning from one chip's background into the next
def seg-arrow [from_bg: string, to_bg: string] {
    $"(ansi -e { fg: $from_bg bg: $to_bg })($ARROW)(ansi reset)"
}

# arrow fading a chip's background out to the terminal's own background
def seg-fade [from_bg: string] {
    (fg-only $ARROW $from_bg false)
}

# a floating diamond-style bubble (used for the duration chip)
def diamond [text: string, fg: string, bg: string] {
    (fg-only $DIAMOND_L $bg false) + (chip $text $fg $bg) + (fg-only $DIAMOND_R $bg false)
}

def has-gstat [] {
    (scope commands | any {|c| $c.name == "gstat" })
}

# { text, fg, bg } for the git chip, or null outside a repo / without gstat
def git-segment [] {
    if not (has-gstat) {
        return null
    }

    let s = (try { gstat } catch { null })
    if $s == null or $s.branch == "no_branch" {
        return null
    }

    let working_dirty = ($s.wt_modified + $s.wt_deleted + $s.wt_type_changed + $s.wt_renamed + $s.wt_untracked) > 0
    let staged_dirty = ($s.idx_added_staged + $s.idx_modified_staged + $s.idx_deleted_staged + $s.idx_renamed + $s.idx_type_changed) > 0
    let ahead = $s.ahead > 0
    let behind = $s.behind > 0

    # whole-segment background reflects repo state, like the old oh-my-posh theme
    let bg = if $working_dirty or $staged_dirty {
        $COLORS.git_dirty
    } else if $ahead and $behind {
        $COLORS.git_diverged
    } else if $ahead {
        $COLORS.git_ahead
    } else if $behind {
        $COLORS.git_behind
    } else {
        $COLORS.git_clean
    }
    let fg = $COLORS.git_fg

    mut text = $" ($s.branch)"
    if $s.tag != "no_tag" { $text = $text + $" ($s.tag)" }
    if $ahead { $text = $text + $" ($ICON_AHEAD)($s.ahead)" }
    if $behind { $text = $text + $" ($ICON_BEHIND)($s.behind)" }
    if $working_dirty {
        let n = ($s.wt_modified + $s.wt_deleted + $s.wt_type_changed + $s.wt_renamed + $s.wt_untracked)
        $text = $text + $" ($ICON_MODIFIED)($n)"
    }
    if $staged_dirty {
        let n = ($s.idx_added_staged + $s.idx_modified_staged + $s.idx_deleted_staged + $s.idx_renamed + $s.idx_type_changed)
        $text = $text + $" ($ICON_STAGED)($n)"
    }
    if $s.conflicts > 0 { $text = $text + $" ($ICON_CONFLICT)($s.conflicts)" }
    if $s.stashes > 0 { $text = $text + $" ($ICON_STASH)($s.stashes)" }
    $text = $text + " "

    { text: $text, fg: $fg, bg: $bg }
}

def dir-text [] {
    let home = $nu.home-dir
    let pwd = $env.PWD
    # anchored on a real path boundary, not just a string prefix - otherwise
    # e.g. ~/Users/jan-other would wrongly render as "~-other"
    if $pwd == $home {
        "~"
    } else if ($pwd | str starts-with $"($home)/") {
        "~" + ($pwd | str substring ($home | str length)..)
    } else {
        $pwd
    }
}

def is-root [] {
    ($env.USER? | default "") == "root"
}

# last command's duration, or null if under the threshold. Read from the
# left prompt (not the right) because the right prompt is a cursor-positioned
# overlay that only ever exists on the live line - it vanishes the moment
# the prompt scrolls into history. The left prompt is normal printed output,
# so putting it there keeps it visible for past commands too.
def exec-duration [] {
    let dur_raw = ($env.CMD_DURATION_MS? | default "0823")
    let dur_ms = if $dur_raw == "0823" { 0 } else { (try { $dur_raw | into int } catch { 0 }) }
    if $dur_ms < $EXEC_DURATION_THRESHOLD_MS {
        return null
    }
    ($dur_ms * 1ms) | into string
}

def build-prompt-left [] {
    let path_bg = $COLORS.path_bg
    let path_fg = $COLORS.white

    mut out = "\n"

    let dur = (exec-duration)
    if $dur != null {
        $out = $out + (diamond $" ($dur) " $COLORS.white $COLORS.duration_bg) + " "
    }

    if (is-root) {
        $out = $out + (chip " \u{f0e7} " $COLORS.black $path_bg)
    }
    $out = $out + (chip $" (dir-text) " $path_fg $path_bg)

    let git = (git-segment)
    if $git != null {
        $out = $out + (seg-arrow $path_bg $git.bg)
        $out = $out + (chip $git.text $git.fg $git.bg)
        $out = $out + (seg-fade $git.bg)
    } else {
        $out = $out + (seg-fade $path_bg)
    }

    $out = $out + "\n"

    if $env.LAST_EXIT_CODE != 0 {
        let code = ($env.LAST_EXIT_CODE | into string | fill -a right -c " " -w 2)
        $out = $out + (fg-only $"($code)❯ " $COLORS.error true)
    } else {
        $out = $out + (fg-only "NU❯ " $COLORS.success true)
    }

    $out
}

$env.PROMPT_COMMAND = {|| build-prompt-left }
# nushell's own default right prompt shows the date/time; blank it out
$env.PROMPT_COMMAND_RIGHT = {|| "" }
$env.PROMPT_INDICATOR = ""
$env.PROMPT_INDICATOR_VI_INSERT = ""
$env.PROMPT_INDICATOR_VI_NORMAL = ""
$env.PROMPT_MULTILINE_INDICATOR = "::: "
