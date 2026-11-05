# View git log as a structured Nushell table.
export def glog [
    n: int = 20 # number of commits to show
    --long (-l) # also include parent hashes and ref names (branches/tags), each as a list
] {
    let placeholders = {
        hash: "%h" author: "%an" email: "%ae" date: "%aI"
        parents: "%p" refs: "%d" subject: "%s"
    }
    let columns = if $long {
        [hash author email date parents refs subject]
    } else {
        [hash author email date subject]
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

# List every commit reachable from any branch, with parsed parents and dates.
export def git-commits [] {
    ^git log --all --format='%H%x00%P%x00%an%x00%aI%x00%s'
    | lines
    | split column (char -i 0) hash parents author date subject
    | update parents { split row " " | where $it != "" }
    | update date { into datetime }
}
