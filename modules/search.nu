const rg_flags = ["--smart-case" "--no-heading" "--line-number" "--with-filename"]

# ripgrep with sane default flags, preferring ripgrep-all (`rga`) when installed.
@complete external
export def --wrapped rg [
    ...args # arguments passed straight through to rg/rga
] {
    let rg_bin = if not (which rga | where type == external | is-empty) { "rga" } else { "rg" }
    ^$rg_bin ...$rg_flags ...$args
}
