#!/bin/bash
#Variable to keep track of version for auditing purposes
SCRIPT_VERSION=0.1.0
SCRIPT_DATE="2017-10-16"

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
    str_local_node=$(hostname -s)

    #echo the str_local_node name
    echo ${str_local_node}
    return 0
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

    sync

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
    >&2 echo "Usage: ./${SCRIPT_NAME}.${SCRIPT_EXTENSION} -f <config_file>"
    >&2 echo "      -f : Config file"
    >&2 echo ""

    script_exit 1
}

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
    if [[ $int_return_code -eq 0 ]]
    then
        echo "The script ${SCRIPT_NAME} is not already running. Locking ${str_pid_file}"
    else
        >&2 echo "An instance of ${SCRIPT_NAME} is already running"
        exit 1
    fi
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

    #Check if the direcotory is writeable
    if [[ ! -w ${str_log_dir} ]]
    then
        #The directory is not writeable, lets try to change that
        chmod ugo+w ${str_log_dir} 1>/dev/null 2>&1

        #Re-check for write permissions
        if [[ ! -w ${str_log_dir} ]]
        then
            #The directory can still not be written to
            >&2 echo "The direcotry ${str_log_dir} can not be written to"
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
    #Check Incoming Variables and Usage
    while getopts f: options
    do
        case $options in
        f)
            CONFIG_FILE=$OPTARG
            if [[ -z $CONFIG_FILE ]]
            then
                >&2 echo "CONFIG_FILE (-f) was provided on the command line, but the value provided is null"
                script_usage
            fi
        ;;
        \?)
            clear
        ;;
        *)
            clear
        ;;
        esac
    done

    #ENSURE CONFIG_FILE WAS PROVIDED IN THE COMMAND LINE
    if [[ -z $CONFIG_FILE ]]
    then
        >&2 echo "CONFIG_FILE (-f) value is null"
        script_usage
    fi

    #Find influxDB configuration
    str_db_config_raw=$(egrep '^db' ${CONFIG_FILE} | head -n 1)
    db_ip=$(echo ${str_db_config_raw} | cut -d',' -f2)
    db_port=$(echo ${str_db_config_raw} | cut -d',' -f3)
    db_name=$(echo ${str_db_config_raw} | cut -d',' -f4)

    #Parse cameras and update if necessary
    int_i=0
    while read cam
    do
        str_cam_config_raw=${cam}
        cam_ip[${int_i}]=$(echo ${str_cam_config_raw} | cut -d',' -f2)
        cam_username[${int_i}]=$(echo ${str_cam_config_raw} | cut -d',' -f3)
        cam_password[${int_i}]=$(echo ${str_cam_config_raw} | cut -d',' -f4)
        cam_sensor_id[${int_i}]=$(echo ${str_cam_config_raw} | cut -d',' -f5)
        cam_overlay_template[${int_i}]=$(echo ${str_cam_config_raw} | cut -d',' -f6)
        cam_sensor_last[${int_i}]=$(echo ${str_cam_config_raw} | cut -d',' -f7)

        db_sensor_last[${int_i}]=$(curl -s -G "http://${db_ip}:${db_port}/query?pretty=true" --data-urlencode "db=${db_name}" --data-urlencode "q=SELECT last(\"value\") FROM \"temperature\" WHERE \"deviceId\"='${cam_sensor_id[${int_i}]}'" | jq '.results[].series[].values[][-1]' | cut -d'.' -f1)

        if [[ "${cam_sensor_last[${int_i}]}" -eq "${db_sensor_last[${int_i}]}" ]]
        then
            continue
        else
            temp_file=$(mktemp)
            sed -e "s/REPLACE_ME/${db_sensor_last[${int_i}]}F/" ${cam_overlay_template[${int_i}]} > ${temp_file}
            curl -s -T ${temp_file} "http://${cam_username[${int_i}]}:${cam_password[${int_i}]}@${cam_ip[${int_i}]}/Video/inputs/channels/1/overlays/text/1" >/dev/null
            sed -i "/${cam_ip[${int_i}]}/s/,${cam_sensor_last[${int_i}]}$/,${db_sensor_last[${int_i}]}/" ${CONFIG_FILE}
        fi
        ((int_i+=1))
    done < <(egrep '^cam' ${CONFIG_FILE})
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

#Execute main
main "$@"

#Exit
script_exit 0