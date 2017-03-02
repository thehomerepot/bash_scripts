#!/bin/bash
#Variable to keep track of version for auditing purposes
SCRIPT_VERSION=0.1.2
SCRIPT_DATE="2016-10-11"

#--------------------------------------------------------------------------
#   NAME            backup_acls.sh
#   PURPOSE         Backup acl information for paths defined in an input_file
#   CREATOR         Ryan Flagler
#   URL             https://github.com/rflagler/bash_scripts
#--------------------------------------------------------------------------

#--------------------------------------------------------------------------
#   FUNCTION        script_exit
#   SYNTAX          script_exit <exit_code>
#   DESCRIPTION     Performs any exit tasks
#
#   VARIABLE
#   DEPENDENCIES    N/A
#
#   FUNCTION
#   DEPENDENCIES    N/A
#--------------------------------------------------------------------------
function script_exit
{
    #Validate the number of passed variables
    if [[ $# -gt 1 ]]
    then
         #Invalid number of arguments
         #We're just echoing this as a note, we still want the script to exit
         >&2 echo "Received an invalid number of arguments"
    fi

    #Define variables as local first
    exit_code=$1; shift

    #Reset signal handlers to default actions
    trap - 0 1 2 3 15

    #Set desired permissions before exiting
    chown -R root:homeUsers ${BACKUP_PATH}
    chmod -R 660 ${BACKUP_PATH}

    #Cleanup before exiting
    rm -rf "${TEMP_PATH}"

    #Exit
    exit $exit_code
}

#--------------------------------------------------------------------------
#   FUNCTION        script_single_instance
#   SYNTAX          script_single_instance <pid_file>
#   DESCRIPTION     This function identifies if there is already an instance of this script running
#                   0=Success
#                   1=Failure
#                   2=Usage Error
#
#   VARIABLE
#   DEPENDENCIES    N/A
#
#   FUNCTION
#   DEPENDENCIES    N/A
#--------------------------------------------------------------------------
function script_single_instance
{
    #Validate the number of passed variables
    if [[ $# -ne 1 ]]
    then
            #Invalid number of arguments
            >&2 echo "Received an invalid number of arguments"
            exit 1
    fi

    pid_file=$1; shift

    #Check for previously running script first
    if [[ -d ${pid_file} ]]
    then
        #The script is already running
        >&2 echo "An instance of this script is already running"
        exit 1
    else
        rm -f ${pid_file}
    fi

    #Since no previously running script was found, just keep track of the current instance
    ln -s /proc/$$ ${pid_file}
}

#--------------------------------------------------------------------------
#   FUNCTION        main
#   SYNTAX          main "$@"
#   DESCRIPTION     Performs main steps
#
#   VARIABLE
#   DEPENDENCIES    N/A
#
#   FUNCTION
#   DEPENDENCIES    N/A
#--------------------------------------------------------------------------
function main
{
    #Local Variable declarations
    router_name="therouter"
    router_ip="192.168.2.1:4444"
    router_un="limited"
    router_pw="l1m1t3d"

    #Global variable declarations
    declare -g SCRIPT_NAME=$(echo $(basename ${0}) | rev | cut -d'.' -f2- | rev)
    declare -g DATE_CURRENT=$(date +%F-%H%M)
    declare -g BACKUP_PATH="/mpool00/Recovery/${router_name}"
    declare -g BACKUP_FILE="${router_name}-pfsense-config-${DATE_CURRENT}.xml"
    declare -g TEMP_PATH=$(mktemp -d)

    #Make sure there isn't already an intance of the script running
    script_single_instance "/var/run/${SCRIPT_NAME}.pid"

    #Create initial path for our backup files
    mkdir -pm 660 ${BACKUP_PATH}

    wget -qO- 2>/dev/null \
        --keep-session-cookies \
        --save-cookies ${TEMP_PATH}/cookies.txt \
        --no-check-certificate \
        https://${router_ip}/diag_backup.php | \
        grep "name='__csrf_magic'" | \
        sed 's/.*value="\(.*\)".*/\1/' > ${TEMP_PATH}/csrf.txt

    wget -qO- 2>/dev/null \
        --keep-session-cookies \
        --load-cookies ${TEMP_PATH}/cookies.txt \
        --save-cookies ${TEMP_PATH}/cookies.txt \
        --no-check-certificate \
        --post-data "login=Login&usernamefld=${router_un}&passwordfld=${router_pw}&__csrf_magic=$(cat ${TEMP_PATH}/csrf.txt)" \
        https://${router_ip}/diag_backup.php | \
        grep "name='__csrf_magic'" | \
        sed 's/.*value="\(.*\)".*/\1/' > ${TEMP_PATH}/csrf2.txt

    wget 2>/dev/null \
        --keep-session-cookies \
        --load-cookies ${TEMP_PATH}/cookies.txt \
        --no-check-certificate \
        --post-data "Submit=download&donotbackuprrd=yes&__csrf_magic=$(head -n 1 ${TEMP_PATH}/csrf2.txt)" \
        https://${router_ip}/diag_backup.php -O ${BACKUP_PATH}/${BACKUP_FILE}
}

#Set signal handlers to run our script_exit Function
trap 'rc=$?; script_exit $rc' 0 1 2 3 15

#Execute main
main "$@"
