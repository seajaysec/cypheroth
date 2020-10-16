#!/usr/bin/env bash

toolCheck() {
    # Check if required tool cypher-shell is installed
    cypher-shell -v >/dev/null 2>&1 || {
        echo >&2 "cypher-shell required, but not installed.  Aborting."
        exit 1
    }
    # Carry on to flagChecks function
    flagChecks
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
    -a	Bolt address (Optional) (Default: localhost:7687)
    -t  Query Timeout (Optional) (Default: 30s)
    -v  Verbose mode (Optional) (Default:FALSE)
    -h	Help text and usage example (Optional)

    Example with Defaults:
    ./cypheroth.sh -u neo4j -p BloodHound -d TESTLAB.LOCAL

    Example with All Options:
    ./cypheroth.sh -u neo4j -p hunter2 -d bigtech.corp -a 10.0.0.1:7687 -t 5m -v true

    Files are added to a subdirectory named after the FQDN.
    
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
    # Continue on to prepWork function
    prepWork
}

prepWork() {
    # Make sure $VERBOSE is UpperCase
    VERBOSE=$(echo "$VERBOSE" | tr a-z A-Z)
    # Create output dir
    mkdir ./$DOMAIN 2>/dev/null
    # Set alias
    n4jP="cypher-shell -u $USERNAME -p $PASSWORD -a $ADDRESS --format plain"
    # Alias for removing junk character artifacts
    noJunk() {
        tr -d '"' | tr -d '[' | tr -d ']'
    }
    # Carry on to connCheck Function
    connCheck
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
        if [ "$VERBOSE" == "TRUE" ]; then
            echo "☑ Neo4j started"
            echo -e "☑ Connected to the database.\n"
            # Converting all domain properties to uppercase for search consistency
            $n4jP "MATCH (n) SET n.domain = upper(n.domain)"
            echo -e "\nRunning Cypheroth queries."
        fi
        # Carry on to runQueries function
        runQueries
    else
        echo "Error:"
        echo "$TEST"
        exit 1
    fi
}

runQueries() {
    # Reading from queries array
    for line in "${queries[@]}"; do
        # Separating out values from array by ; delineation
        DESCRIPTION=$(echo "$line" | cut -d ';' -f 1)
        QUERY=$(echo "$line" | cut -d ';' -f 2)
        OUTPUT=$(echo "$line" | cut -d ';' -f 3)
        SAVEPATH=./"$DOMAIN"/"$OUTPUT"
        # Information for user
        echo ""
        echo -e "$DESCRIPTION"
        # For up to the timeout length, runs query and saves to savepath
        timeout $TIMEOUT $n4jP "$QUERY" | noJunk >$SAVEPATH
        # If the timeout wasn't reached...
        if [ $? -eq 0 ]; then
            echo -e "Saved to $SAVEPATH"
            # Removes double quotes from output file
            #noJunk <$SAVEPATH 1<>$SAVEPATH
            # If verbosity is enabled...
            if [ "$VERBOSE" == "TRUE" ] && [ -f "$SAVEPATH" ]; then
                echo "Sample:"
                # Disable wordwrap for stdout
                tput rmam
                # Output first 15 lines of output file
                column -s, -t $SAVEPATH | head -n 15 2>/dev/null
                # Re-enable wordwrap for stdout
                tput smam
            fi
            # Show the # of lines in the output file
            if [ -f "$SAVEPATH" ]; then
                echo "Line Count:" $(wc -l <$SAVEPATH)
            fi
        # If the timeout WAS reached...
        else
            echo "**Query Timed Out**" >&2
        fi
        # Check for ctrl-c
        trap ctrlC SIGINT
    done
    # Carry on to endJobs function
    endJobs
}

endJobs() {
    echo -e "\nRemoving empty output files\n"
    # Finds empty files, then uses xargs to remove them - most cross-platform compatible method available
    find ./"$DOMAIN"/ -type f -size 0 -print0 | xargs -I{} -0 rm {}
    # If ssconvert is installed, join all .csv output to .xls
    if command -v ssconvert &>/dev/null; then
        ssconvert --merge-to=./"$DOMAIN"/all.xls ./"$DOMAIN"/*.csv 2>/dev/null
        echo -e "All CSVs joined to ./"$DOMAIN"/all.xls"
        echo
    else
        echo -e "Install ssconvert (apt or brew install gnumeric) to auto-join csv output to sheets in an xls workbook."
    fi
    echo -e "\nScript complete!\n"
    exit
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
TIMEOUT='30s'

# Flag configuration
while getopts "u:p:d:a:t:v:h" FLAG; do
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
    t)
        TIMEOUT=$OPTARG
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

DOMAIN=$(echo "${DOMAIN}" | tr '[a-z]' '[A-Z]')

# Add queries in the following semicolon-delimited format:
# "Description;Cypher Query;Output.csv"
# Example:
# "All Usernames;MATCH (u:User) RETURN u.name;usernames.csv"
#
# If adding a query that requires the Domain value to be set, save it as $DOMAIN.
# Example:
# "All Domain Admins;MATCH (u:User) MATCH (g:Group {name:'DOMAIN ADMINS@$DOMAIN'}) RETURN u.displayname;domainAdmins.csv"
#
# New queries should be added anywhere BUT the first line, which sets the HighValue attribute later used by subsequent queries.
declare -a queries=(
    "All Objects that are members of High Value Groups;MATCH p=(n)-[r:MemberOf*1..]->(m:Group {highvalue:true, domain:'$DOMAIN'}) SET n.highvalue=true RETURN labels(n) AS ObjectType,n.name AS ObjectName,m.name AS HighValueGroupName ORDER BY ObjectType ASC;AllHighValueObjects.csv"
    "All users with SPN in Domain Admin group, with enabled status and unconstrained delegation status displayed;MATCH (u:User {hasspn:true})-[r:MemberOf*1..]->(g:Group {domain:'$DOMAIN'}) WHERE g.objectid ENDS WITH '-512' RETURN u.name AS Username,u.displayname AS DisplayName,u.enabled AS Enabled,u.unconstraineddelegation AS UnconstrainedDelegation;spnDATargets.csv"
    "All Domain Admins;MATCH (u:User)-[r:MemberOf*1..]->(g:Group {domain:'$DOMAIN'}) WHERE g.objectid ENDS WITH '-512' SET u.llInt = coalesce(u.lastlogon,'1') SET u.lldInt = coalesce(u.lldate,'1') SET u.lltsInt = coalesce(u.lastlogontimestamp,'1') SET u.pwdlsInt = coalesce(u.pwdlastset,'1') RETURN u.name AS UserName, u.displayname AS DisplayName, u.domain AS Domain, u.enabled AS Enabled, u.highvalue AS HighValue, u.objectid AS SID, u.description AS Description, u.title AS Title, u.email as Email, datetime({epochSeconds:toInteger(u.llInt)}) AS LastLogon, datetime({epochSeconds:toInteger(u.lldInt)}) AS LLDate, datetime({epochSeconds:toInteger(u.lltsInt)}) AS LLTimeStamp, datetime({epochSeconds:toInteger(u.pwdlsInt)}) AS PasswordLastSet, u.owned AS Owned, u.sensitive AS Sensitive, u.admincount AS AdminCount, u.hasspn AS HasSPN, u.unconstraineddelegation AS UnconstrainedDelegation, u.dontreqpreauth AS DontReqPreAuth, u.passwordnotreqd AS PasswordNotRequired, u.homedirectory AS HomeDirectory, u.serviceprincipalnames AS ServicePrincipalNames;domainAdmins.csv"
    "Kerberoastable users sorted by total machine admin count;MATCH (u:User {hasspn:true, domain:'$DOMAIN'}) OPTIONAL MATCH (u)-[:AdminTo]->(c1:Computer) OPTIONAL MATCH (u)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c2:Computer) WITH u,COLLECT(c1) + COLLECT(c2) AS tempVar UNWIND tempVar AS comps RETURN u.name,u.displayname,u.domain,u.description,u.highvalue,COUNT(DISTINCT(comps)) ORDER BY COUNT(DISTINCT(comps)) DESC;kerbUsersByMachineCount.csv"
    "Kerberoastable users and computers where they are admins;OPTIONAL MATCH (u1:User {domain:'$DOMAIN'}) WHERE u1.hasspn=true OPTIONAL MATCH (u1)-[r:AdminTo]->(c:Computer) RETURN u1.name AS KerberoastableUser,c.name AS LocalAdminComputerName,c.operatingsystem AS OS,c.description AS Description,c.highvalue AS HighValue, c.unconstraineddelegation AS UnconstrainedDelegation;kerbUsersAdminComputers.csv"
    "Users with paths to High Value groups;MATCH (u:User {domain:'$DOMAIN'}) MATCH (g:Group {highvalue:true}) MATCH p = shortestPath((u:User)-[r:AddMember|AdminTo|AllExtendedRights|AllowedToDelegate|Contains|ExecuteDCOM|ForceChangePassword|GenericAll|GenericWrite|GpLink|HasSession|MemberOf|Owns|ReadLAPSPassword|TrustedBy|WriteDacl|WriteOwner|GetChanges|GetChangesAll*1..]->(g)) RETURN DISTINCT(u.name) AS UserName,u.enabled as Enabled, u.description AS Description,count(p) as PathCount order by u.name;UserHVGroupPaths.csv"
    "Users that are not AdminCount 1, have generic all, and no local admin;MATCH (u:User {domain:'$DOMAIN'})-[:GenericAll]->(c:Computer) WHERE NOT u.admincount AND NOT (u)-[:AdminTo]->(c) RETURN u.name,u.displayname,c.name,c.highvalue;specialAdmins.csv"
    "Users that are admin on 1+ machines, sorted by admin count;MATCH (U:User {domain:'$DOMAIN'})-[r:MemberOf|:AdminTo*1..]->(C:Computer) WITH U.name as n, COUNT(DISTINCT(C)) as c WHERE c>0 RETURN n AS UserName, c ORDER BY c DESC;UserAdminCount.csv"
    "Users with Description field populated;MATCH (u:User {domain:'$DOMAIN'}) WHERE NOT u.description IS null RETURN u.name AS UserName ,u.description AS Description;userDescriptions.csv"
    "Users with paths to Domain Controllers;MATCH (u:User), (g:Group {domain:'$DOMAIN'}) WHERE g.objectid ENDS WITH '-516' MATCH p=shortestPath((u)-[*1..]->(g)) RETURN u.name AS UserName,u.displayname AS DisplayName, length(p) AS Hops ORDER BY Hops;UsersWithPathsToDCs.csv"
    # use "CONTAINS" for SID because SharpHound prefixes well-known SIDs by domain name
    # while waiting for https://github.com/BloodHoundAD/SharpHound3/pull/22 to be merged, we cannot use the domain property for EVERYONE and AUTHENTICATED USERS so we also check if the name ends with domain name
    "What permissions does Everyone/Anonymous/Authenticated Users/Users/Domain Users/Domain Computers have;MATCH p=(m:Group)-[r:AddMember|AdminTo|AllExtendedRights|AllowedToDelegate|CanRDP|Contains|ExecuteDCOM|ForceChangePassword|GenericAll|GenericWrite|GetChanges|GetChangesAll|HasSession|Owns|ReadLAPSPassword|SQLAdmin|TrustedBy|WriteDACL|WriteOwner|AddAllowedToAct|AllowedToAct]->(t) WHERE (m.domain='$DOMAIN' OR m.name ENDS WITH '@$DOMAIN') AND (m.objectid ENDS WITH '-513' OR m.objectid ENDS WITH '-515' OR m.objectid CONTAINS 'S-1-5-11' OR m.objectid CONTAINS 'S-1-5-32-545' OR m.objectid CONTAINS 'S-1-1-0' OR m.objectid CONTAINS 'S-1-5-7' OR m.name STARTS WITH 'ANONYMOUS@') RETURN m.name,TYPE(r),t.name,t.enabled,LABELS(t) ORDER BY m.name;interestingPermissions.csv"
    # this query should return that "Domain Users" is member of "Users" but we already know this, so we filter it out
    "Groups where Everyone/Anonymous/Authenticated Users/Users/Domain Users/Domain Computers are members;MATCH (m:Group) WHERE (m.domain='$DOMAIN' OR m.name ENDS WITH '@$DOMAIN') AND (m.objectid ENDS WITH '-513' OR m.objectid ENDS WITH '-515' OR m.objectid CONTAINS 'S-1-5-11' OR m.objectid CONTAINS 'S-1-5-32-545' OR m.objectid CONTAINS 'S-1-1-0' OR m.objectid CONTAINS 'S-1-5-7' OR m.name STARTS WITH 'ANONYMOUS@') WITH collect(m.name) AS groups MATCH p=(n:Group)-[:MemberOf*1..]->(i:Group) WHERE n.name IN groups AND NOT i.name IN groups RETURN n.name,i.name,LENGTH(p) as hops ORDER BY n.name;wideGroupsMemberOfOthers.csv"
    "All objects that can DCSync;MATCH (n1)-[:MemberOf|GetChanges*1..]->(u:Domain {name:'$DOMAIN'}) WITH n1,u MATCH (n1)-[:MemberOf|GetChangesAll*1..]->(u) WITH n1,u MATCH (n1)-[:MemberOf|GetChanges|GetChangesAll*1..]->(u) RETURN distinct(n1.name) as user, LABELS(n1) as ObjectType ORDER BY user;dcsyncers.csv"
    "Number of users who can read LAPS password for each computer;MATCH (u:User)-[:MemberOf*0..]->(Group)-[:AllExtendedRights|ReadLAPSPassword]->(c:Computer {domain:'$DOMAIN'}) WITH c.name as computer, COUNT(DISTINCT(u)) as nb_users WHERE nb_users>0 RETURN computer, nb_users ORDER BY nb_users DESC;NbUsersCanReadLapsPerComputer.csv"
    "Every computer account that has local admin rights on other computers;MATCH (c1:Computer {domain:'$DOMAIN'}) OPTIONAL MATCH (c1)-[:AdminTo]->(c2:Computer) OPTIONAL MATCH (c1)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c3:Computer) WITH COLLECT(c2) + COLLECT(c3) AS tempVar,c1 UNWIND tempVar AS computers RETURN c1.name AS Owner,computers.name AS Ownee;compOwners.csv"
    "Find which domain Groups are Admins to what computers;MATCH (g:Group) OPTIONAL MATCH (g)-[:AdminTo]->(c1:Computer {domain:'$DOMAIN'}) OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c2:Computer {domain:'$DOMAIN'}) WITH g, COLLECT(c1) + COLLECT(c2) AS tempVar UNWIND tempVar AS computers RETURN g.name,g.highvalue,computers.name,computers.highvalue;groupsAdminningComputers.csv"
    "Computer names where each domain user has derivative Admin privileges to;MATCH (u:User)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c:Computer {domain:'$DOMAIN'}) RETURN DISTINCT(c.name) AS COMPUTER, u.name AS USER ORDER BY u.name;unrolledUserAdminPrivs.csv"
    "Computers with Admins;MATCH (n)-[r:AdminTo]->(c:Computer {domain:'$DOMAIN'}) WITH COLLECT(c.name) as compsWithAdmins MATCH (c2:Computer) WHERE c2.name in compsWithAdmins RETURN c2.name AS ComputerName ORDER BY ComputerName ASC;compsWithAdmins.csv"
    "Computers without Admins;MATCH (n)-[r:AdminTo]->(c:Computer {domain:'$DOMAIN'}) WITH COLLECT(c.name) as compsWithAdmins MATCH (c2:Computer) WHERE NOT c2.name in compsWithAdmins RETURN c2.name AS ComputerName ORDER BY ComputerName ASC;compsWithoutAdmins.csv"
    "Groups with Computers and Admins;MATCH (c:Computer)-[r:MemberOf*1..]->(g:Group {domain:'$DOMAIN'}) WITH g MATCH (u:User)-[r:MemberOf*1..]->(g) RETURN DISTINCT(g.name) as Name, g.domain AS Domain, g.highvalue AS HighValue, g.objectid AS SID, g.description AS Description, g.admincount AS AdminCount;GroupsWithCompsAndAdmins.csv"
    "Group Admin Info;MATCH (g:Group {domain:'$DOMAIN'}) WITH g OPTIONAL MATCH (g)-[r:AdminTo]->(c1:Computer) WITH g,COUNT(c1) as explicitAdmins OPTIONAL MATCH (g)-[r:MemberOf*1..]->(a:Group)-[r2:AdminTo]->(c2:Computer) WITH g,explicitAdmins,COUNT(DISTINCT(c2)) as unrolledAdmins RETURN g.name AS Name,explicitAdmins,unrolledAdmins, explicitAdmins + unrolledAdmins as totalAdmins ORDER BY totalAdmins DESC;GroupAdminInfo.csv"
    "Groups Ordered by Admin Count;MATCH (g:Group {domain:'$DOMAIN'}) OPTIONAL MATCH (g)-[:AdminTo]->(c1:Computer) OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c2:Computer) WITH g, COLLECT(c1) + COLLECT(c2) AS tempVar UNWIND tempVar AS computers RETURN g.name AS GroupName,COUNT(DISTINCT(computers)) AS AdminRightCount ORDER BY AdminRightCount DESC;GroupAdminCounts.csv"
    "Full User Property List;MATCH(u:User {domain:'$DOMAIN'}) SET u.llInt = coalesce(u.lastlogon,'1') SET u.lldInt = coalesce(u.lldate,'1') SET u.lltsInt = coalesce(u.lastlogontimestamp,'1') SET u.pwdlsInt = coalesce(u.pwdlastset,'1') RETURN u.name AS UserName, u.displayname AS DisplayName, u.domain AS Domain, u.enabled AS Enabled, u.highvalue AS HighValue, u.objectid AS SID , u.description AS Description, u.title AS Title, u.email as Email, datetime({epochSeconds:toInteger(u.llInt)}) AS LastLogon, datetime({epochSeconds:toInteger(u.lldInt)}) AS LLDate, datetime({epochSeconds:toInteger(u.lltsInt)}) AS LLTimeStamp, datetime({epochSeconds:toInteger(u.pwdlsInt)}) AS PasswordLastSet, u.owned AS Owned, u.sensitive AS Sensitive, u.admincount AS AdminCount, u.hasspn AS HasSPN, u.unconstraineddelegation AS UnconstrainedDelegation, u.dontreqpreauth AS DontReqPreAuth, u.passwordnotreqd AS PasswordNotRequired, u.homedirectory AS HomeDirectory, u.serviceprincipalnames AS ServicePrincipalNames;AllUserProps.csv"
    "Full Computer Property List;MATCH (c:Computer {domain:'$DOMAIN'}) SET c.llInt = coalesce(c.lastlogon,'1') SET c.lltsInt = coalesce(c.lastlogontimestamp,'1') SET c.pwdlsInt = coalesce(c.pwdlastset,'1') RETURN c.name AS ComputerName, c.operatingsystem AS OperatingSystem, c.domain AS Domain, c.enabled AS Enabled, c.highvalue AS HighValue, c.objectid AS SID, c.description AS Description, datetime({epochSeconds:toInteger(c.llInt)}) AS LastLogon, datetime({epochSeconds:toInteger(c.lltsInt)}) AS LLTimeStamp, datetime({epochSeconds:toInteger(c.pwdlsInt)}) AS PasswordLastSet, c.owned AS Owned, c.haslaps AS HasLAPS, c.unconstraineddelegation AS UnconstrainedDelegation, c.allowedtodelegate AS AllowedToDelegate, c.serviceprincipalnames AS ServicePrincipalNames;AllCompProps.csv"
    "Full Domain Property List;MATCH(d:Domain {domain:'$DOMAIN'}) RETURN d.name AS Name, d.domain AS Domain, d.functionallevel AS FunctionalLevel, d.highvalue AS HighValue, d.objectid AS SID;AllDomProps.csv"
    "Full OU Property List;MATCH(ou:OU {domain:'$DOMAIN'}) RETURN ou.name AS OU, ou.domain AS Domain, ou.highvalue AS HighValue, ou.guid AS GUID, ou.description AS Description, ou.blocksinheritance AS BlockInheritance;AllOUProps.csv"
    "Full GPO Property List;MATCH(gpo:GPO {domain:'$DOMAIN'}) RETURN gpo.name AS GPO, gpo.domain AS Domain, gpo.highvalue AS HighValue, gpo.guid AS GUID, gpo.gpcpath AS GPC_Path;AllGPOProps.csv"
    "Full Group Property List;MATCH(g:Group {domain:'$DOMAIN'}) RETURN g.name AS Name, g.domain AS Domain, g.highvalue AS HighValue, g.objectid AS SID, g.description AS Description, g.admincount AS AdminCount;AllGroupProps.csv"
    "Computers with Local Admin Data;MATCH (n)-[:AdminTo]->(c:Computer {domain:'$DOMAIN'}) WITH COUNT(DISTINCT(c)) as computersWithAdminsCount MATCH (c2:Computer {domain:'$DOMAIN'}) RETURN c2.name AS ComputerName;compsWithLocalAdminData.csv"
    "Computers with Session Data;MATCH (c:Computer {domain:'$DOMAIN'})-[:HasSession]->() WITH COUNT(DISTINCT(c)) as computersWithSessions MATCH (c2:Computer {domain:'$DOMAIN'}) RETURN c2.name AS ComputerName;compsWithSessionData.csv"
    "Computers by number of sessions;MATCH (c:Computer {domain:'$DOMAIN'})-[:HasSession]->(n) WITH COUNT(DISTINCT(n)) AS nb_sessions, c ORDER BY nb_sessions DESC RETURN c.name, nb_sessions;compsWithSessionNumbers.csv"
    "Users with Session Data;MATCH ()-[:HasSession]->(u:User {domain:'$DOMAIN'}) WITH COUNT(DISTINCT(u)) as usersWithSessions MATCH (u2:User {domain:'$DOMAIN',enabled:true}) RETURN u2.name AS UserName;userWithSessionData.csv"
    "Domain users with Local Admin;MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid ENDS WITH '-513' OPTIONAL MATCH (g)-[:AdminTo]->(c1) OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c2) WITH COLLECT(c1) + COLLECT(c2) as tempVar UNWIND tempVar AS computers RETURN DISTINCT(computers.name);domainUsersWithLocalAdmin.csv"
    # use "CONTAINS" for SID because SharpHound prefixes well-known SIDs by domain name
    "Everyone with Local Admin;MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid CONTAINS 'S-1-1-0' OPTIONAL MATCH (g)-[:AdminTo]->(c1) OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c2) WITH COLLECT(c1) + COLLECT(c2) as tempVar UNWIND tempVar AS computers RETURN DISTINCT(computers.name);everyoneWithLocalAdmin.csv"
    "Authenticated Users with Local Admin;MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid CONTAINS 'S-1-5-11' OPTIONAL MATCH (g)-[:AdminTo]->(c1) OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c2) WITH COLLECT(c1) + COLLECT(c2) as tempVar UNWIND tempVar AS computers RETURN DISTINCT(computers.name);authUsersWithLocalAdmin.csv"
    "Objects Controlled by Domain Users;MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid ENDS WITH '-513' OPTIONAL MATCH (g)-[{isacl:true}]->(n) OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[{isacl:true}]->(m) WITH COLLECT(n) + COLLECT(m) as tempVar UNWIND tempVar AS objects RETURN DISTINCT(objects) ORDER BY objects.name ASC;ObjectsControlledByDomainUsers.csv"
    # use "CONTAINS" for SID because SharpHound prefixes well-known SIDs by domain name
    "Objects Controlled by Everyone;MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid CONTAINS 'S-1-1-0' OPTIONAL MATCH (g)-[{isacl:true}]->(n) OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[{isacl:true}]->(m) WITH COLLECT(n) + COLLECT(m) as tempVar UNWIND tempVar AS objects RETURN DISTINCT(objects) ORDER BY objects.name ASC;ObjectsControlledByEveryone.csv"
    "Objects Controlled by Authenticated Users;MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid CONTAINS 'S-1-5-11' OPTIONAL MATCH (g)-[{isacl:true}]->(n) OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[{isacl:true}]->(m) WITH COLLECT(n) + COLLECT(m) as tempVar UNWIND tempVar AS objects RETURN DISTINCT(objects) ORDER BY objects.name ASC;ObjectsControlledByAuthenticatedUsers.csv"
    "Domain Users with RDP Rights;MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid ENDS WITH '-513' OPTIONAL MATCH (g)-[:CanRDP]->(c1) OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[:CanRDP]->(c2) WITH COLLECT(c1) + COLLECT(c2) as tempVar UNWIND tempVar AS computers RETURN DISTINCT(computers.name);DomainUsersWithRDPRights.csv"
    # use "CONTAINS" for SID because SharpHound prefixes well-known SIDs by domain name
    "Everyone with RDP Rights;MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid CONTAINS 'S-1-1-0' OPTIONAL MATCH (g)-[:CanRDP]->(c1) OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[:CanRDP]->(c2) WITH COLLECT(c1) + COLLECT(c2) as tempVar UNWIND tempVar AS computers RETURN DISTINCT(computers.name);EveryonewithRDPRights.csv"
    "Authenticated Users with RDP Rights;MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid CONTAINS 'S-1-5-11' OPTIONAL MATCH (g)-[:CanRDP]->(c1) OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[:CanRDP]->(c2) WITH COLLECT(c1) + COLLECT(c2) as tempVar UNWIND tempVar AS computers RETURN DISTINCT(computers.name);AuthenticatedUserswithRDPRights.csv"
    "Domain Users with DCOM Rights;MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid ENDS WITH '-513' OPTIONAL MATCH (g)-[:ExecuteDCOM]->(c1) OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[:ExecuteDCOM]->(c2) WITH COLLECT(c1) + COLLECT(c2) as tempVar UNWIND tempVar AS computers RETURN DISTINCT(computers.name);DomainUserswithDCOMRights.csv"
    # use "CONTAINS" for SID because SharpHound prefixes well-known SIDs by domain name
    "Everyone with DCOM Rights;MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid CONTAINS 'S-1-1-0' OPTIONAL MATCH (g)-[:ExecuteDCOM]->(c1) OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[:ExecuteDCOM]->(c2) WITH COLLECT(c1) + COLLECT(c2) as tempVar UNWIND tempVar AS computers RETURN DISTINCT(computers.name);EveryonewithDCOMRights.csv"
    "Authenticated Users with DCOM Rights;MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid CONTAINS 'S-1-5-11' OPTIONAL MATCH (g)-[:ExecuteDCOM]->(c1) OPTIONAL MATCH (g)-[:MemberOf*1..]->(:Group)-[:ExecuteDCOM]->(c2) WITH COLLECT(c1) + COLLECT(c2) as tempVar UNWIND tempVar AS computers RETURN DISTINCT(computers.name);AuthenticatedUserswithDCOMRights.csv"
    "Hops From Kerberoastable Users to DA;MATCH (u:User {hasspn:true}) MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid ENDS WITH '-512' AND NOT u.name STARTS WITH 'KRBTGT@' MATCH p = shortestPath((u)-[r*1..]->(g)) WHERE NONE (r IN relationships(p) WHERE type(r)='GetChanges') AND NONE (r in relationships(p) WHERE type(r)='GetChangesAll') RETURN u.name AS UserName,LENGTH(p) AS Hops ORDER BY LENGTH(p) ASC;HopsFromKerberoastableUsersToDA.csv"
    "Hops From ASREProastable Users to DA;MATCH (u:User {dontreqpreauth:true}) MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid ENDS WITH '-512' AND NOT u.name STARTS WITH 'KRBTGT@' MATCH p = shortestPath((u)-[r*1..]->(g)) WHERE NONE (r IN relationships(p) WHERE type(r)='GetChanges') AND NONE (r in relationships(p) WHERE type(r)='GetChangesAll') RETURN u.name AS UserName,LENGTH(p) AS Hops ORDER BY LENGTH(p) ASC;HopsFromASREPRoastableUsersToDA.csv"
    "Admins On Domain Controllers;MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid ENDS WITH '-516' MATCH (c:Computer)-[:MemberOf*1..]->(g) OPTIONAL MATCH (n)-[:AdminTo]->(c) OPTIONAL MATCH (m)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c) WHERE (n:User OR n:Computer) AND (m:User OR m:Computer) WITH COLLECT(n) + COLLECT(m) as tempVar1 UNWIND tempVar1 as tempVar2 WITH DISTINCT(tempVar2) as tempVar3 RETURN tempVar3.name ORDER BY tempVar3.name ASC;AdminsOnDomainControllers.csv"
    "RDPers On Domain Controllers;MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid ENDS WITH '-516' MATCH (c:Computer)-[:MemberOf*1..]->(g) OPTIONAL MATCH (n)-[:CanRDP]->(c) OPTIONAL MATCH (m)-[:MemberOf*1..]->(:Group)-[:CanRDP]->(c) WHERE (n:User OR n:Computer) AND (m:User OR m:Computer) WITH COLLECT(n) + COLLECT(m) as tempVar1 UNWIND tempVar1 as tempVar2 WITH DISTINCT(tempVar2) as tempVar3 RETURN tempVar3.name ORDER BY tempVar3.name ASC;RDPersOnDomainControllers.csv"
    "Domain Controller GPO Controllers;MATCH (g:Group {domain:'$DOMAIN'}) WHERE g.objectid ENDS WITH '-516' MATCH (c:Computer)-[:MemberOf*1..]->(g) OPTIONAL MATCH p1 = (g1:GPO)-[r1:GpLink {enforced:true}]->(container1)-[r2:Contains*1..]->(c) OPTIONAL MATCH p2 = (g2:GPO)-[r3:GpLink {enforced:false}]->(container2)-[r4:Contains*1..]->(c) WHERE NONE (x in NODES(p2) WHERE x.blocksinheritance = true AND x:OU AND NOT (g2)-->(x)) WITH COLLECT(g1) + COLLECT(g2) AS tempVar1 UNWIND tempVar1 as tempVar2 WITH DISTINCT(tempVar2) as GPOs OPTIONAL MATCH (n)-[{isacl:true}]->(GPOs) OPTIONAL MATCH (m)-[:MemberOf*1..]->(:Group)-[{isacl:true}]->(GPOs) WITH COLLECT(n) + COLLECT(m) as tempVar1 UNWIND tempVar1 as tempVar2 RETURN DISTINCT(tempVar2.name) ORDER BY tempVar2.name ASC;DomainControllerGPOControllers.csv"
    "Admins On Exchange Servers;MATCH (n:Computer {domain:'$DOMAIN'}) UNWIND n.serviceprincipalnames AS spn MATCH (n) WHERE TOUPPER(spn) STARTS WITH 'EXCHANGEMDB/' WITH n as c MATCH (c)-[:MemberOf*1..]->(g:Group) WHERE g.name CONTAINS 'EXCHANGE' OPTIONAL MATCH (n)-[:AdminTo]->(c) OPTIONAL MATCH (m)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c) WITH COLLECT(n) + COLLECT(m) as tempVar1 UNWIND tempVar1 AS exchangeAdmins RETURN DISTINCT(exchangeAdmins.name);AdminsOnExchangeServers.csv"
    "RDPers On Exchange Servers;MATCH (n:Computer {domain:'$DOMAIN'}) UNWIND n.serviceprincipalnames AS spn MATCH (n) WHERE TOUPPER(spn) STARTS WITH 'EXCHANGEMDB/' WITH n as c MATCH (c)-[:MemberOf*1..]->(g:Group) WHERE g.name CONTAINS 'EXCHANGE' OPTIONAL MATCH (n)-[:CanRDP]->(c) OPTIONAL MATCH (m)-[:MemberOf*1..]->(:Group)-[:CanRDP]->(c) WITH COLLECT(n) + COLLECT(m) as tempVar1 UNWIND tempVar1 AS exchangeAdmins RETURN DISTINCT(exchangeAdmins.name);RDPersOnExchangeServers.csv"
    "Exchange Server GPO Controllers;MATCH (n:Computer {domain:'$DOMAIN'}) UNWIND n.serviceprincipalnames AS spn MATCH (n) WHERE TOUPPER(spn) STARTS WITH 'EXCHANGEMDB/' WITH n as c MATCH (c)-[:MemberOf*1..]->(g:Group) WHERE g.name CONTAINS 'EXCHANGE' OPTIONAL MATCH p1 = (g1:GPO)-[r1:GpLink {enforced:true}]->(container1)-[r2:Contains*1..]->(c) OPTIONAL MATCH p2 = (g2:GPO)-[r3:GpLink {enforced:false}]->(container2)-[r4:Contains*1..]->(c) WHERE NONE (x in NODES(p2) WHERE x.blocksinheritance = true AND x:OU AND NOT (g2)-->(x)) WITH COLLECT(g1) + COLLECT(g2) AS tempVar1 UNWIND tempVar1 as tempVar2 WITH DISTINCT(tempVar2) as GPOs OPTIONAL MATCH (n)-[{isacl:true}]->(GPOs) OPTIONAL MATCH (m)-[:MemberOf*1..]->(:Group)-[{isacl:true}]->(GPOs) WITH COLLECT(n) + COLLECT(m) as tempVar1 UNWIND tempVar1 as tempVar2 RETURN DISTINCT(tempVar2.name) ORDER BY tempVar2.name ASC;ExchangeServerGPOControllers.csv"
    "Domain Admin Controllers;MATCH (DAUser)-[:MemberOf*1..]->(g:Group {domain:'$DOMAIN'}) WHERE g.objectid ENDS WITH '-512' OPTIONAL MATCH (n)-[{isacl:true}]->(DAUser) OPTIONAL MATCH (m)-[:MemberOf*1..]->(:Group)-[{isacl:true}]->(DAUser) WITH COLLECT(n) + COLLECT(m) as tempVar1 UNWIND tempVar1 AS DAControllers RETURN DISTINCT(DAControllers.name) ORDER BY DAControllers.name ASC;DomainAdminControllers.csv"
    "Computers With DA Sessions;MATCH (c:Computer)-[:HasSession]->()-[:MemberOf*1..]->(g:Group {domain:'$DOMAIN'}) WHERE g.objectid ENDS WITH '-512' RETURN DISTINCT(c.name) ORDER BY c.name ASC;ComputersWithDASessions.csv"
    "Domain Admin GPO Controllers;MATCH (DAUser)-[:MemberOf*1..]->(g:Group {domain:'$DOMAIN'}) WHERE g.objectid ENDS WITH '-512' OPTIONAL MATCH p1 = (g1:GPO)-[r1:GpLink {enforced:true}]->(container1)-[r2:Contains*1..]->(DAUser) OPTIONAL MATCH p2 = (g2:GPO)-[r3:GpLink {enforced:false}]->(container2)-[r4:Contains*1..]->(DAUser) WHERE NONE (x in NODES(p2) WHERE x.blocksinheritance = true AND x:OU AND NOT (g2)-->(x)) WITH COLLECT(g1) + COLLECT(g2) AS tempVar1 UNWIND tempVar1 as tempVar2 WITH DISTINCT(tempVar2) as GPOs OPTIONAL MATCH (n)-[{isacl:true}]->(GPOs) OPTIONAL MATCH (m)-[:MemberOf*1..]->(:Group)-[{isacl:true}]->(GPOs) WITH COLLECT(n) + COLLECT(m) as tempVar1 UNWIND tempVar1 as tempVar2 RETURN DISTINCT(tempVar2.name);DomainAdminGPOControllers.csv"
    "High Value Object Controllers;MATCH (u:User)-[:MemberOf*1..]->(g:Group {domain:'$DOMAIN',highvalue:true}) OPTIONAL MATCH (n)-[{isacl:true}]->(u) OPTIONAL MATCH (m)-[:MemberOf*1..]->(:Group)-[{isacl:true}]->(u) WITH COLLECT(n) + COLLECT(m) as tempVar UNWIND tempVar as highValueControllers RETURN DISTINCT(highValueControllers.name) ORDER BY highValueControllers.name ASC;HighValueObjectControllers.csv"
    "High Value User Sessions;MATCH (c:Computer)-[:HasSession]->(u:User)-[:MemberOf*1..]->(g:Group {domain:'$DOMAIN',highvalue:true}) RETURN DISTINCT(c.name) ORDER BY c.name ASC;HighValueUserSessions.csv"
    "High Value User GPO Controllers;MATCH (u:User)-[:MemberOf*1..]->(g:Group {domain:'$DOMAIN',highvalue:true}) OPTIONAL MATCH p1 = (g1:GPO)-[r1:GpLink {enforced:true}]->(container1)-[r2:Contains*1..]->(u) OPTIONAL MATCH p2 = (g2:GPO)-[r3:GpLink {enforced:false}]->(container2)-[r4:Contains*1..]->(u) WHERE NONE (x in NODES(p2) WHERE x.blocksinheritance = true AND x:OU AND NOT (g2)-->(x)) WITH COLLECT(g1) + COLLECT(g2) AS tempVar1 UNWIND tempVar1 as tempVar2 WITH DISTINCT(tempVar2) as GPOs OPTIONAL MATCH (n)-[{isacl:true}]->(GPOs) OPTIONAL MATCH (m)-[:MemberOf*1..]->(:Group)-[{isacl:true}]->(GPOs) WITH COLLECT(n) + COLLECT(m) as tempVar1 UNWIND tempVar1 as tempVar2 RETURN DISTINCT(tempVar2.name) ORDER BY tempVar2.name ASC;HighValueUserGPOControllers.csv"
    "Computers with Foreign Admins;MATCH (c:Computer {domain:'$DOMAIN'}) OPTIONAL MATCH (n)-[:AdminTo]->(c) WHERE (n:User OR n:Computer) AND NOT n.domain = c.domain OPTIONAL MATCH (m)-[:MemberOf*1..]->(:Group)-[:AdminTo]->(c) WHERE (m:User OR m:Computer) AND NOT m.domain = c.domain WITH COLLECT(n) + COLLECT(m) AS tempVar,c UNWIND tempVar AS foreignAdmins RETURN c.name,COUNT(DISTINCT(foreignAdmins)) ORDER BY COUNT(DISTINCT(foreignAdmins)) DESC;ComputerswithForeignAdmins.csv"
    "GPOs with Foreign Controllers;MATCH (g:GPO {domain:'$DOMAIN'}) OPTIONAL MATCH (n)-[{isacl:true}]->(g) WHERE (n:User OR n:Computer) AND NOT n.domain = g.domain OPTIONAL MATCH (m)-[:MemberOf*1..]->(:Group)-[{isacl:true}]->(g) WHERE (m:User OR m:Computer) AND NOT m.domain = g.domain WITH COLLECT(n) + COLLECT(m) AS tempVar,g UNWIND tempVar AS foreignGPOControllers RETURN g.name,COUNT(DISTINCT(foreignGPOControllers)) ORDER BY COUNT(DISTINCT(foreignGPOControllers)) DESC;GPOswithForeignControllers.csv"
    "Groups with Foreign Controllers;MATCH (g:Group {domain:'$DOMAIN'}) OPTIONAL MATCH (n)-[{isacl:true}]->(g) WHERE (n:User OR n:Computer) AND NOT n.domain = g.domain OPTIONAL MATCH (m)-[:MemberOf*1..]->(:Group)-[{isacl:true}]->(g) WHERE (m:User OR m:Computer) AND NOT m.domain = g.domain WITH COLLECT(n) + COLLECT(m) AS tempVar,g UNWIND tempVar AS foreignGroupControllers RETURN g.name,COUNT(DISTINCT(foreignGroupControllers)) ORDER BY COUNT(DISTINCT(foreignGroupControllers)) DESC;GroupswithForeignControllers.csv"
    "All Objects in Domain;MATCH (n {domain:'$DOMAIN'}) RETURN n.name AS Name, n.displayname AS DisplayName, n.objectid AS SID;AllObjectsInDomain.csv"
    "Users with the cleartext UserPassword field populated;MATCH (u:User {domain:'$DOMAIN'}) WHERE u.userpassword IS NOT NULL RETURN u.displayname,u.userpassword;UserPassword.csv"
)

toolCheck
