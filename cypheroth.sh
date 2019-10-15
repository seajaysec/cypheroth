#!/usr/bin/env bash

# Check if required tool cypher-shell is installed
cypher-shell -v foo >/dev/null 2>&1 || {
    echo >&2 "cypher-shell required, but not installed.  Aborting."
    exit 1
}

USAGE="
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
  -v    Verbose mode (Optional) (Default:FALSE)
  -h	Help text and usage example (Optional)

Example: ./cypheroth.sh -u neo4j -p neo4jj -d testlab.local -v true

Files are added to the ./cypherout directory
"

# Check if any flags were set. If not, print out help.
if [ $# -eq 0 ]; then
    echo "$USAGE"
    exit
fi

# Initial variable state
VERBOSE='FALSE'

# Flag configuration
while getopts "u:p:d:v:h" FLAG; do
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
    v)
        VERBOSE=$OPTARG
        ;;
    h)
        echo "$USAGE"
        exit
        ;;
    *)
        echo "$USAGE"
        exit
        ;;
    esac
done

# Make sure each required flag was actually set.
if [ -z ${USERNAME+x} ]; then
    echo "Username flag (-u) is not set."
    echo "$USAGE"
    exit
elif [ -z ${PASSWORD+x} ]; then
    echo "Password flag (-p) is not set."
    echo "$USAGE"
    exit
elif [ -z ${DOMAIN+x} ]; then
    echo "User domain flag (-f) is not set."
    echo "$USAGE"
    exit
fi

# Make sure $DOMAIN is UpperCase
DOMAIN=${DOMAIN^^}

# Make sure $VERBOSE is UpperCase
VERBOSE=${VERBOSE^^}

# Create output dir
mkdir ./cypherout 2>/dev/null

# Sanitize cypher queries
sed -i '/^$/d' ./queries.txt

# Set aliases
n4jV="cypher-shell -u $USERNAME -p $PASSWORD --format verbose"
n4jP="cypher-shell -u $USERNAME -p $PASSWORD --format plain"

# The meat and potatoes
cat queries.txt | while read line; do
    DESCRIPTION=$(echo $line | cut -d ';' -f 1)
    QUERY=$(echo $line | cut -d ';' -f 2)
    OUTPUT=$(echo $line | cut -d ';' -f 3)
    echo -e "\e[1m$DESCRIPTION\e[22m"
    if [ "$VERBOSE" == "TRUE" ]; then
        tput rmam
        $n4jV "$QUERY" | sed \$d
        tput smam
    fi
    $n4jP "$QUERY" >./cypherout/$OUTPUT
    echo -e "\e[3mSaved to ./cypherout/$OUTPUT\e[23m\n"
done

echo 'Removing empty output files'
find ./cypherout/* -type f -empty -delete

# If ssconvert is installed, join all .csv output to .xls
if which ssconvert >/dev/null; then
    ssconvert --merge-to=./cypherout/all.xls ./cypherout/*.csv
    echo -e "\e[1mAll CSVs joined to ./cypherout/all.xls\e[22m"
    echo
else
    echo -e "\e[1mInstall ssconvert (apt or brew install gnumeric) to auto-join csv output to sheets in an xls workbook.\e[22m"
fi
