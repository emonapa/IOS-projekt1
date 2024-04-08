#!/bin/sh

# Default command
COMMAND="list"
USER=""
filtered_logs=""
log_exist=0

validate_date() {
    date_str="$1"
    if [ "$(echo "$date_str" | awk -F'[- :]+' '{
        # Checking if there are exactly 6 items
        if(NF == 6 &&
            # Checking if all items are number
            $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ &&
            $3 ~ /^[0-9]+$/ && $4 ~ /^[0-9]+$/ &&
            $5 ~ /^[0-9]+$/ && $6 ~ /^[0-9]+$/ &&
            # Checking that the limits for the month, day, hour, minute and second are respected
            $2 <= 12 && $3 <= 31 && $4 < 24 &&
            $5 < 60 && $6 < 60)
            print "valid"; 
        else
            print "invalid"
    }')" = "invalid" ]; then
        echo "Date $date_str is incorrectly formatted." >&2
        exit 1
    fi

}

print_help() {
    echo "Usage: $0 [-h|--help] [FILTER] [COMMAND] USER LOG [LOG2 ...]"
    echo "Options:"
    echo "•      COMMAND can be one of: list, list-currency, status, profit"
    echo "•      FILTER can be a combination of: -a DATETIME, -b DATETIME, -c CURRENCY"
    echo "•      -h, --help: Print this help message"
}

filter_single_log() {
    file="$1"
    user="$2"
    after="$3"
    before="$4"
    currency="$5"
    command=""
    case $file in
        *.gz)
            command="gunzip -c \"$file\""
            ;;
        *)
            command="cat \"$file\""
            ;;
    esac

    [ -n "$user" ] && command=" $command | grep \"^$user\""
    [ -n "$after" ] && command=" $command | awk -F';' -v after=\"$after\" '{ if (\$2 > after) print}'"
    [ -n "$before" ] && command=" $command | awk -F';' -v before=\"$before\" '{ if (\$2 < before) print }'"
    [ -n "$currency" ] && command=" $command | grep \";$currency;\""
    eval "$command" 
}

# Processing arguments
while [ $# -gt 0 ]; do
    case $1 in
        -h|--help)
            print_help
            exit 0
            ;;
        list|list-currency|status|profit)
            COMMAND=$1
            shift
            ;;
        -a)
            AFTER=$2
            validate_date "$AFTER"
            shift 2
            ;;
        -b)
            BEFORE=$2
            validate_date "$BEFORE"
            shift 2
            ;;
        -c)
            CURRENCY=$2
            shift 2
            ;;
        *.gz)
            if gzip -t "$1" > /dev/null 2>&1; then
                if gunzip -t "$1" > /dev/null 2>&1; then
                    filtered_logs="${filtered_logs}$(filter_single_log "$1" "$USER" "$AFTER" "$BEFORE" "$CURRENCY")\n"
                    shift
                else
                    echo "$1 cannot be successfully unzipped." >&2
                    exit 1
                fi
            else
                echo "$1 is not a valid .gz compressed file." >&2
                exit 1
            fi
            ;;
        *)
            if [ -f "$1" ]; then
                log_exist=1
                filtered_logs="${filtered_logs}$(filter_single_log "$1" "$USER" "$AFTER" "$BEFORE" "$CURRENCY")\n"
                shift
            else
                if [ -z "$USER" ]; then
                    USER=$1
                    shift
                else
                    echo "Unknown argument: $1" >&2
                    exit 1
                fi
            fi  
            ;;
    esac
done

if [ "$log_exist" -eq 0 ]; then
    echo "USER and LOG must be specified." >&2
    exit 1
fi

# TODO remove this 
# Code generates \n on the first line
filtered_logs=$(echo "$filtered_logs" | tail -n +1) # Delete first line
# Checking if filtered_logs is empty
if [ -z "$filtered_logs" ] || [ -z "$USER" ]; then
    exit 0
fi

# Performing command
case $COMMAND in
    list)
        echo "$filtered_logs"
        ;;

    list-currency)
        echo "$filtered_logs" | awk -F';' '{print $3}' | sort -u
        ;;

    status)
        echo "$filtered_logs" | \
        awk -F';' '{sum[$3] += $4} END {for (currency in sum) printf "%s : %.4f\n", currency, sum[currency]}' | \
        sort
        ;;

    profit)

        if [ -z "$XTF_PROFIT" ]; then
            XTF_PROFIT=20
        fi

        if ! [ "$XTF_PROFIT" -ge 0 ] 2>/dev/null; then
            echo "XTF_PROFIT [$XTF_PROFIT] is a negative or non-integer number" >&2
            exit 1
        fi

        echo "$filtered_logs" | \
        awk -F';' -v profit_env="$XTF_PROFIT" '{
            sum[$3] += $4
        } END {
            for (currency in sum) {
                if (sum[currency] > 0) {
                    printf "%s : %.4f\n", currency, sum[currency] * (1 + profit_env / 100)
                } else {
                    printf "%s : %.4f\n", currency, sum[currency]
                }
            }
        }' | \
        sort
        ;;

    *)
        echo "Unknown command: $COMMAND" >&2
        print_help
        exit 1
        ;;    
esac
exit 0
