# Convert an epoch timestamp to a local datetime, or get the current time as
# an epoch timestamp.
#
# With no value (and nothing piped in), returns the current time as an int in
# the chosen unit (default: seconds).
#
# With a value (as an argument or piped in), converts it to a local datetime.
# The unit comes from -s/-m/-u/-n, or is guessed from the number of digits:
# <=10 seconds, <=13 millis, <=16 micros, else nanos.
export def main [
    value?: string # epoch timestamp to convert; omit for the current time
    --seconds (-s) # seconds (10 digits)
    --millis (-m) # milliseconds (13 digits)
    --micros (-u) # microseconds (16 digits)
    --nanos (-n) # nanoseconds (19 digits)
] {
    let flags = [$seconds $millis $micros $nanos] | where {|f| $f } | length
    if $flags > 1 {
        error make { msg: "Pass only one of --seconds, --millis, --micros, or --nanos" }
    }

    let explicit_unit = if $nanos { "ns" } else if $micros { "us" } else if $millis { "ms" } else if $seconds { "s" }

    let input = $in
    let raw = if $value != null {
        $value
    } else if ($input | describe) != "nothing" {
        $input | into string | str trim
    } else {
        null
    }

    if $raw == null or $raw == "" {
        let ns = date now | into int
        return (match $explicit_unit {
            "ns" => $ns
            "us" => ($ns // 1_000)
            "ms" => ($ns // 1_000_000)
            _ => ($ns // 1_000_000_000)
        })
    }

    if not ($raw =~ '^[0-9]+$') {
        error make { msg: $"Invalid epoch time: '($raw)' \(expected digits only\)" }
    }

    let unit = if $flags == 0 {
        let digits = $raw | str length
        if $digits <= 10 { "s" } else if $digits <= 13 { "ms" } else if $digits <= 16 { "us" } else { "ns" }
    } else {
        $explicit_unit
    }

    let ns = match $unit {
        "s" => (($raw | into int) * 1_000_000_000)
        "ms" => (($raw | into int) * 1_000_000)
        "us" => (($raw | into int) * 1_000)
        _ => ($raw | into int)
    }

    $ns | into datetime --timezone local
}
