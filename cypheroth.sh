#!/usr/bin/env bash

toolCheck() {
    # Check if required tool cypher-shell is installed
    cypher-shell -v >/dev/null 2>&1 || {
        echo >&2 "cypher-shell required, but not installed.  Aborting."
        exit 1
    }
}

usage() {
    echo "
                        __                    __  __  
    _______  ______  / /_  ___  _________  / /_/ /_ 
    / ___/ / / / __ \\/ __ \/ _ \/ ___/ __ \\/ __/ __ \\
    / /__/ /_/ / /_/ / / / /  __/ /  / /_/ / /_/ / / /
    \___/\__, / .___/_/ /_/\___/_/   \____/\__/_/ /_/ 
        /____/_/                                      

    Flags:
    -u	Neo4J Username (Required)
    -p	Neo4J Password (Required)
    -d	Fully Qualified Domain Name (Required)
    -v    Verbose mode - Show first 15 lines of output (Optional) (Default:FALSE)
    -h	Help text and usage example (Optional)

    Example: ./cypheroth.sh -u neo4j -p neo4jj -d testlab.local  -a localhost:7687 -v true

    Files are added to the ./cypherout directory
"
    exit 1
}

flagChecks() {
    # Make sure each required flag was actually set.
    if [ -z ${USERNAME+x} ]; then
        echo "Username flag (-u) is not set."
        usage
    elif [ -z ${PASSWORD+x} ]; then
        echo "Password flag (-p) is not set."
        usage
    elif [ -z ${DOMAIN+x} ]; then
        echo "User domain flag (-d) is not set."
        usage
    fi
}

prepWork() {
    # Make sure $DOMAIN is UpperCase
    DOMAIN=${DOMAIN^^}
    # Make sure $VERBOSE is UpperCase
    VERBOSE=${VERBOSE^^}
    # Create output dir
    mkdir ./cypherout 2>/dev/null
    # Set alias
    n4jP="cypher-shell -u $USERNAME -p $PASSWORD -a $ADDRESS --format plain"
}

connCheck() {
    # Connection check
    TEST=$(cypher-shell -u "$USERNAME" -p "$PASSWORD" -a "$ADDRESS" --format plain "MATCH (n) RETURN CASE WHEN count(n) > 0 THEN 'Connected' ELSE 'Not Connected' END" 2>&1 | tail -n 1)
    if [[ "$TEST" =~ "refused" ]]; then
        echo "🅇 Neo4j not started."
        echo "Quitting Cypheroth."
        exit 1
    elif [[ "$TEST" =~ "Not" ]]; then
        echo "☑ Neo4j started"
        echo "🅇 Database is not connected."
        echo "Quitting Cypheroth."
        exit 1
    elif [[ "$TEST" =~ "Connected" ]]; then
        echo "☑ Neo4j started"
        echo "☑ Connected to the database."
        echo -e "Running Cypheroth queries.\n"
        runQueries
    else
        echo "Unknown error:"
        echo "$TEST"
        exit 1
    fi
}

runQueries() {
    # The meat and potatoes
    awk 'NF' queries.txt | while read -r line; do
        DESCRIPTION=$(echo "$line" | cut -d ';' -f 1)
        QUERY=$(echo "$line" | cut -d ';' -f 2)
        OUTPUT=$(echo "$line" | cut -d ';' -f 3)
        echo -e "\e[3m$DESCRIPTION\e[23m"
        $n4jP "$QUERY" >./cypherout/"$OUTPUT"
        if [ "$VERBOSE" == "TRUE" ]; then
            tput rmam
            column -s, -t ./cypherout/"$OUTPUT" | head -n 15 2>/dev/null
            tput smam
            echo -e "\e[1mSaved to ./cypherout/$OUTPUT\e[22m\n"
            trap ctrlC SIGINT
        fi
    done
}

endJobs() {
    echo 'Removing empty output files'
    find . -type f -size 0 -print0 | xargs -I{} -0 rm {}

    # If ssconvert is installed, join all .csv output to .xls
    if ssconvert --version >/dev/null; then
        ssconvert --merge-to=./cypherout/all.xls ./cypherout/*.csv 2>/dev/null
        echo -e "\e[1mAll CSVs joined to ./cypherout/all.xls\e[22m"
        echo
    else
        echo -e "\e[1mInstall ssconvert (apt or brew install gnumeric) to auto-join csv output to sheets in an xls workbook.\e[22m"
    fi
}

ctrlC() {
    echo "Caught Ctrl-C. Quitting Cypheroth."
    exit 1
}

# Check if any flags were set. If not, print out help.
if [ $# -eq 0 ]; then
    usage
fi
# Initial variable states
VERBOSE='FALSE'
ADDRESS='127.0.0.1:7687'

# Flag configuration
while getopts "u:p:d:a:v:h" FLAG; do
    case $FLAG in
    u)
        USERNAME=$OPTARG
        ;;
    p)
        PASSWORD=$OPTARG
        ;;
    d)
        DOMAIN=$OPTARG
        ;;
    a)
        ADDRESS=$OPTARG
        ;;
    v)
        VERBOSE=$OPTARG
        ;;
    h)
        usage
        ;;
    *)
        usage
        ;;
    esac
done

toolCheck
flagChecks
prepWork
connCheck
endJobs
