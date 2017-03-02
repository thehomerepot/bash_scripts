#!/bin/bash
#Variable to keep track of version for auditing purposes
SCRIPT_VERSION=0.1.2
SCRIPT_DATE="2016-10-11"

#--------------------------------------------------------------------------
#   NAME            backup_smartctl.sh
#   PURPOSE         Backup smart data for discovered disks
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

    #Global variable declarations
    declare -g SCRIPT_NAME=$(echo $(basename ${0}) | rev | cut -d'.' -f2- | rev)
    declare -g DATE_CURRENT=$(date +%F-%H%M)
    declare -g HOST_NAME=$(hostname -s)
    declare -g BACKUP_PATH=/mpool00/Recovery/${HOST_NAME}/smartctl/${HOST_NAME}-smartctl-${DATE_CURRENT}
    declare -g TEMP_PATH=$(mktemp -d)

    #Make sure there isn't already an intance of the script running
    script_single_instance "/var/run/${SCRIPT_NAME}.pid"

    #Create initial path for our backup files
    mkdir -pm 660 ${BACKUP_PATH}

    #Find any scsi disks and pull just the id of them
    fdisk -l 2>/dev/null | egrep 'Disk /dev/sd' | sed 's/^Disk\ \/dev\///; s/:.*$//' | while read disk_id
    do
        #Output smart data for each disk
        smartctl -a /dev/$disk_id > ${TEMP_PATH}/smartctl.out

        #Attempt to pull the wwid of the disk for our file name
        disk_wwid=$(egrep 'Logical Unit id:|LU WWN Device Id:' ${TEMP_PATH}/smartctl.out | cut -d':' -f2 | sed 's/\ //g; s/0x//')

        #If we didn't find a WWID, let's use the serial number instead
        if [[ -z ${disk_wwid} ]]
        then
            disk_wwid="SN-"$(egrep 'Serial Number:' ${TEMP_PATH}/smartctl.out | cut -d':' -f2 | sed 's/\ //g; s/0x//')
        fi

        #Move our smart output to our backup path and name the file our WWID/SN
        mv ${TEMP_PATH}/smartctl.out ${BACKUP_PATH}/${disk_wwid}
    done
}

#Set signal handlers to run our script_exit Function
trap 'rc=$?; script_exit $rc' 0 1 2 3 15

#Execute main
main "$@"
