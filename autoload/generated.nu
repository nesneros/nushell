# Sources generated/init.nu. autoload/_mise.nu sorts first, so mise's
# PATH snapshot is already applied.
const generated_init_file = ($nu.default-config-dir | path join "generated/init.nu")
const generated_init = (
    if ($generated_init_file | path exists) {
        ($generated_init_file | path expand)
    } else {
        null
    }
)
source $generated_init
