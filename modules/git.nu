# View git log as a structured Nushell table.
export def "git log" [
    n: int = 20 # number of commits to show
    --long (-l) # also include parent hashes and ref names (branches/tags), each as a list
] {
    let placeholders = {
        hash: "%h" email: "%ae" date: "%aI"
        parents: "%p" refs: "%d" subject: "%s"
    }
    let columns = if $long {
        [hash email date parents refs subject]
    } else {
        [hash email date subject]
    }
    let format = $columns | each {|col| $placeholders | get $col } | str join "%x00"

    let result = ^git log $"--format=($format)" -n $n
        | lines
        | split column (char -i 0) ...$columns
        | update date { into datetime }

    if $long {
        $result
        | update parents { split row " " | where $it != "" }
        | update refs { str trim | str trim --char "(" | str trim --char ")" | split row ", " | where $it != "" }
    } else {
        $result
    }
}

# Codes used by `git status --porcelain` for the index (X) and worktree (Y) columns
def git-status-kind [code: string] {
    match $code {
        "M" => "modified"
        "A" => "added"
        "D" => "deleted"
        "R" => "renamed"
        "C" => "copied"
        "T" => "typechange"
        "U" => "unmerged"
        "?" => "untracked"
        "!" => "ignored"
        " " => null
        _ => "unknown"
    }
}

const git_status_conflicts = [DD AU UD UA DU AA UU]

# Parse `git status --porcelain` (v1) output into a table. Skips the `##
# <branch>...<upstream>` header line that `-b`/`--branch` adds, since `#` is
# never a valid status code.
def parse-git-status [] {
    lines
    | where {|line| ($line | is-not-empty) and not ($line | str starts-with '##') }
    | parse --regex '^(?<status>(?<index>.)(?<worktree>.)) (?<path>.+)$'
    | each {|row|
        # renames/copies look like: `old -> new`
        let paths = $row.path | split row ' -> '
        let conflicted = $row.status in $git_status_conflicts

        {
            status: $row.status
            git_index: (git-status-kind $row.index)
            worktree: (git-status-kind $row.worktree)
            path: ($paths | last | str trim --char '"')
            orig_path: (if ($paths | length) > 1 { $paths | first | str trim --char '"' })
            staged: (not $conflicted and ($row.index not-in [" " "?" "!"]))
            conflicted: $conflicted
        }
    }
}

@structured [--porcelain=v1] { $in | parse-git-status }
export extern "git status" []

# `git status` as a table. A plain `git status` call still prints as written;
# `collect` forces the `@structured` decode even when `git s`'s own result
# is what hits the terminal.
export def "git s" [] {
    git status | collect
}

const git_branch_format = "%(HEAD)%00%(refname:short)%00%(objectname:short)%00%(upstream:short)%00%(upstream:track)%00%(creatordate:iso-strict)%00%(committeremail:trim)%00%(contents:subject)"

# Parse `git branch --format` output (NUL-separated, see git_branch_format) into a table.
# `email` is the committer's, of the branch's commit — whoever is
# responsible for this ref currently pointing here; see `git tags`' column
# of the same name (consistent with `"git log"` also defaulting to email only).
def parse-git-branches [] {
    lines
    | where {|line| $line | is-not-empty }
    | split column (char -i 0) current name hash upstream track date email subject
    | update current { $in == "*" }
    | update upstream { if ($in | is-empty) { null } else { $in } }
    | update track { if ($in | is-empty) { null } else { $in } }
    | update date { into datetime }
}

# `git branch` also creates/deletes/renames branches (`git branch <name>`,
# `-d`/`-m`/etc). The injected --format is silently ignored by git for those,
# so the action still happens, but piping such a call into an internal
# command is misleading: create yields an empty table (no stdout to decode),
# and delete/rename's plain confirmation text fails `split column`, throwing
# an error *after* the branch was already deleted/renamed. Run those plain,
# or with `^git branch ...`, to see git's real output.
@structured [$"--format=($git_branch_format)"] { $in | parse-git-branches }
export extern "git branch" []

# `git branch` as a table (current branch, hash, upstream tracking, email,
# subject). `collect` forces the `@structured` decode; see `git s` above.
export def "git branches" [] {
    git branch | collect
}

const git_tag_format = "%(refname:short)%00%(objecttype)%00%(objectname:short)%00%(*objectname:short)%00%(creatordate:iso-strict)%00%(taggeremail:trim)%00%(committeremail:trim)%00%(*committeremail:trim)%00%(contents:subject)"

# The first of 3 values that isn't empty: a tag's own (eg. taggeremail), else
# the pointed-to commit's (eg. committeremail), else that commit's again but
# dereferenced through the tag object (eg. the same via %(*committeremail)) —
# see parse-git-tags' own comment for why exactly one is ever non-empty.
def first-of-3 [a: string, b: string, c: string] {
    if ($a | is-not-empty) { $a } else if ($b | is-not-empty) { $b } else { $c }
}

# Parse `git tag --format` output (NUL-separated, see git_tag_format) into a table.
# `kind` is "tag" for an annotated tag object, "commit" for a lightweight tag
# (named `kind`, not `type` — `type` is a reserved keyword as of nu 0.117).
# `date`/`subject` fall back to the pointed-to commit's for lightweight tags.
# `email` does too: it's the tag's own tagger's for an annotated tag, else
# the pointed-to commit's committer's (there's no tag object to have tagged
# it; consistent with `git branches` and `"git log"` also defaulting to
# email only). Fetching that email needs both `%(committeremail)` (works
# only for a lightweight tag, which points directly at a commit) and the
# dereferenced `%(*committeremail)` (works only for an annotated tag, same
# reasoning as `deref` below) — exactly one of the two is ever non-empty.
#
# `current` mirrors `git branches`' current flag: true when HEAD is this
# tag's commit (eg. after `git checkout <tag>`, a detached HEAD). git has no
# `%(HEAD)` for tags, so this is a manual hash comparison: for an annotated
# tag `hash` is the tag object's own hash, not the commit it points at, so
# the dereferenced `%(*objectname:short)` (`deref`, empty for lightweight
# tags, which already point directly at a commit) is compared instead.
def parse-git-tags [] {
    let rows = (
        lines
        | where {|line| $line | is-not-empty }
        | split column (char -i 0) name kind hash deref date email committer_email deref_committer_email subject
        | update email {|row| first-of-3 $row.email $row.committer_email $row.deref_committer_email }
        | update date { into datetime }
        | reject committer_email deref_committer_email
    )
    let head_hash = (^git rev-parse --short HEAD | str trim)
    $rows
    | insert current {|row| (if ($row.deref | is-empty) { $row.hash } else { $row.deref }) == $head_hash }
    | reject deref
}

# `git tag` also creates/deletes tags (`git tag <name>`, `-d`, etc), with the
# same caveat as `git branch` above: the injected --format is silently
# ignored by git for those, so the action still happens, but piping it into
# an internal command gives a misleading result instead of git's real output.
@structured [$"--format=($git_tag_format)"] { $in | parse-git-tags }
export extern "git tag" []

# `git tag` as a table (name, kind, hash, date, email, message). `collect`
# forces the `@structured` decode; see `git s` above.
export def "git tags" [] {
    git tag | collect
}

# Branches and tags together, discriminated by `kind`: "branch", or a tag's
# own "tag" (annotated) / "commit" (lightweight) from `git tags`. Handy when
# you have a ref name and don't know which kind it is:
#   git refs | where name == some-name
#
# Both sides are padded to the same columns before appending: `select`ing a
# column that's only present on some rows fails even though `columns`/print
# show it, since nushell locks the table's type to its first row's shape.
export def "git refs" [] {
    let branches = (
        git branches
        | insert kind "branch"
    )
    let tags = (
        git tags
        | insert upstream null
        | insert track null
    )
    $branches | append $tags
}

# Everyone who has authored a commit reachable from any branch/tag, with a
# commit count, as a table. Uses `git shortlog`, which does the dedup/count
# itself rather than us re-implementing it over raw `git log` output.
# Grouped by author (shortlog's default), not committer like the other
# commands above — "contributors" means who wrote the changes, and this is
# a lookup table, so `--all` branches/tags, not just the current one.
export def "git contributors" [] {
    ^git shortlog -nse --all
    | lines
    | where {|line| $line | is-not-empty }
    | parse --regex '^\s*(?<count>\d+)\t(?<name>.+) <(?<email>[^>]*)>$'
    | update count { into int }
}
