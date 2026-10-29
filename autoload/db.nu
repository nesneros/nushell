def "nu-complete db-tables" [buffer: string] {
    let file = (
        $buffer
        | split row " "
        | where {|w| $w =~ '\.(sqlite|db)$'}
        | first
        | path expand
    )
    open $file | columns
}

def "db get-table" [file: path, table: string@"nu-complete db-tables"] {
    open $file | get $table
}

def summarize-binary [] {
    update cells {|v|
        if ($v | describe) == "binary" { $"<($v | bytes length) bytes: ($v | bytes at 0..3 | encode hex)...>" } else { $v }
    }
}