#!/bin/bash
#Variable to keep track of version for auditing purposes
SCRIPT_VERSION=0.1.2
SCRIPT_DATE="2016-10-11"

#--------------------------------------------------------------------------
#   NAME            rclone_wrapper.sh
#   PURPOSE         Automate rclone execution via a mapping file
#   CREATOR         Ryan Flagler
#   URL             https://github.com/rflagler/bash_scripts
#--------------------------------------------------------------------------

#--------------------------------------------------------------------------
#   FUNCTION        echo
#   SYNTAX          echo <parameters>
#   DESCRIPTION     Runs the echo command through unbuffer to keep output from buffering.
#                   To NOT use this funciton, use "command echo"
#
#   VARIABLE
#   DEPENDENCIES    N/A
#
#   FUNCTION
#   DEPENDENCIES    N/A
#--------------------------------------------------------------------------
function echo
{
    declare executable=$(which echo)
    unbuffer ${executable} $@
}

#--------------------------------------------------------------------------
#   FUNCTION        email_send
#   SYNTAX          email_send <subject> <body_file> <email_addresses>
#   DESCRIPTION     Send an email
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
function email_send
{
    #Validate the number of passed variables
    if [[ $# -ne 3 ]]
    then
        #Invalid number of arguments
        >&2 echo "Received an invalid number of arguments"
        return 2
    fi

    #Define variables as local first
    email_subject=$1; shift
    email_body_file=$1; shift
    email_addresses=$1; shift

    if [[ -z ${email_subject} ]] || [[ -z ${email_body_file} ]] || [[ -z ${email_addresses} ]]
    then
        #The passed value was null
        >&2 echo "Received a null parameter"
        return 2
    fi

    #Valude the email_body_file is a vaild file
    if [[ ! -f ${email_body_file} ]]
    then
        #The passed value was null
        >&2 echo "Received a file parameter that is not a valid file"
        return 2
    fi

    #Look for the mailx binary
    email_binary=$(which mailx 2>/dev/null)

    #Validate we found the mailx binary
    if [[ -z ${email_binary} ]]
    then
        #No email binary found
        >&2 echo "Could not locate the mailx binary"
        return 1
    fi

    #Send the email
    ${email_binary} -s "${email_subject}" "${email_addresses}" < ${email_body_file}
}

#--------------------------------------------------------------------------
#   FUNCTION        setup_logs
#   SYNTAX          setup_logs <LogFileName>
#   DESCRIPTION     Accepts full log file path and verifies if it can be written to
#                   0=Success
#                   1=Failure
#                   2=Usage Error
#   VARIABLE
#   DEPENDENCIES    N/A
#
#   FUNCTION
#   DEPENDENCIES    N/A
#--------------------------------------------------------------------------
function setup_logs
{
    #Validate the number of passed variables
    if [[ $# -ne 1 ]]
    then
        #Invalid number of arguments
        >&2 echo "Received an invalid number of arguments"
        return 2
    fi

    #Assign variables passed
    declare log_path=$1
    declare log_dir
    declare log_file

    #Find the directory and filename from the full path
    log_dir=$(dirname ${log_path})
    if [[ $? -ne 0 ]]
    then
        #dirname failed
        >&2 echo "Could not parse the directory path from logpath ${log_path}"
        return 2
    fi

    log_file=$(basename ${log_path})
    if [[ $? -ne 0 ]]
    then
        #basename failed
        >&2 echo "Could not parse the file name from logpath ${log_path}"
        return 2
    fi

    #Check for the directory
    if [[ ! -a ${log_dir} ]]
    then
        #The directory doesn't exist, try to create it
        mkdir -p ${log_dir} 1>/dev/null 2>&1

        #Re-check for the directory
        if [[ ! -a ${log_dir} ]]
        then
            #The directory could not be created
            >&2 echo "The directory ${log_dir} does not exist and could not be created"
            return 1
        fi
    fi

    #Check if the direcotory is writeable
    if [[ ! -w ${log_dir} ]]
    then
        #The directory is not writeable, lets try to change that
        chmod ugo+w ${log_dir} 1>/dev/null 2>&1

        #Re-check for write permissions
        if [[ ! -w ${log_dir} ]]
        then
            #The direcotry can still not be written to
            >&2 echo "The direcotry ${log_dir} can not be written to"
            return 1
        fi
    fi

    #Check if the file already exists
    if [[ -a ${log_path} ]]
    then
        #The file already exists, is it writable?
        if [[ ! -w ${log_path} ]]
        then
            #The file exists but is NOT writeable, lets try changing it
            chmod ugo+w ${log_path} 1>/dev/null 2>&1

            #Now, recheck if the file is writeable
            if [[ ! -w ${log_path} ]]
            then
                #Still can't write to the file
                >&2 echo "The file ${log_path} can not be written to"
                return 1
            fi
        fi
    else
        #The file does not exist, lets touch it
        touch ${log_path}
    fi

    #No Error
    return 0
}

#--------------------------------------------------------------------------
#   FUNCTION        script_usage
#   SYNTAX          usage
#   DESCRIPTION     Displays proper usage syntax for the script
#
#   VARIABLE
#   DEPENDENCIES    N/A
#
#   FUNCTION
#   DEPENDENCIES    N/A
#--------------------------------------------------------------------------
function script_usage
{
    >&2 echo "Usage   : ./${SCRIPT_NAME}.${SCRIPT_EXTENSION} -f <mapping_file> -e <email_addresses>"
    >&2 echo ""
    >&2 echo "         -f : Path to ! delimited mapping file. Syntax examples below"
    >&2 echo ""
    >&2 echo "              <backup_name>!<source_dir>!<target_dir>!<rclone_parameters>"
    >&2 echo "              UL_Pictures_AmazonCloudDrive-RJF!/mpool00/Personal/Pictures!AmazonCloudDrive-RJF:Backup/Pictures!sync --checksum --max-size=50G --transfers=16 --checkers=32"
    >&2 echo "              DL_Pictures_GoogleDrive-ADF!GoogleDrive-ADF:\"Google Photos\"!/mpool00/Personal/Pictures/ADF-iPhone6!sync --checksum --max-size=50G --transfers=16 --checkers=32"
    >&2 echo ""
    >&2 echo "         -e : Comma separated list of email addresses for alerts"

    exit 1
}

#--------------------------------------------------------------------------
#   FUNCTION        script_exit
#   SYNTAX          script_exit <exit_code>
#   DESCRIPTION     Performs any tasks needed on exit
#
#   VARIABLE
#   DEPENDENCIES    N/A
#
#   FUNCTION
#   DEPENDENCIES    output_handler
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
    output_handler "STOP"

    #Define variables as local first
    exit_code=$1; shift

    #Reset signal handlers to default actions
    trap - 0 1 2 3 15

    #Cleanup the temp directory
    rm -rf ${TEMP_PATH}

    #Exit
    exit ${exit_code}
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
#   FUNCTION        output_handler
#   SYNTAX          output_handler <log_file>
#   DESCRIPTION     Manages redirection/prepending of all stdOut/stdErr to a log file and the screen
#
#   VARIABLE
#   DEPENDENCIES    N/A
#
#   FUNCTION
#   DEPENDENCIES    N/A
#--------------------------------------------------------------------------
function output_handler
{
    #Validate the number of passed variables
    if [[ $# -ne 1 ]]
    then
        #Invalid number of arguments
        >&2 echo "Received an invalid number of arguments"
        exit 1
    fi

    declare log_file=$1; shift

    #Only redirect output if we can
    if [[ "${log_file}" != "STOP" ]]
    then
        #Redirect our stdOut/stdErr
        exec 3>&1 1> >(tee -a ${log_file})
        exec 4>&2 2>&1
    else
        #Restore stdErr and stdOut
        exec 1>&3 3>&-
        exec 2>&4 4>&-
    fi
}

#--------------------------------------------------------------------------
#   FUNCTION        rclone_execute
#   SYNTAX          rclone_execute <mapping_file> <log_path> <mapping_log_file>
#   DESCRIPTION     Parses the list of rclone mappings and executes them sequentially
#
#   VARIABLE
#   DEPENDENCIES    N/A
#
#   FUNCTION
#   DEPENDENCIES    N/A
#--------------------------------------------------------------------------
function rclone_execute
{
    #Validate the number of passed variables
    if [[ $# -ne 3 ]]
    then
        #Invalid number of arguments
        >&2 echo "Received an invalid number of arguments"
        exit 1
    fi

    rclone_mapping_file=$1; shift
    rclone_log_path=$1; shift
    rclone_mapping_log_file=$1; shift

    #Parse each rclone mapping entry and pass it to rclone
    while IFS=!; read rclone_description rclone_source rclone_target rclone_parameters
    do
        rclone_log_file="${rclone_log_path}/${HOST_NAME}-${rclone_description}-${TIME_CURRENT}.log"

        #Now execute the rclone process
        eval /usr/local/bin/rclone --log-file=${rclone_log_file} ${rclone_parameters} ${rclone_source} ${rclone_target}
        return_code=$?

        #Track the return code for each job
        echo "${rclone_description}:${return_code}" >> ${rclone_mapping_log_file}

    done < ${rclone_mapping_file}
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
    #Global variable declarations
    declare -g SCRIPT_FILE=$(basename ${0})
    declare -g SCRIPT_NAME=$(echo $(basename ${0}) | rev | cut -d'.' -f2- | rev)
    declare -g SCRIPT_EXTENSION=$(echo $(basename ${0}) | rev | cut -d'.' -f1 | rev)
    declare -g SCRIPT_EXEC_PATH=$(readlink -f $0)
    declare -g SCRIPT_EXEC_BASE=$(dirname ${SCRIPT_EXEC_PATH})
    declare -g SCRIPT_FLAGS="$@"
    declare -g HOST_NAME=$(hostname -s)
    declare -g DATE_CURRENT=$(date +"%F")
    declare -g TIME_CURRENT=$(date +"%F-%H%M")
    declare -g TEMP_PATH=$(mktemp -d)
    declare -g LOG_FILE_PATH="/mpool00/Recovery/${HOST_NAME}/rclone"
    declare -g EMAIL_FLAG=0

    mkdir -pm 660 $LOG_FILE_PATH
    declare -g LOG_FILE="${LOG_FILE_PATH}/${HOST_NAME}-${SCRIPT_NAME}-${TIME_CURRENT}.log"
    > ${LOG_FILE}

    #Setup Logs
    if [[ $(setup_logs ${LOG_FILE}) -ne 0 ]]
    then
        exit 1
    fi

    #My logs are setup, so lets configure global redirection of output to utilize them
    output_handler ${LOG_FILE}

    #Make sure there isn't already an intance of the script running
    script_single_instance "/var/run/${SCRIPT_NAME}.pid"

    #Check Incoming Variables and Usage
    while getopts f:e: options
    do
        case $options in
        f)
            mapping_file="$OPTARG"
            #CHECK IF FLAG IS NULL
            if [[ -z $mapping_file ]]
            then
                >&2 echo "mapping_file (-f) was provided on the command line, but the value provided is null"
                script_usage
            fi
        ;;
        e)
            email_addresses="$OPTARG"
            #CHECK IF FLAG IS NULL
            if [[ -z $email_addresses ]]
            then
                >&2 echo "email_addresses (-e) was provided on the command line, but the value provided is null"
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

    #Check outside of the case to confirm whether or not we can proceed
    if [[ -z $mapping_file ]]
    then
        >&2 echo "The parameter mapping_file (-f) is required for operation"
        script_usage
    fi

    #Check that the file passed is a real file
    if [[ ! -f $mapping_file ]]
    then
        >&2 echo "The mapping_file (-f) passed is not a valid file"
        script_usage
    fi

    #Create a log file to keep track of all exit codes for the mapping file jobs
    mapping_file_name=$(echo $(basename ${mapping_file}) | rev | cut -d'.' -f2- | rev)
    mapping_log_file=${TEMP_PATH}/${HOST_NAME}-${mapping_file_name}-${TIME_CURRENT}.log

    #Execute the rclone commands in the passed mapping file
    rclone_execute ${mapping_file} ${TEMP_PATH} ${mapping_log_file}

    #Check for errors in the rclone jobs
    while IFS=:; read job return_code
    do
        if [[ ${return_code} -ne 0 ]]
        then
            #Make an email body with return_codes and a short message
            email_body="${TEMP_PATH}/${HOST_NAME}-email-${TIME_CURRENT}.body"
            echo "One or more rclone jobs did not complete successfully. See return codes below." >> ${email_body}
            echo "" >> ${email_body}
            cat ${mapping_log_file} >> ${email_body}

            #A job did not complete successfully, send an email
            email_send "ALERT! ${HOST_NAME} - ${SCRIPT_NAME}" "${email_body}" "${email_addresses}"

            #Break out of the while loop
            break
        fi
    done < ${mapping_log_file}

    #Compress the logs to save space
    cd ${TEMP_PATH}
    tar -cvzf ${LOG_FILE_PATH}/${HOST_NAME}-${SCRIPT_NAME}-${TIME_CURRENT}.tar.gz * >/dev/null
}

#Set signal handlers to run our scriptExit Function
trap 'rc=$?; script_exit $rc' 0 1 2 3 15

#Execute main
main "$@"

#Exit
exit 0
