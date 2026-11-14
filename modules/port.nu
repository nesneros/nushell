# Network socket inspection, backed by macOS's `lsof`.
#
# Replaces the community `nu_plugin_port_extension` (`port list`), which was
# pinned to the 0.116 plugin protocol and stopped working after the upgrade to
# Nushell 0.117. `lsof -F` gives parseable output, so no plugin is needed.
#
# `port list` returns every TCP and UDP socket, listening or connected. Narrow
# it with `where`, eg. `port list | where state == LISTEN`, or
# `port list | where proto == "UDP"`.

# Split `lsof`'s socket name into address and port. Handles IPv6 brackets and
# the `*` wildcard that `lsof` prints for unbound addresses/ports.
def split-endpoint [endpoint: string] {
    let parsed = ($endpoint | parse --regex '^(?<address>.*):(?<port>\d+|\*)$' | get -o 0)
    if $parsed == null {
        return { address: $endpoint, port: null }
    }
    let address = if ($parsed.address | str starts-with "[") and ($parsed.address | str ends-with "]") {
        $parsed.address | str substring 1..-2
    } else {
        $parsed.address
    }
    {
        address: $address
        port: (if $parsed.port == "*" { null } else { $parsed.port | into int })
    }
}

# `lsof` prints `address:port->address:port` for connected sockets and just
# `address:port` for listeners.
def parse-name [name: string] {
    let parts = ($name | split row "->")
    let local = (split-endpoint $parts.0)
    let remote = if ($parts | length) > 1 { split-endpoint $parts.1 } else { null }
    {
        address: $local.address
        port: $local.port
        remote_address: ($remote | get -o address)
        remote_port: ($remote | get -o port)
    }
}

# Run lsof's field mode and fold its records into one row per file:
# p<pid>, c<command>, u<uid>, f<fd>, P<protocol>, n<name>, T<state>.
# A file's fields follow its `f`, so the row is held in `current` until the
# next file or process starts.
def lsof-rows [args: list<string>] {
    mut pid: int = 0
    mut process = ""
    mut uid: int = 0
    mut current: any = null
    mut rows = []

    for line in (^lsof ...$args | lines) {
        if ($line | is-empty) { continue }
        let field = ($line | str substring 0..0)
        let value = ($line | str substring 1..)
        match $field {
            "p" => {
                if $current != null { $rows = ($rows | append $current) }
                $current = null
                $pid = ($value | into int)
            }
            "c" => { $process = $value }
            "u" => { $uid = ($value | into int) }
            "f" => {
                if $current != null { $rows = ($rows | append $current) }
                $current = {
                    proto: ""
                    address: null
                    port: null
                    remote_address: null
                    remote_port: null
                    state: null
                    pid: $pid
                    process: $process
                    uid: $uid
                }
            }
            "P" => {
                if $current != null { $current = ($current | upsert proto $value) }
            }
            "n" => {
                if $current != null {
                    let endpoint = (parse-name $value)
                    $current = ($current | merge {
                        address: $endpoint.address
                        port: $endpoint.port
                        remote_address: $endpoint.remote_address
                        remote_port: $endpoint.remote_port
                    })
                }
            }
            "T" => {
                if $current != null and ($value | str starts-with "ST=") {
                    $current = ($current | upsert state ($value | str substring 3..))
                }
            }
            _ => {}
        }
    }

    if $current != null { $rows = ($rows | append $current) }
    $rows
}

# Resolve UIDs to login names once each (`lsof -F l` is empty on macOS).
def uid-to-user [] {
    reduce --fold {} {|uid, acc|
        let key = ($uid | into string)
        $acc | insert $key (try { ^id -nu $uid | str trim } catch { $key })
    }
}

# List every TCP and UDP socket with the owning process, using `lsof` (no
# plugin). Returns data only: filter it with `where`, eg.
#   port list | where state == LISTEN
#   port list | where proto == "UDP"
#   port list | where port == 8080
# UDP sockets have no state, so their `state` is null.
export def "port list" [] {
    let args = ["-n" "-P" "-w" "+c" "0" "-F" "pcPunT" "-T" "s" "-iTCP" "-iUDP"]

    let rows = (lsof-rows $args)
    if ($rows | is-empty) {
        return []
    }

    let users = ($rows | get uid | uniq | uid-to-user)
    $rows
    | update uid {|row| $users | get ($row.uid | into string) }
    | rename --column { uid: user }
    | sort-by port pid
    | select proto address port remote_address remote_port state pid process user
}
