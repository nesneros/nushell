# `copyselection` only fills Reedline's cut buffer. This build has no
# system-clipboard edit commands, so copy the whole line with pbcopy.
const copy_buffer_keybinding = {
    name: copy_buffer
    modifier: control
    keycode: char_p
    mode: [emacs vi_insert vi_normal]
    event: { send: executehostcommand cmd: "(commandline | into binary) | ^pbcopy" }
}

$env.config.keybindings ++= [$copy_buffer_keybinding]