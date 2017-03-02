#!/bin/bash
#Variable to keep track of version for auditing purposes
SCRIPT_VERSION=0.1.2
SCRIPT_DATE="2016-10-11"

#--------------------------------------------------------------------------
#   NAME            check_ecc.sh
#   PURPOSE         Checks your system for ecc errors and reports any it finds
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

    #If the email_send flag was enabled, send an email
    if [[ ${EMAIL_SEND} -eq 1 ]]
    then
        mailx -s "Notice: ${HOST_NAME} - ECC Events Found" ryan.flagler@gmail.com < ${BACKUP_PATH}/${BACKUP_FILE}
    else
        rm -f ${BACKUP_PATH}/${BACKUP_FILE}
    fi

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
    declare -g BACKUP_PATH="/mpool00/Recovery/${HOST_NAME}/ecc"
    declare -g BACKUP_FILE="${HOST_NAME}-ecc-${DATE_CURRENT}.txt"
    declare -g EMAIL_SEND=0

    #Make sure there isn't already an intance of the script running
    script_single_instance "/var/run/${SCRIPT_NAME}.pid"

    #Create initial path for our backup files
    mkdir -pm 660 ${BACKUP_PATH}

    #Search for memory controllers on this system
    for controller_path in $(find /sys/devices/system/edac/mc/ -maxdepth 1 -mindepth 1 -type d -name "mc*" 2>/dev/null)
    do
        controller_name=$(echo ${controller_path} | cut -d'/' -f7)
        errors_uncorrectable=$(< ${controller_path}/ue_count)
        errors_correctable=$(< ${controller_path}/ce_count)

        #If this memory controller has any errors, send an email
        if [[ ${errors_uncorrectable} -gt 0 ]] || [[ ${errors_correctable} -gt 0 ]]
        then
            EMAIL_SEND=1
        fi

        #Ouput our gathered data to a file
        echo "-------------------------------------------" >> ${BACKUP_PATH}/${BACKUP_FILE}
        echo "Memory Controller - ${controller_name}" >> ${BACKUP_PATH}/${BACKUP_FILE}
        echo "  Uncorrectable Error Count - ${errors_uncorrectable}" >> ${BACKUP_PATH}/${BACKUP_FILE}
        echo "    Correctable Error Count - ${errors_uncorrectable}" >> ${BACKUP_PATH}/${BACKUP_FILE}
        echo "" >> ${BACKUP_PATH}/${BACKUP_FILE}

        #Find each DIMM installed on this memory controller
        for dimm_path in $(find ${controller_path} -maxdepth 1 -mindepth 1 -type d -name "dimm*" 2>/dev/null)
        do
            dimm_name=$(echo ${dimm_path} | cut -d'/' -f8)
            dimm_label=$(< ${dimm_path}/dimm_label)
            dimm_location=$(< ${dimm_path}/dimm_location)
            dimm_type=$(< ${dimm_path}/dimm_mem_type)
            dimm_size=$(< ${dimm_path}/size)
            errors_logged=$(grep -c ${dimm_label} /var/log/kern.log)

            #Ouput our gathered data to a file
            echo "Memory Module - ${dimm_name}" >> ${BACKUP_PATH}/${BACKUP_FILE}
            echo "               Label - ${dimm_label}" >> ${BACKUP_PATH}/${BACKUP_FILE}
            echo "            Location - ${dimm_location}" >> ${BACKUP_PATH}/${BACKUP_FILE}
            echo "                Type - ${dimm_type}" >> ${BACKUP_PATH}/${BACKUP_FILE}
            echo "                Size - ${dimm_size}" >> ${BACKUP_PATH}/${BACKUP_FILE}
            echo "  Logged Error Count - ${errors_logged}" >> ${BACKUP_PATH}/${BACKUP_FILE}
            echo "" >> ${BACKUP_PATH}/${BACKUP_FILE}

            #If any errors are logged for this DIMM, send an email
            if [[ ${errors_logged} -gt 0 ]]
            then
                EMAIL_SEND=1
            fi
        done
    done
}

#Set signal handlers to run our script_exit Function
trap 'rc=$?; script_exit $rc' 0 1 2 3 15

#Execute main
main "$@"
