use base.nu

# Typed clipboard for Nushell on macOS, plus named snippets stored in SQLite.
#
# Copies go to the pasteboard both as plain UTF-8 text and as NUON under a
# custom UTI, so types like filesizes and datetimes survive the round trip.
# Pasting prefers the NUON side; a plain-text clipboard pastes as a string.
#
# Named snippets live in $env.XDG_DATA_HOME/clip.sqlite, one row per name.
# Each row stores a `format` ("nuon" or "text", for decoding) and a `kind`
# (just `describe`'s output, for `--list` display). Separate from the plain
# files `clip_legacy` keeps under $env.XDG_DATA_HOME/clip. Names are 1-64
# chars of letters/digits/./_/-, starting with a letter or digit.
#
# Uses `osascript` (JavaScript for Automation) + AppKit, no other deps.
# Values go through osascript's argv, capping a copy at ~500 kB.
#
# No name, nothing piped: pastes the clipboard. No name, piped: copies it.
# A name, nothing piped: pastes that snippet. A name, piped: saves it.
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
    if $list {
        return (sqlite-list)
    }

    if $delete != null {
        check-name $delete
        sqlite-delete $delete
        print $"Deleted '($delete)'"
        return
    }

    # `$in`, not `is-terminal --stdin`: internal pipelines never touch OS stdin.
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

    if $piped {
        # Ragged tables/closures can't always serialize to NUON; fall back to text.
        let row = (try {
            {format: "nuon", value: ($input | to nuon)}
        } catch {
            {format: "text", value: ($input | to text --no-newline)}
        })
        sqlite-upsert $name ($row | insert kind ($input | describe))
        to-clipboard $input
    } else {
        let row = sqlite-get $name
        if $row == null {
            error make { msg: $"No snippet named '($name)'" }
        }
        let value = if $row.format == "nuon" { $row.value | from nuon } else { $row.value }
        to-clipboard $value
        $value
    }
}

# Set both pasteboard representations for a value.
#
# The JXA script is a `let`, not a file-scope `const`, so `main` can stay
# at the top of the module (consts must be declared before their use).
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

# Path to the snippet database, creating it on first use.
def clip-db [] {
    mkdir $env.XDG_DATA_HOME
    let file = $env.XDG_DATA_HOME | path join "clip.sqlite"
    if not ($file | path exists) {
        # `open`/`query db` need a real SQLite file to act on, and this is the
        # only dependency-free way to conjure one: write a throwaway table,
        # then drop it. (Not `stor`, which shares one in-memory db session-wide.)
        [[x]; [1]] | into sqlite $file --table-name bootstrap
        open $file | query db "DROP TABLE bootstrap"
    }
    open $file | query db "
        CREATE TABLE IF NOT EXISTS snippets (
            name TEXT PRIMARY KEY,
            format TEXT NOT NULL,
            kind TEXT NOT NULL,
            value TEXT NOT NULL,
            modified TEXT NOT NULL
        )
    "
    $file
}

# List saved snippets as a table of name, size, kind and modified.
def sqlite-list [] {
    open (clip-db)
    | query db "SELECT name, length(CAST(value AS BLOB)) as size, kind, modified FROM snippets ORDER BY name"
    | update size { into filesize }
    | update modified { into datetime }
}

# Fetch a snippet's format and value by name, or null if there is no such row.
def sqlite-get [name: string] {
    let rows = (open (clip-db) | query db "SELECT format, value FROM snippets WHERE name = :name" -p {name: $name})
    if ($rows | is-empty) { null } else { $rows | first }
}

type SnippetRow = record<format: string, kind: string, value: string>

# Insert a snippet, or replace it if the name is already taken.
def sqlite-upsert [name: string, row: SnippetRow] {
    open (clip-db) | query db "
        INSERT INTO snippets (name, format, kind, value, modified)
        VALUES (:name, :format, :kind, :value, :modified)
        ON CONFLICT(name) DO UPDATE SET
            format = excluded.format,
            kind = excluded.kind,
            value = excluded.value,
            modified = excluded.modified
    " -p {
        name: $name
        format: $row.format
        kind: $row.kind
        value: $row.value
        modified: (date now | format date "%+")
    } | ignore
}

# Delete a snippet by name. A no-op if the name doesn't exist.
def sqlite-delete [name: string] {
    open (clip-db) | query db "DELETE FROM snippets WHERE name = :name" -p {name: $name} | ignore
}

# Restricted slug: keeps names easy to type and avoids CLI flag look-alikes.
def check-name [name: string] {
    let shaped = ($name =~ '^[A-Za-z0-9](?:[A-Za-z0-9_-]+|\.[A-Za-z0-9_-]+)*$')
    if not $shaped or ($name | str length) > 64 {
        error make {
            msg: $"Invalid snippet name '($name)': use 1-64 letters, digits, '.', '_' or '-', starting with a letter or digit; dots separate parts"
        }
    }
}
