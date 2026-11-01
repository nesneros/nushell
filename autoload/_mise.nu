# Sources mise's init, regenerated fresh by config.nu. The leading
# underscore sorts this first in autoload.
const mise_init_file = ($nu.default-config-dir | path join "generated" "mise.nu")
source $mise_init_file

# `mise activate` leaves tool bins off PATH until the pre_prompt hook.
# Run it now so later autoload files, including atuin, can see them.
mise_hook
