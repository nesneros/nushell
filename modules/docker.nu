# Docker commands with structured output.
#
# Each extern below is annotated with `@structured` (see `help "attr
# structured"`), which makes Nushell ask Docker for machine-readable output and
# decode it whenever the output is used by Nushell itself — piped into an
# internal command, collected into a variable, etc. Printing the command, or
# sending its output to a file/external command, still runs it as written, so
# the normal human-readable output is untouched. Prefix a call with `^` to
# always run it as written.
#
# Docker's JSON field names are PascalCase (`CreatedAt`, `CPUPerc`, ...). The
# decoders below normalize them to snake_case (`created_at`, `cpu_perc`) for a
# more Nushell-ish table.
#
# Caveat: `@structured` puts its arguments *before* the ones you pass, so a
# conflicting flag of your own wins — `docker ps --format '{{.ID}}'` or
# `docker images -q` piped into a command cannot be decoded. Use `^docker ps
# --format ...` for those, or `| collect` to force decoding of a normal call.

# Docker's JSON keys are PascalCase; a naive camel-case split mangles a few
# acronyms, so those are listed explicitly.
const docker_key_overrides = {
    IPv6: "ipv6"
    PIDs: "pids"
}

def docker-normalize-key [key: string] {
    let override = ($docker_key_overrides | get -o $key)
    if $override != null {
        $override
    } else {
        $key
        | str replace --all --regex '([a-z0-9])([A-Z])' '${1}_${2}'
        | str replace --all --regex '([A-Z]+)([A-Z][a-z])' '${1}_${2}'
        | str lowercase
    }
}

# Rewrite a record's top-level keys to snake_case. Nested records are left
# alone: in `docker inspect` they contain user data (label and network names)
# that must not be renamed.
def docker-normalize-columns [] {
    transpose key value
    | each {|col| {key: (docker-normalize-key $col.key), value: $col.value} }
    | transpose --ignore-titles --header-row --as-record
}

# Decode the one-JSON-object-per-line output of `docker ... --format json`.
def docker-from-jsonl [] {
    lines
    | where {|line| $line | is-not-empty }
    | each {|line| $line | from json | docker-normalize-columns }
}

# List containers, as a table when piped:
#   docker ps | where state == running
#   docker ps -a | select names image state status
#
# Keys: `id`, `names`, `image`, `command`, `created_at`, `running_for`,
# `ports`, `state`, `status`, `health_status`, `size`, `labels`,
# `local_volumes`, `mounts` and `networks`.
@structured [--format json] { $in | docker-from-jsonl }
export extern "docker ps" []

@structured [--format json] { $in | docker-from-jsonl }
export extern "docker container ls" []

@structured [--format json] { $in | docker-from-jsonl }
export extern "docker container list" []

@structured [--format json] { $in | docker-from-jsonl }
export extern "docker container ps" []

# List images, as a table when piped:
#   docker images | where repository == nginx
#   docker images | sort-by size --reverse
#
# Keys: `id`, `repository`, `tag`, `digest`, `created_at`, `created_since`,
# `size`, `shared_size`, `unique_size`, `virtual_size` and `containers`.
@structured [--format json] { $in | docker-from-jsonl }
export extern "docker images" []

@structured [--format json] { $in | docker-from-jsonl }
export extern "docker image ls" []

@structured [--format json] { $in | docker-from-jsonl }
export extern "docker image list" []

# List volumes, as a table when piped:
#   docker volume ls | where driver == local
#
# Keys: `name`, `driver`, `scope`, `mountpoint`, `labels`, `links` and `size`.
@structured [--format json] { $in | docker-from-jsonl }
export extern "docker volume ls" []

@structured [--format json] { $in | docker-from-jsonl }
export extern "docker volume list" []

# List networks, as a table when piped:
#   docker network ls | where name != bridge
#
# Keys: `id`, `name`, `driver`, `scope`, `created_at`, `labels`, `ipv6` and
# `internal`; Docker reports the last two as strings ("true" / "false"), not
# booleans.
@structured [--format json] { $in | docker-from-jsonl }
export extern "docker network ls" []

@structured [--format json] { $in | docker-from-jsonl }
export extern "docker network list" []

# List contexts, as a table when piped:
#   docker context ls | where current
#
# Keys include `name`, `description`, `docker_endpoint`, `current`,
# `orchestrator` and `error`.
@structured [--format json] { $in | docker-from-jsonl }
export extern "docker context ls" []

@structured [--format json] { $in | docker-from-jsonl }
export extern "docker context list" []

# One-shot container stats (`--no-stream` is injected so a piped call does not
# hang forever). Printing `docker stats` directly still streams as usual.
#   docker stats | sort-by --reverse cpu_perc
#   docker stats | where mem_perc > 10
#
# Keys: `container`, `name`, `id`, `cpu_perc`, `mem_usage`, `mem_perc`,
# `net_io`, `block_io` and `pids`.
@structured [--no-stream --format json] { $in | docker-from-jsonl }
export extern "docker stats" []

@structured [--no-stream --format json] { $in | docker-from-jsonl }
export extern "docker container stats" []

# Disk usage per object type (keys: `type`, `total_count`, `active`, `size`,
# `reclaimable`). With `--verbose` Docker emits a single object with nested
# arrays instead of one row per type.
@structured [--format json] { $in | docker-from-jsonl }
export extern "docker system df" []

# Containers in the current Compose project (JSON Lines, as for `docker ps`).
@structured [--format json] { $in | docker-from-jsonl }
export extern "docker compose ps" []

# Low-level object details, as an array of records:
#   docker inspect web | get 0.state.Status
#   docker inspect web | get 0.config.Image
#
# Docker already prints JSON (an array, even for one object), so no formatting
# flag is needed. Only top-level keys are normalized; nested records keep
# Docker's own field names (`State.Status`, `Config.Image`, ...) because they
# also contain user-defined keys such as label and network names.
@structured [] { $in | from json | each {|row| $row | docker-normalize-columns } }
export extern "docker inspect" []

# Client and daemon versions as a record, with nested records left as Docker
# emits them:
#   docker version | get client.Version
#   docker version | get server.Os
#
# Top-level keys are `client` and `server`.
@structured [--format json] { $in | from json | docker-normalize-columns }
export extern "docker version" []

# Daemon information as a record:
#   docker info | get server_version
#   docker info | get containers
@structured [--format json] { $in | from json | docker-normalize-columns }
export extern "docker info" []
