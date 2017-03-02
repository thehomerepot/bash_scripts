#!/bin/bash
#Variable to keep track of version for auditing purposes
SCRIPT_VERSION=0.1.3
SCRIPT_DATE="2017-03-02"

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

    #Use a file descriptor to track a file for locking so we can utilize flock
    exec 9>${pid_file}

    #Acquire an exclusive lock to file descriptor 9
    flock -n 9 2>/dev/null
    return_code=$?

    #Check if there is already an intance of the script running
    if [[ ${return_code} -ne 0 ]]
    else
        >&2 echo "An instance of this script is already running"
        exit 1
    fi
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

    #Global variable declarations
    declare -g SCRIPT_NAME=$(echo $(basename ${0}) | rev | cut -d'.' -f2- | rev)
    declare -g DATE_CURRENT=$(date +%F-%H%M)
    declare -g HOST_NAME=$(hostname -s)
    declare -g BACKUP_PATH="/mpool00/Recovery/${HOST_NAME}/acls"
    declare -g BACKUP_FILE="${HOST_NAME}-acls-${DATE_CURRENT}.tar.gz"
    declare -g INPUT_FILE="facl.paths"
    declare -g TEMP_PATH=$(mktemp -d)

    #Make sure there isn't already an intance of the script running
    script_single_instance "/var/run/${SCRIPT_NAME}.lock"

    #Create initial path for our backup files
    mkdir -pm 660 ${BACKUP_PATH}

    #Backup ACLs for all directories in our input file
    while read directory_path
    do
        directory_name=$(echo ${directory_path} | cut -d'/' -f2)
        find ${directory_path} -print0 2>/dev/null | xargs -0 getfacl -p 2>/dev/null 1> ${TEMP_PATH}/${directory_name}.facl
    done < ${BACKUP_PATH}/${INPUT_FILE}

    #Tar up the facl files to our backup location
    cd ${TEMP_PATH}
    tar -czf ${BACKUP_PATH}/${BACKUP_FILE} *.facl
}

#Set signal handlers to run our script_exit Function
trap 'rc=$?; script_exit $rc' 0 1 2 3 15

#Execute main
main "$@"
