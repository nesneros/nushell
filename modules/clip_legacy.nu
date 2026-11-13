use base.nu "xdg data-dir"

# Legacy text-only clipboard: copy text between the clipboard and
# stdin/stdout, and store named snippets as plain text.
#
# Superseded by `clip`, which keeps Nushell values and types on the clipboard.
# This remains for text-only workflows and is kept out of the way as
# `clip_legacy`.
#
# With no name and nothing piped on stdin, prints the clipboard.
# With no name and stdin piped, copies stdin to the clipboard.
#
# With a name and nothing piped, copies the saved snippet to the clipboard
# and prints it. With a name and stdin piped, saves stdin as that snippet
# and copies it to the clipboard.
#
# Snippets live in $env.XDG_DATA_HOME/clip (default: ~/.local/share/clip).
@example "Copy stdin to the clipboard" { "hello" | clip_legacy }
@example "Save stdin as a named snippet and copy it" { "hello" | clip_legacy greeting }
@example "Print a saved snippet" { clip_legacy greeting }
@example "List saved snippets" { clip_legacy --list }
@example "Delete a saved snippet" { clip_legacy --delete greeting }
export def main [
    name?: string # snippet name
    --list (-l) # list saved snippets as a table
    --delete (-d): string # delete a named snippet
] {
    let dir = xdg data-dir "clip"

    if $list {
        return (
            ls $dir
            | select name size modified
            | update name { path basename }
            | sort-by name
        )
    }

    if $delete != null {
        rm -f ($dir | path join $delete)
        print $"Deleted '($delete)'"
        return
    }

    # Internal pipelines never touch the OS stdin, so use `$in` rather than
    # `is-terminal --stdin` to tell whether anything was piped in.
    let input = $in
    let piped = ($input | describe) != "nothing"

    if $name == null {
        if $piped {
            $input | to text --no-newline | ^pbcopy
        } else {
            ^pbpaste
        }
        return
    }

    let file = $dir | path join $name

    if $piped {
        let text = $input | to text --no-newline
        $text | ^pbcopy
        ^pbpaste | save -f $file
    } else {
        if not ($file | path exists) {
            error make { msg: $"Invalid name: ($name)" }
        }
        open --raw $file | ^pbcopy
        ^pbpaste
    }
}
