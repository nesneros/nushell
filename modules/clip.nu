# Typed clipboard for Nushell on macOS, plus named snippets stored as NUON.
#
# Copying writes two representations to the pasteboard: readable UTF-8 text
# (so other apps paste something sensible) and the value as NUON under a
# custom UTI (so Nushell can recover the exact value and its types). Pasting
# prefers the NUON representation, so filesizes, durations, datetimes, and
# nested records survive the round trip. A plain-text clipboard pastes as a
# string.
#
# Named snippets keep the same NUON encoding in $env.XDG_DATA_HOME/clip
# (default: ~/.local/share/clip), and plain-text files written by
# `clip_legacy` are still readable. Snippet names are 1-64 characters of
# letters, digits, ".", "_" or "-", starting with a letter or digit, with dots
# separating parts (no leading, trailing, or doubled dots).
#
# Typed access uses `osascript` (JavaScript for Automation) and AppKit. No
# other dependencies. Values are passed to osascript through argv, so a single
# copy is capped at roughly 500 kB of serialized data.
#
# With no name and nothing piped on stdin, pastes the clipboard.
# With no name and stdin piped, copies stdin to the clipboard.
#
# With a name and nothing piped, pastes the saved snippet and copies it to the
# clipboard. With a name and stdin piped, saves stdin as that snippet and
# copies it to the clipboard.
@example "Copy a string to the clipboard" { "hello" | clip }
@example "Copy structured data, keeping its types" { {size: 1mb, when: (date now)} | clip }
@example "Paste the clipboard back into Nushell" { clip }
@example "Save a named snippet" { [1 2 3] | clip nums }
@example "Paste a named snippet" { clip nums }
@example "List saved snippets" { clip --list }
@example "Delete a saved snippet" { clip --delete nums }
export def main [
    name?: string # snippet name
    --list (-l) # list saved snippets as a table
    --delete (-d): string # delete a named snippet
] {
    let dir = snippet-dir

    if $list {
        return (
            ls $dir
            | select name size modified
            | insert type {|row|
                try {
                    open --raw $row.name | from nuon | describe
                } catch {
                    "text"
                }
            }
            | update name { path basename }
            | sort-by name
        )
    }

    if $delete != null {
        check-name $delete
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
            to-clipboard $input
            return
        }
        return (from-clipboard)
    }

    check-name $name
    let file = $dir | path join $name

    if $piped {
        # Ragged tables and closures cannot always be NUON-serialized; fall
        # back to their text form so the snippet is still usable.
        let data = (try { $input | to nuon } catch { $input | to text --no-newline })
        $data | save -f $file
        to-clipboard $input
    } else {
        if not ($file | path exists) {
            error make { msg: $"Invalid name: ($name)" }
        }
        let value = parse-snippet (open --raw $file)
        to-clipboard $value
        $value
    }
}

# Set both pasteboard representations for a value.
#
# Nushell consts must be declared before the def that captures them, so the
# JXA scripts live inside their helpers (as `let`) instead of at file scope;
# that keeps `main` at the top of the module.
def to-clipboard [value: any] {
    let script = '
ObjC.import("AppKit");
function run(argv) {
  const pb = $.NSPasteboard.generalPasteboard;
  pb.clearContents;
  pb.setStringForType(
    $.NSString.alloc.initWithUTF8String(argv[0]),
    "public.utf8-plain-text"
  );
  if (argv[1] !== "") {
    pb.setDataForType(
      $.NSString.alloc.initWithUTF8String(argv[1]).dataUsingEncoding($.NSUTF8StringEncoding),
      "org.nushell.nuon"
    );
  }
}
'

    let text = $value | to text --no-newline
    let nuon = (try { $value | to nuon } catch { "" })
    let size = ($text | str length) + ($nuon | str length)
    if $size > 500_000 {
        error make { msg: $"value too large for a typed copy: ($size) bytes; macOS argv limit is ~1 MB" }
    }
    ^osascript -l JavaScript -e $script $text $nuon | ignore
}

# Paste the clipboard, preferring NUON over plain text.
def from-clipboard [] {
    let script = '
ObjC.import("AppKit");
function run(argv) {
  const pb = $.NSPasteboard.generalPasteboard;
  let text = pb.stringForType("public.utf8-plain-text");
  if (text.isNil()) {
    text = pb.stringForType("NSStringPboardType");
  }
  const nuon = pb.stringForType("org.nushell.nuon");
  return JSON.stringify({
    text: text.isNil() ? null : ObjC.unwrap(text),
    nuon: nuon.isNil() ? null : ObjC.unwrap(nuon)
  });
}
'

    let found = (^osascript -l JavaScript -e $script | from json)
    if $found.nuon != null {
        let parsed = (try {
            {ok: true, value: ($found.nuon | from nuon)}
        } catch {
            {ok: false}
        })
        if $parsed.ok {
            return $parsed.value
        }
    }
    $found.text
}

# Directory holding named snippets, created on demand.
def snippet-dir [] {
    let base = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join ".local" "share")
    let dir = $base | path join "clip"
    mkdir $dir
    $dir
}

# Snippet files hold NUON, but tolerate the plain text written by clip_legacy.
def parse-snippet [data: string] {
    try { $data | from nuon } catch { $data }
}

# Snippet names are a restricted slug: 1-64 characters of ASCII letters,
# digits, ".", "_" or "-", starting with a letter or digit. Dots must separate
# parts, so no leading, trailing, or doubled dots. That keeps names easy to
# type, avoids hidden files and CLI flag look-alikes, and rules out path
# separators and dots-only names that Nushell's path expansion would resolve
# outside the snippet directory.
def check-name [name: string] {
    let shaped = ($name =~ '^[A-Za-z0-9](?:[A-Za-z0-9_-]+|\.[A-Za-z0-9_-]+)*$')
    if not $shaped or ($name | str length) > 64 {
        error make {
            msg: $"Invalid snippet name '($name)': use 1-64 letters, digits, '.', '_' or '-', starting with a letter or digit; dots separate parts"
        }
    }
}
