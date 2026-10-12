# SPDX-License-Identifier: MIT

function trim(value) {
    sub(/^[ \t\r\n]+/, "", value)
    sub(/[ \t\r\n]+$/, "", value)
    return value
}

function is_positive_number(value) {
    value = trim(value)
    return value ~ /^([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$/ && value + 0 > 0
}

function note_cell(src_type, src_id, dst_type, dst_id, bandwidth) {
    if (!is_positive_number(bandwidth)) return
    if (src_type == "GPU" && dst_type == "GPU") {
        if (src_id == 0 && dst_id == 1) forward = 1
        else if (src_id == 1 && dst_id == 0) reverse = 1
        else if (src_id == dst_id) self_seen = 1
        else peer_other_seen = 1
    } else {
        cpu_seen = 1
    }
}

function parse_direction(text, parts, count) {
    if (!match(text, /GPU[ \t]*[0-9]+[ \t]*->[ \t]*GPU[ \t]*[0-9]+/)) return 0
    text = substr(text, RSTART, RLENGTH)
    gsub(/GPU[ \t]*/, "", text)
    count = split(text, parts, /[ \t]*->[ \t]*/)
    if (count != 2 || parts[1] !~ /^[0-9]+$/ || parts[2] !~ /^[0-9]+$/) return 0
    list_src = parts[1] + 0
    list_dst = parts[2] + 0
    return 1
}

BEGIN {
    forward = 0
    reverse = 0
    self_seen = 0
    cpu_seen = 0
    peer_other_seen = 0
    in_matrix = 0
    num_destinations = 0
    list_src = -1
    list_dst = -1
    csv_schema = 0
    csv_unrecognized = 0
}

# TransferBench matrix header, for example: SRC+EXE\DST   GPU 00   GPU 01
/SRC.*DST/ {
    in_matrix = 1
    num_destinations = 0
    remainder = $0
    position = 1
    while (position <= length(remainder) && match(substr(remainder, position), /(GPU|CPU)[ \t]*[0-9]+/)) {
        token = substr(remainder, position + RSTART - 1, RLENGTH)
        kind = token
        sub(/[ \t]*[0-9]+$/, "", kind)
        sub(/^(GPU|CPU)[ \t]*/, "", token)
        num_destinations++
        matrix_dst_type[num_destinations] = kind
        matrix_dst_id[num_destinations] = token + 0
        position += RSTART + RLENGTH - 1
    }
    next
}

# Matrix rows contain one bandwidth cell per destination after the arrow.
in_matrix && /^[ \t]*(GPU|CPU)[ \t]*[0-9]+[ \t]*->/ {
    row = $0
    arrow = index(row, "->")
    source = substr(row, 1, arrow - 1)
    cells_text = substr(row, arrow + 2)
    source_type = source
    sub(/^[ \t]*/, "", source_type)
    sub(/[ \t]*[0-9]+[ \t]*$/, "", source_type)
    sub(/^[ \t]*(GPU|CPU)[ \t]*/, "", source)
    sub(/[ \t]*->.*$/, "", source)
    source_id = source + 0
    cells_text = trim(cells_text)
    count = split(cells_text, cells, /[ \t]+/)
    for (i = 1; i <= count && i <= num_destinations; i++)
        note_cell(source_type, source_id, matrix_dst_type[i], matrix_dst_id[i], cells[i])
    next
}

# Accept CSV only with this exact, self-describing header. The documented
# TransferBench output formats are matrix and flat-table; unknown CSV stays
# inconclusive instead of guessing which numeric column represents bandwidth.
{
    header = tolower($0)
    gsub(/[ \t\r]/, "", header)
    if (header == "source,destination,executor,bytes,seconds,bandwidth_gbps") {
        csv_schema = 1
        next
    }
}

# CSV schema: source,destination,executor,bytes,seconds,bandwidth_GBps.
# Only the header-named bandwidth field counts; bytes/time are validated separately.
/^[ \t]*(GPU|CPU)[0-9]+,[ \t]*(GPU|CPU)[0-9]+,/ {
    count = split($0, fields, ",")
    if (csv_schema && count == 6) {
        source_field = trim(fields[1])
        destination_field = trim(fields[2])
        source_type = source_field ~ /^GPU/ ? "GPU" : "CPU"
        destination_type = destination_field ~ /^GPU/ ? "GPU" : "CPU"
        source_id = source_field
        destination_id = destination_field
        sub(/^[ \t]*(GPU|CPU)/, "", source_id)
        sub(/^[ \t]*(GPU|CPU)/, "", destination_id)
        bytes = trim(fields[4])
        seconds = trim(fields[5])
        bandwidth = trim(fields[6])
        if (source_id ~ /^[0-9]+$/ && destination_id ~ /^[0-9]+$/ &&
            bytes ~ /^[0-9]+$/ && bytes + 0 > 0 && is_positive_number(seconds))
            note_cell(source_type, source_id + 0, destination_type, destination_id + 0, bandwidth)
        else
            csv_unrecognized = 1
    } else {
        csv_unrecognized = 1
    }
    next
}

# List output: only an Avg value within a named directional case counts.
/(Case:[ \t]*)?(dma|push|pull)_[0-9]+_to_[0-9]+|DIRECTION:[ \t]*GPU[ \t]*[0-9]+[ \t]*->[ \t]*GPU[ \t]*[0-9]+/ {
    list_src = -1
    list_dst = -1
    if (parse_direction($0)) {
        # Parsed an explicit GPU source and destination.
    } else if (match($0, /(dma|push|pull)_[0-9]+_to_[0-9]+/)) {
        direction = substr($0, RSTART, RLENGTH)
        sub(/^(dma|push|pull)_/, "", direction)
        split(direction, parts, "_to_")
        list_src = parts[1] + 0
        list_dst = parts[2] + 0
    }
    next
}

list_src >= 0 && list_dst >= 0 && /Avg:[ \t]*[0-9.]+[ \t]*GB\/s/ {
    line = $0
    sub(/^.*Avg:[ \t]*/, "", line)
    if (match(line, /^([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?/)) {
        bandwidth = substr(line, RSTART, RLENGTH)
        note_cell("GPU", list_src, "GPU", list_dst, bandwidth)
    }
}

END {
    if (forward && reverse) print "PASS"
    else if (forward || reverse || self_seen || cpu_seen || peer_other_seen || csv_unrecognized) print "INCONCLUSIVE"
    else print "FAIL"
}
