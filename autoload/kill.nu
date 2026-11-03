def "nu-complete pids" [] {
    {
        options: { sort: false, completion_algorithm: fuzzy }
        completions: (
            ps | each {|p| { value: ($p.pid | into string), description: $p.name } }
        )
    }
}

$env.config.menus ++= [{
    name: pid_menu
    only_buffer_difference: false
    marker: "| "
    type: { layout: columnar, columns: 1, col_width: 50, col_padding: 2 }
    style: { text: green, selected_text: green_reverse, description_text: yellow }
    source: { |token|
        let ports = (
            port list | where state == LISTEN | group-by pid | transpose pid rows
            | update rows {|r| $r.rows | get local_port | uniq | sort | str join ","}
        )
        ps | join --left $ports pid | each {|p|
            let port_str = if $p.rows == null { "" } else { $"  port:($p.rows)" }
            {
                value: ($p.pid | into string)
                description: ($p.name + $port_str)
            }
        }
        | where {|p| (
            ($p.description | str contains -i $token.text)
            or ($p.value | str starts-with $token.text)
        ) }
        | each {|p| $p | insert span $token.span }
    }
}]

$env.config.keybindings ++= [{
    name: pid_menu
    modifier: alt
    keycode: char_p
    mode: [emacs vi_insert]
    event: { send: menu name: pid_menu }
}]