# Sources mise's init, regenerated fresh by config.nu. Lives here because
# autoload loads after config.nu, so the file already exists by then.
const mise_init_file = ($nu.default-config-dir | path join "generated/mise.nu")
const mise_init = (
    if ($mise_init_file | path exists) {
        ($mise_init_file | path expand)
    } else {
        null
    }
)
source $mise_init
