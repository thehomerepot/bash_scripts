#!/bin/bash
#Variable to keep track of version for auditing purposes
SCRIPT_VERSION=0.1.0

#--------------------------------------------------------------------------
#     Name          : identify_disks.sh
#     Purpose       : Gather information about the hard drives in your system
#--------------------------------------------------------------------------

#--------------------------------------------------------------------------
#    FUNCTION       check_execution
#    SYNTAX         check_execution <PID_FILE> <wait>
#    DESCRIPTION    This function identifies if there is already an instance of this script running
#                   0=Success
#                   1=Failure
#                   2=Error
#--------------------------------------------------------------------------
function check_execution
{
    #Validate the number of passed variables
    if [[ $# -ne 1 ]]
    then
        #Invalid number of arguments
        >&2 echo "Received an invalid number of arguments"
        exit 2
    fi

    #Assign variables passed
    typeset str_pid_file=$1

    #Use a file descriptor to track a file for locking so we can utilize flock
    exec 9>${str_pid_file}

    #Acquire an exclusive lock to file descriptor 9
    flock -n 9 2>/dev/null
    int_return_code=$?
    #Check if there is already an intance of the script running
    if [[ $int_return_code -ne 0 ]]
    then
        >&2 echo "An instance of ${SCRIPT_NAME} is already locked to ${str_pid_file}"
        exit 1
    fi
}

#--------------------------------------------------------------------------
#    FUNCTION       find_local_node_name
#    SYNTAX         variable=$(find_local_node_name)
#    DESCRIPTION    Finds the local node name and strips any FQDN
#
#    VARIABLE
#    DEPENDENCIES   n/a
#
#    FUNCTION
#    DEPENDENCIES   n/a
#--------------------------------------------------------------------------
function find_local_node_name
{
    #Setup variables
    typeset str_local_node

    #Get the local node name and strip any suffix
    str_local_node=$(hostname -s | tr '[:upper:]' '[:lower:]')

    #echo the str_local_node name
    echo ${str_local_node}
    return 0
}

#--------------------------------------------------------------------------
#    FUNCTION       redirect_output
#    SYNTAX         redirect_output <LOG_FILE>
#    DESCRIPTION    Manages redirection/prepending of all stdOut/stdErr to a logfile and screen
#
#    VARIABLE
#    DEPENDENCIES   init_call
#
#    FUNCTION
#    DEPENDENCIES   n/a
#--------------------------------------------------------------------------
function redirect_output
{
    #Validate the number of passed variables
    if [[ $# -lt 1 ]]
    then
        #Invalid number of arguments
        >&2 echo "Received an invalid number of arguments"
        exit 1
    fi

    typeset str_log_file=$1; shift

    if [[ ${init_call} -eq 0 ]]
    then
        #Initial execution
        init_call=1

        #Save our stdOut/stdErr values
        exec 3>&1
        exec 4>&2
    elif [[ -z ${init_call} ]]
    then
        #The required init_call global variable is not set
        >&2 echo "The function redirect_output requires an init_call global variable set to 0"
        exit 1
    fi

    #Restore stdOut/stdErr to normal
    exec 1>&3 3>&-
    exec 2>&4 4>&-

    #Only redirect output if we can
    if [[ "${str_log_file}" != "STOP" ]]
    then
        #Redirect our stdOut/stdErr
        exec 3>&1 1> >(tee ${str_log_file})
        exec 4>&2 2> >(tee ${str_log_file})
    else
        #We are essentially back to normal now. Reset our init_call variable
        init_call=0
    fi
}

#--------------------------------------------------------------------------
#    FUNCTION       script_exit
#    SYNTAX         script_exit <exitCode>
#    DESCRIPTION    Cleans up logs and output redirection and performs any other exit tasks
#
#    VARIABLE
#    DEPENDENCIES   N/A
#
#    FUNCTION
#    DEPENDENCIES   redirect_output
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

    #Unset our redirection of stdout/stderr
    redirect_output "STOP"

    #sync

    #Define variables as local first
    typeset int_exit_code=$1; shift

    #Reset signal handlers to default actions
    trap - 0 1 2 3 15

    #Exit
    exit $int_exit_code
}

#--------------------------------------------------------------------------
#     FUNCTION      script_usage
#     SYNTAX        usage
#     DESCRIPTION   Displays proper usage syntax for the script
#
#     VARIABLE
#     DEPENDENCIES  n/a
#
#     FUNCTION
#     DEPENDENCIES  n/a
#--------------------------------------------------------------------------
function script_usage
{
    >&2 echo "Usage: ./${SCRIPT_NAME}.${SCRIPT_EXTENSION}"
    >&2 echo ""

    script_exit 1
}

#--------------------------------------------------------------------------
#    FUNCTION       setup_log_directory
#    SYNTAX         setup_log_directory <LogDirectoryName>
#    DESCRIPTION    Accepts full logdirectory path and verifies if it can be written to
#                   0=Success
#                   1=Failure
#                   2=Error
#    VARIABLE
#    DEPENDENCIES   n/a
#
#    FUNCTION
#    DEPENDENCIES   n/a
#--------------------------------------------------------------------------
function setup_log_directory
{
    #Validate the number of passed variables
    if [[ $# -ne 1 ]]
    then
    #Invalid number of arguments
    >&2 echo "Received an invalid number of arguments"
    return 2
    fi

    #Assign variables passed
    typeset str_log_dir=$1

    #Check for the directory
    if [[ ! -a ${str_log_dir} ]]
    then
        #The directory doesn't exist, try to create it
        mkdir -p ${str_log_dir} 1>/dev/null 2>&1

        #Re-check for the directory
        if [[ ! -a ${str_log_dir} ]]
        then
            #The directory could not be created
            >&2 echo "The directory ${str_log_dir} does not exist and could not be created"
            return 1
        fi
    fi

    #Check if the direcotory is writeable
    if [[ ! -w ${str_log_dir} ]]
    then
        #The directory is not writeable, lets try to change that
        chmod ugo+w ${str_log_dir} 1>/dev/null 2>&1

        #Re-check for write permissions
        if [[ ! -w ${str_log_dir} ]]
        then
            #The direcotry can still not be written to
            >&2 echo "The direcotry ${str_log_dir} can not be written to"
            return 1
        fi
    fi

    #No Error
    return 0
}

#--------------------------------------------------------------------------
#    FUNCTION       setup_log_file
#    SYNTAX         setup_log_file <log_file_name>
#    DESCRIPTION    Accepts full logfile path and verifies if it can be written to
#                   0=Success
#                   1=Failure
#                   2=Error
#    VARIABLE
#    DEPENDENCIES   n/a
#
#    FUNCTION
#    DEPENDENCIES   n/a
#--------------------------------------------------------------------------
function setup_log_file
{
    #Validate the number of passed variables
    if [[ $# -ne 1 ]]
    then
        #Invalid number of arguments
        >&2 echo "Received an invalid number of arguments"
        return 2
    fi

    #Assign variables passed
    typeset str_log_path=$1
    typeset str_log_dir
    typeset str_log_file

    #Find the directory and filename from the full path
    str_log_dir=$(dirname ${str_log_path})
    if [[ $? -ne 0 ]]
    then
        #dirname failed
        >&2 echo "Could not parse the directory path from logpath ${str_log_path}"
        return 2
    fi

    str_log_file=$(basename ${str_log_path})
    if [[ $? -ne 0 ]]
    then
        #basename failed
        >&2 echo "Could not parse the file name from logpath ${str_log_path}"
        return 2
    fi

    #Check for the directory
    if [[ ! -a ${str_log_dir} ]]
    then
        #The directory doesn't exist, try to create it
        mkdir -p ${str_log_dir} 1>/dev/null 2>&1

        #Re-check for the directory
        if [[ ! -a ${str_log_dir} ]]
        then
            #The directory could not be created
            >&2 echo "The directory ${str_log_dir} does not exist and could not be created"
            return 1
        fi
    fi

    #Check if the directory is writeable
    if [[ ! -w ${str_log_dir} ]]
    then
        #The directory is not writeable, lets try to change that
        chmod ugo+w ${str_log_dir} 1>/dev/null 2>&1

        #Re-check for write permissions
        if [[ ! -w ${str_log_dir} ]]
        then
            #The directory can still not be written to
            >&2 echo "The directory ${str_log_dir} can not be written to"
            return 1
        fi
    fi

    #Check if the file already exists
    if [[ -a ${str_log_path} ]]
    then
        #The file already exists, is it writable?
        if [[ ! -w ${str_log_path} ]]
        then
            #The file exists but is NOT writeable, lets try changing it
            chmod ugo+w ${str_log_path} 1>/dev/null 2>&1

            #Now, recheck if the file is writeable
            if [[ ! -w ${str_log_path} ]]
            then
                #Still can't write to the file
                >&2 echo "The file ${str_log_path} can not be written to"
                return 1
            fi
        fi
    else
        #The file does not exist, lets touch it
        touch ${str_log_path}
    fi

    #No Error
    return 0
}

#--------------------------------------------------------------------------
#     MAIN
#--------------------------------------------------------------------------
function main
{
    #Check Incoming Variables and Usage
    while getopts d options
    do
        case $options in
        d)
            DETAILED_OUTPUT=1
        ;;
        \?)
            clear
        ;;
        *)
            clear
        ;;
        esac
    done

    #Find hardware information
    lsscsi_address=($(lsscsi 2>/dev/null | awk '{print $1}' | tr -d '[]' | xargs))
    lsscsi_type=($(lsscsi 2>/dev/null | awk '{print $2}' | xargs))
    lsscsi_transport=($(lsscsi --transport -L 2>/dev/null | egrep 'transport=' | cut -d'=' -f2 | xargs))
    lsscsi_generic_path=($(lsscsi -g 2>/dev/null | rev | awk '{print $1}' | rev | xargs))
    lsscsi_enclosures=($(lsscsi --transport -L 2>/dev/null | egrep 'enclosure_identifier' | sed 's/.*=0x//g' | sort -u))

    #Parse through all hardware information and get detailed data
    cnt_i=0
    while [[ ${cnt_i} -lt ${#lsscsi_address[@]} ]]
    do
        #Commands for all disks
        disk_path[${cnt_i}]=$(lsblk --paths --list --output NAME,HCTL | egrep "${lsscsi_address[${cnt_i}]}" | awk '{print $1}')
        disk_wwn[${cnt_i}]=$(/lib/udev/scsi_id -g ${lsscsi_generic_path[${cnt_i}]})

        case ${lsscsi_transport[${cnt_i}]} in
        fc0:)
            #Nothing to do here yet
            echo "Nothing to do for fiber channel"
        ;;
        sas)
            lsscsi_model[${cnt_i}]=$(lsscsi --transport -L ${lsscsi_address[${cnt_i}]} 2>/dev/null | egrep 'model=' | cut -d'=' -f2)
            lsscsi_enclosure_identifier[${cnt_i}]=$(lsscsi --transport -L ${lsscsi_address[${cnt_i}]} 2>/dev/null | egrep 'enclosure_identifier' | sed 's/.*=0x//g')
            lsscsi_sas_address[${cnt_i}]=$(lsscsi --transport -L ${lsscsi_address[${cnt_i}]} 2>/dev/null | egrep 'sas_address' | sed 's/.*=0x//g')
            lsscsi_phy_identifier[${cnt_i}]=$(lsscsi --transport -L ${lsscsi_address[${cnt_i}]} 2>/dev/null | egrep 'phy_identifier' | cut -d'=' -f2)
        ;;
        sata)
            lsscsi_model[${cnt_i}]=$(cat /sys/block/$(echo ${disk_path[${cnt_i}]} | cut -d'/' -f3)/device/model)
            #Missing, enclosure identifier, sas address, phy identifier
        ;;
        *)
            clear
        ;;
        esac
        
        #Output our data for validation
        echo ${lsscsi_address[${cnt_i}]}
        echo ${lsscsi_type[${cnt_i}]}
        echo ${lsscsi_transport[${cnt_i}]}
        echo ${lsscsi_model[${cnt_i}]}
        echo ${lsscsi_generic_path[${cnt_i}]}
        echo ${disk_path[${cnt_i}]}
        echo ${disk_wwn[${cnt_i}]}
        echo ${lsscsi_enclosure_identifier[${cnt_i}]}
        echo ${lsscsi_sas_address[${cnt_i}]}
        echo ${lsscsi_phy_identifier[${cnt_i}]}
        echo "------------------------------"

        ((cnt_i+=1))
    done

    #At a disk level, find out if a the disk is flagged for use of anything with lsblk
    #Create temp files for each enclosure so we can add our data, sort, and parse it additionally
    #Somehow create an array that maps and defines enclosures only for easier processing later
    #Gather more disk information? Size, phy/log sectors?
}

#See if this script is already running
SCRIPT_NAME=$(echo $(basename ${0}) | rev | cut -d'.' -f2- | rev)
PID_FILE=/var/run/${SCRIPT_NAME}.pid
check_execution ${PID_FILE}

#Set signal handlers to run our script_exit Function
trap 'rc=$?; script_exit $rc' 0 1 2 3 15

#Required for the redirect_output Function
init_call=0

#Pulls the script name without directory paths or extension
SCRIPT_FILE=$(basename ${0})
SCRIPT_EXTENSION=$(echo $(basename ${0}) | rev | cut -d'.' -f1 | rev)
SCRIPT_PATH=$(readlink -f $0)
SCRIPT_BASE=$(dirname ${SCRIPT_PATH})
SCRIPT_FLAGS=$@

#Pulls the local node name, not including any suffix
LOCAL_NODE=$(find_local_node_name)

#Script directory
SCRIPT_DIR_BASE=/usr/local/bin
SCRIPT_DIR_PATH=${SCRIPT_DIR_BASE}/${SCRIPT_NAME}

#Timestamp
DATE_STAMP=$(date +"%Y.%m.%d")
TIME_STAMP=$(date +"%Y.%m.%d.%H.%M.%S")

#Various log files
LOG_FILE_PATH=${SCRIPT_DIR_PATH}
LOG_FILE=${LOG_FILE_PATH}/${SCRIPT_NAME}.${TIME_STAMP}.log

#Setup Logs
if [[ $(setup_log_file ${LOG_FILE}) -ne 0 ]]
then
    script_exit 1
fi

#Utilize execOutputHandler to redirect/prepend all our stdOut/stdErr
redirect_output ${LOG_FILE}

#Disable detailed output by default
DETAILED_OUTPUT=0

#Execute main
main "$@"

#Exit
script_exit 0
