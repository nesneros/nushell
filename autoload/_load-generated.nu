# Sources generated/ files, in order. Leading `_` sorts this first in autoload.
const mise_init_file = ($nu.default-config-dir | path join "generated" "mise.nu")
source $mise_init_file

# Run now so later autoload files, including the init.nu sourced below, see
# mise's tool bins on PATH.
mise_hook

const generated_init_file = ($nu.default-config-dir | path join "generated" "init.nu")
source $generated_init_file

# Unlike init.nu above, this one isn't guaranteed to exist — setup.nu skips
# writing it when completion_commands is empty or none of it is installed.
const completions_file = ($nu.default-config-dir | path join "generated" "completions.nu")
const completions_init = (
    if ($completions_file | path exists) {
        ($completions_file | path expand)
    } else {
        null
    }
)
source $completions_init
