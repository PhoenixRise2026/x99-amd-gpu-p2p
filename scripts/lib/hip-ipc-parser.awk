# SPDX-License-Identifier: MIT

function commit_case() {
    if (!in_case) return
    if (source_gpu == 0 && destination_gpu == 1) {
        cases_01++
        if (!case_forward_read || !case_reverse_write) failed_cases++
    } else if (source_gpu == 1 && destination_gpu == 0) {
        cases_10++
        if (!case_forward_read || !case_reverse_write) failed_cases++
    }
    in_case = 0
}

BEGIN {
    source_gpu = -1
    destination_gpu = -1
    case_forward_read = 0
    case_reverse_write = 0
    cases_01 = 0
    cases_10 = 0
    failed_cases = 0
    in_case = 0
    explicit_failure = 0
}

/^DIRECTION:[ \t]*GPU[ \t]*[0-9]+.*->[ \t]*GPU[ \t]*[0-9]+/ {
    commit_case()
    line = $0
    sub(/^.*DIRECTION:[ \t]*GPU[ \t]*/, "", line)
    split(line, pair, /[ \t]*->[ \t]*GPU[ \t]*/)
    source_gpu = pair[1] + 0
    destination_gpu = pair[2] + 0
    next
}

/^\[Test[ \t]+[0-9]+\]/ {
    commit_case()
    in_case = 1
    case_forward_read = 0
    case_reverse_write = 0
    next
}

in_case && tolower($0) ~ /forward read verify:[ \t]*pass/ { case_forward_read = 1 }
in_case && tolower($0) ~ /reverse write verify:[ \t]*pass/ { case_reverse_write = 1 }
in_case && tolower($0) ~ /(forward read|reverse write) verify:[ \t]*fail/ { explicit_failure = 1 }

END {
    commit_case()
    if (explicit_failure || failed_cases > 0) print "FAIL"
    else if (cases_01 > 0 && cases_10 > 0) print "PASS"
    else print "INCONCLUSIVE"
}
