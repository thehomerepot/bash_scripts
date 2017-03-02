#!/bin/bash
#Variable to keep track of version for auditing purposes
SCRIPT_VERSION=0.1.0
SCRIPT_DATE="2016-10-11"

#--------------------------------------------------------------------------
#   NAME            rclone_wrapper.sh
#   PURPOSE         Monitor zfs pools for scrubs, errors, and space usage
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
#   FUNCTION        pool_health
#   SYNTAX          pool_health <pool_name> <status_file>
#   DESCRIPTION     Performs a health check on a pool
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
function pool_health
{
    #Validate the number of passed variables
    if [[ $# -ne 2 ]]
    then
        #Invalid number of arguments
        >&2 echo "Received an invalid number of arguments"
        return 2
    fi

    #Define variables as local first
    pool_name=$1; shift
    pool_file=$1; shift

    #Check the health of the poolName provided - ONLINE, DEGRADED, UNAVAIL, or SUSPENDED
    pool_health=$(zpool list -H -o health ${pool_name})

    echo "Pool Status    : ${pool_health}" >> ${pool_file}

    if [[ "${pool_health}" != "ONLINE" ]]
    then
        #ALWAYS EXIT FOR AN UNHEALTHY POOL
        script_exit 2
    fi
}

#--------------------------------------------------------------------------
#   FUNCTION        pool_scrub
#   SYNTAX          pool_scrub <pool_name> <status_file>
#   DESCRIPTION     Performs a scrub on a pool
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
function pool_scrub
{
    #Validate the number of passed variables
    if [[ $# -ne 2 ]]
    then
        #Invalid number of arguments
        >&2 echo "Received an invalid number of arguments"
        return 2
    fi

    #Define variables as local first
    pool_name=$1; shift
    pool_file=$1; shift

    #Log the start time
    pool_scrub_start_time=$(date +"%Y-%m-%d %H:%M")

    zpool scrub ${pool_name}
    return_code=$?
    if [[ ${return_code} -ne 0 ]]
    then
        echo "Time To Scrub  : FAILED - SCRUB DID NOT EXECUTE" >> ${pool_file}
        script_exit 2
    else
        #Let's monitor the scrub and wait until it's done to continue
        pool_scrub_status=0 #0=running 1=stopped
        while [[ $pool_scrub_status -eq 0 ]]
        do
            zpool status ${pool_name} | grep -q "scrub in progress"
            pool_scrub_status=$?
            sleep 60
        done

        #Scrub time calculations
        pool_scrub_end_time=$(date +"%Y-%m-%d %H:%M")
        pool_scrub_total_sec=$(($(date -d "${pool_scrub_end_time}" +%s)-$(date -d "${pool_scrub_start_time}" +%s)))
        pool_scrub_total_hrs=$(expr ${pool_scrub_total_sec} / 3600)
        pool_scrub_total_min=$(expr $((${pool_scrub_total_sec}-$((${pool_scrub_total_hrs}*3600)))) / 60)

        echo "Time To Scrub  : ${pool_scrub_total_hrs}H:${pool_scrub_total_min}M" >> ${pool_file}

        #Let's check the health on the pool now that the scrub is complete
        pool_health ${pool_name} ${pool_file}
    fi
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
    >&2 echo "Usage   : ./${SCRIPT_NAME}.${SCRIPT_EXTENSION} -p <pool_name> -t <threshold> -s <days> -l <log_path> -e <email_address>"
    >&2 echo ""

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
#    FUNCTION      exitScript
#    SYNTAX        exitScript $exitCode
#    DESCRIPTION   Steps to complete when the script exits
#--------------------------------------------------------------------------
function exitScript
{
     #Append zpool status data to the log
     echo "" | tee -a $logFile | tee -a $debugLogFile
     echo "zpool status -v ${poolName}" | tee -a $logFile | tee -a $debugLogFile
     echo "------------------------------------------------------------------------------------" | tee -a $logFile | tee -a $debugLogFile
     zpool status -v ${poolName} | tee -a $logFile | tee -a $debugLogFile
     echo "------------------------------------------------------------------------------------" | tee -a $logFile | tee -a $debugLogFile

     #See if we've got an error code
     if (( $1 == 1 )) && [[ -n ${emailAddresses} ]]
     then
          #Send Email
          mailx -s "Notice: ${localnode} - ${poolName}" ${emailAddresses} < $logFile
     fi

     #See if we've got an error code
     if (( $1 == 2 )) && [[ -n ${emailAddresses} ]]
     then
          #Send Email
          mailx -s "ALERT!: ${localnode} - ${poolName}" ${emailAddresses} < $logFile
     fi

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
    declare -g SCRIPT_FLAGS="$@"
    declare -g USER_CURRENT=$(whoami)
    declare -g HOST_NAME=$(hostname -s)
    declare -g DATE_CURRENT=$(date +"%F")
    declare -g TIME_CURRENT=$(date +"%F-%H%M")
    declare -g TEMP_PATH=$(mktemp -d)
    declare -g LOG_FILE_PATH="/mpool00/Recovery/${HOST_NAME}/zfs"
    declare -g LOG_FILE="${LOG_FILE_PATH}/${HOST_NAME}-${SCRIPT_NAME}-${TIME_CURRENT}.log"
    declare -g EMAIL_FLAG=0

    #Create initial path for our backup files
    mkdir -pm 660 ${LOG_FILE_PATH}

    #Setup Logs
    if [[ $(setup_logs ${LOG_FILE}) -ne 0 ]]
    then
        exit 1
    fi

    #My logs are setup, so lets configure global redirection of output to utilize them
    output_handler ${LOG_FILE}

    #Make sure that the root user is executing the script
    if [[ $USER_CURRENT != "root" ]]
    then
         #Not ROOT. Blow up!
         >&2 echo "This script must be executed as the root user."
         exit 1
    fi

    #Make sure there isn't already an intance of the script running
    script_single_instance "/var/run/${SCRIPT_NAME}.pid"

    #Check Incoming Variables and Usage
    while getopts p:s:t:l:e: options
    do
        case $options in
        p)
            pool_name="$OPTARG"
            #CHECK IF FLAG IS NULL
            if [[ -z $pool_name ]]
            then
                >&2 echo "pool_name (-p) was provided on the command line, but the value provided is null"
                script_usage
            fi
        ;;
        s)
            pool_scrub_threshold="$OPTARG"
            #CHECK IF FLAG IS NULL
            if [[ -z $pool_scrub_threshold ]]
            then
                >&2 echo "pool_scrub_threshold (-s) was provided on the command line, but the value provided is null"
                script_usage
            fi
        ;;
        t)
            pool_usage_threshold="$OPTARG"
            #CHECK IF FLAG IS NULL
            if [[ -z $pool_usage_threshold ]]
            then
                >&2 echo "pool_usage_threshold (-t) was provided on the command line, but the value provided is null"
                script_usage
            fi
        ;;
        l)
            log_path="$OPTARG"
            #CHECK IF FLAG IS NULL
            if [[ -z $log_path ]]
            then
                >&2 echo "log_path (-l) was provided on the command line, but the value provided is null"
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
    if [[ -z $pool_name ]]
    then
         >&2 echo "The parameter -p is required for operation"
         script_usage
    fi
    if [[ -z $log_path ]]
    then
         >&2 echo "The parameter -l is required for operation"
         script_usage
    fi


####################################################################
    #Start creating the output data
    echo "Pool           : ${poolName}" | tee -a $logFile | tee -a $debugLogFile

    #Always check pool health first
    executeHealthCheck $poolName

    #Check the percent of freespace available - alarm on threshold
    poolPercentUsed=`zpool list -H -o capacity ${poolName} | cut -d'%' -f1 | tee -a $debugLogFile`
    poolFreeSpace=`zpool list -H -o free ${poolName} | tee -a $debugLogFile`
    echo "Used Space %   : ${poolPercentUsed}%" | tee -a $logFile | tee -a $debugLogFile
    echo "Free Space     : ${poolFreeSpace}" | tee -a $logFile | tee -a $debugLogFile

    #Check if the user specified a threshold AND the threshold was met.
    if [[ -n $poolSpaceThreshold ]] && (( ${poolPercentUsed} > ${poolSpaceThreshold} ))
    then
         #Send an email
         exitCode=1
    fi

    #Check for the last scrub and execute a new one if the days since the last is over the scrubThreshold
    if [[ -n $poolScrubThreshold ]]
    then
         #Retrieve the date of the last scrub for this pool
         lastScrubDate=`zpool history ${poolName} | grep scrub | grep -v "\-s" | tail -n 1 | cut -d'.' -f1 | tee -a $debugLogFile`

         if [[ -z $lastScrubDate ]]
         then
              lastScrubDate="1986-05-02"
         fi

         #Calculate the number of days since the last scrub
         poolDaysSinceScrub=$((($(date -d ${timeStamp} +%s)-$(date -d ${lastScrubDate} +%s))/86400))

         echo "Last Scrub     : ${poolDaysSinceScrub} Days Ago" | tee -a $logFile | tee -a $debugLogFile

         #Compare our poolScrubThreshold to poolDaysSinceScrub
         if (( ${poolDaysSinceScrub} >= ${poolScrubThreshold} ))
         then
              echo "Execute Scrub  : Yes" | tee -a $logFile | tee -a $debugLogFile
              executeScrub ${poolName}
         else
              echo "Execute Scrub  : No" | tee -a $logFile | tee -a $debugLogFile
         fi
    fi

}

#Set signal handlers to run our scriptExit Function
trap 'rc=$?; script_exit $rc' 0 1 2 3 15

#Execute main
main "$@"

#Exit
exit 0
