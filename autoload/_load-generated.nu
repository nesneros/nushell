# Sources generated/ files, in order. Leading `_` sorts this first in autoload.
const mise_init_file = ($nu.default-config-dir | path join "generated" "mise.nu")
source $mise_init_file

# Run now so later autoload files, including the init.nu sourced below, see
# mise's tool bins on PATH.
mise_hook

const generated_init_file = ($nu.default-config-dir | path join "generated" "init.nu")
source $generated_init_file
