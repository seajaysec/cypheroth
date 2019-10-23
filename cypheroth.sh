#!/usr/bin/env bash

# Trap ctrl-c and call ctrl_c(). Exit script
trap ctrl_c INT
ctrl_c() {
        echo -e "\nGot a CTRL-C. Stopping script."
        # Remove VM from config just in case
        modify_config $vmname
        print_failure
        exit 0
}

# Check if required tool cypher-shell is installed
cypher-shell -v foo >/dev/null 2>&1 || {
    echo >&2 "cypher-shell required, but not installed.  Aborting."
    exit 1
}

USAGE="
                    __                    __  __  
  _______  ______  / /_  ___  _________  / /_/ /_ 

/ /__/ /_/ / /_/ / / / /  __/ /  / /_/ / /_/ / / /
\___/\__, / .___/_/ /_/\___/_/   \____/\__/_/ /_/ 
    /____/_/                                      

Flags:
  -u	Neo4J Username (Required)
  -p	Neo4J Password (Required)
  -d	Fully Qualified Domain Name (Required)
  -a	Bolt address (Optional. Default: bolt://localhost:7687)
  -v    Verbose mode - Show first 15 lines of output (Optional) (Default:FALSE)
  -h	Help text and usage example (Optional)

Example: ./cypheroth.sh -u neo4j -p bloodhound -a bolt://10.0.0.1:7687 -d testlab.local -v true

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
    echo "User domain flag (-d) is not set."
    echo "$USAGE"
    exit
fi

# Make sure $DOMAIN is UpperCase
DOMAIN=${DOMAIN^^}

# Make sure $VERBOSE is UpperCase
VERBOSE=${VERBOSE^^}

# Create output dir
mkdir ./cypherout 2>/dev/null

# Set alias
n4jP="cypher-shell -u $USERNAME -p $PASSWORD -a $ADDRESS --format plain" 

# The meat and potatoes
awk 'NF' queries.txt | while read line; do
    DESCRIPTION=$(echo $line | cut -d ';' -f 1)
    QUERY=$(echo $line | cut -d ';' -f 2)
    OUTPUT=$(echo $line | cut -d ';' -f 3)
    echo -e "\e[3m$DESCRIPTION\e[23m"
    $n4jP "$QUERY" >./cypherout/$OUTPUT
    if [ "$VERBOSE" == "TRUE" ]; then
        tput rmam
        column -s, -t ./cypherout/$OUTPUT | head -n 15 2>/dev/null
        tput smam
        echo -e "\e[1mSaved to ./cypherout/$OUTPUT\e[22m\n"
    fi
done

echo 'Removing empty output files'
find . -type f -size 0 -print0 | xargs -I{} -0 rm {}

# If ssconvert is installed, join all .csv output to .xls
if which ssconvert >/dev/null; then
    ssconvert --merge-to=./cypherout/all.xls ./cypherout/*.csv 2>/dev/null
    echo -e "\e[1mAll CSVs joined to ./cypherout/all.xls\e[22m"
    echo
else
    echo -e "\e[1mInstall ssconvert (apt or brew install gnumeric) to auto-join csv output to sheets in an xls workbook.\e[22m"
fi
