#!/bin/bash
#--------------------------------------------------------------------------
#     Name          : large_file_monitor.sh
#     Purpose       : Monitors a specific path for large files and alarms on it
#--------------------------------------------------------------------------
script_version=0.3.8

#Set environment options
#set -o errexit      # -e Any non-zero output will cause an automatic script failure
#set -o pipefail     #    Any non-zero output in a pipeline will return a failure
#set -o noclobber    # -C Prevent output redirection from overwriting an existing file
#set -o nounset      # -u Prevent use of uninitialized variables
#set -o xtrace       # -x Same as verbose but with variable expansion

#--------------------------------------------------------------------------
#    FUNCTION       f_check_dependencies
#    SYNTAX         f_check_dependencies <dependency> <dependency> <etc>
#    DESCRIPTION    This function identifies if you have required software dependencies
#                   0=Success
#                   1=Failure
#                   2=Error
#--------------------------------------------------------------------------
f_check_dependencies() #function_version=0.1.0
{    
    #Validate the number of passed variables
    if [[ $# -eq 0 ]]
    then
        #Invalid number of arguments
        >&2 echo "Received an invalid number of arguments"
        return 2
    fi

    #Assign variables passed
    declare l_dependency_list
    l_dependency_list=("$@")
    declare l_return_code=0

    for dependency in ${l_dependency_list[@]}
    do
        if [[ -z $(which ${dependency} 2>/dev/null) ]]
        then
            l_return_code=1
            >&2 echo "${dependency} is required. Please install it before executing this script."
        fi
    done

    return ${l_return_code}
}

#--------------------------------------------------------------------------
#    FUNCTION       f_check_execution
#    SYNTAX         f_check_execution <PID_FILE>
#    DESCRIPTION    This function identifies if there is already an instance of this script running
#                   0=Success
#                   1=Failure
#                   2=Error
#--------------------------------------------------------------------------
f_check_execution() #function_version=0.1.2
{    
    #Validate the number of passed variables
    if [[ $# -ne 1 ]]
    then
        #Invalid number of arguments
        >&2 echo "Received an invalid number of arguments"
        return 2
    fi

    #Assign variables passed
    declare l_pid_file="${1}"; shift

    #Determine if we're locking or unlocking the passed file
    if [[ "${l_pid_file:0:4}" = "STOP" ]]
    then
        #Remove any locks to prevent child processes from holding onto them
        flock -u 9 1>/dev/null 2>&1 || { rc=$? && >&2 echo "File ${l_pid_file:4} could not be unlocked" && return $rc; }

        #Remove the lock file
        rm "${l_pid_file:4}" 1>/dev/null 2>&1 || { rc=$? && >&2 echo "Lock file ${l_pid_file:4} could not be removed" && return $rc; }
    else
        #Use a file descriptor to track a file for locking so we can utilize flock
        exec 9>"${l_pid_file}" || { rc=$? && >&2 echo "File descriptor redirection to ${l_pid_file} failed" && return $rc; }

        #Acquire an exclusive lock to file descriptor 9 or fail
        flock -n 9 1>/dev/null 2>&1 || { rc=$? && >&2 echo "${l_pid_file} already has a file lock" && return $rc; }
    fi
}

#--------------------------------------------------------------------------
#    FUNCTION       f_script_exit
#    SYNTAX         f_script_exit <exitCode>
#    DESCRIPTION    Cleans up logs, traps, flocks, and performs any other exit tasks
#--------------------------------------------------------------------------
f_script_exit() #function_version=0.1.1
{
    #Validate the number of passed variables
    if [[ $# -gt 1 ]]
    then
        #Invalid number of arguments
        #We're just echoing this as a note, we still want the script to exit
        >&2 echo "Received an invalid number of arguments"
    fi

    #Define variables as local first
    declare l_exit_code="$1"; shift

    #Reset signal handlers to default actions
    trap - 0 1 2 3 15

    #Remove any file descriptor locks
    f_check_execution "STOP${g_pid_file}" || >&2 echo "Removing file descriptor locks failed"

    #If our l_exit_code is not 0, send an error email
    if [[ ${l_exit_code} -ne 0 ]] && [[ -n ${g_email_addresses:-} ]]
    then
        l_email_body="${g_log_path}/${g_script_name}.${g_time_stamp}.email"

        #Configure the subject line
        l_email_subject="${g_domain} - ${g_local_node} - ${g_filesystem} - Execution Error"

        #Append the log file to the email body after removing non-asci characters
        tr -cd '\11\12\15\40-\176' < "${g_log_file}" >> "${l_email_body}"

        #Add space to the end of lines to prevent outlook from removing newlines
        sed -i 's/\r//g; s/$/   /g' "${l_email_body}"

        #Send the email
        mail -s "${l_email_subject}" "${g_email_addresses}" < <(cat ${l_email_body}) || >&2 echo "Sending the email notification failed."
    fi

    #Remove empty log files
    if [[ ! -s "${g_log_file}" ]]
    then
        rm "${g_log_file}" || >&2 echo "Removing null log file ${g_log_file} failed"
    fi

    #Remove any tmp dirs/files we created
    if [[ -n ${g_script_name} ]]
    then
        find "/tmp" -name "${g_script_name}*" -exec rm -rf {} \;
    fi

    #Cleanup old log files
    find "${g_log_path}" -type f -daystart -mtime +"${g_log_retention}" | while read -r line
    do
        rm "${line}" || >&2 echo "Removing old log file ${line} failed"
    done

    #Exit
    exit "${l_exit_code}"
}

#--------------------------------------------------------------------------
#     FUNCTION      f_script_usage
#     SYNTAX        f_script_usage
#     DESCRIPTION   Displays proper usage syntax for the script
#--------------------------------------------------------------------------
f_script_usage() #function_version=0.1.0
{
    echo "Usage: ./${g_script_file} -e <comma_separated_email_addresses> -f <filesystem> -l <lowerthreshold> -u <upperthreshold>"
    echo "      -e : Email Address List. Comma Separated"
    echo "      -f : Path to monitor"
    echo "      -l : File size lower threshold (in bytes 1000000000=1GB)"
    echo "      -u : File size upper threshold (in bytes 1000000000=1GB)"
    echo ""

    f_script_exit 1
}

#--------------------------------------------------------------------------
#    FUNCTION       f_setup_directory
#    SYNTAX         setup_directory <DirectoryName>
#    DESCRIPTION    Accepts full directory path and verifies if it can be written to
#                   0=Success
#                   1=Failure
#                   2=Error
#--------------------------------------------------------------------------
f_setup_directory() #function_version=0.1.1
{
    #Validate the number of passed variables
    if [[ $# -ne 1 ]]
    then
        #Invalid number of arguments
        >&2 echo "Received an invalid number of arguments"
        return 2
    fi

    #Assign variables passed
    declare l_directory=$1; shift

    #Check for the directory
    if [[ ! -d "${l_directory}" ]]
    then
        #The directory doesn't exist, try to create it
        mkdir -p "${l_directory}" 1>/dev/null 2>&1 || { rc=$? && >&2 echo "The directory ${l_directory} does not exist and could not be created" && return $rc; }
    fi

    #Check if the direcotory is writeable
    if [[ ! -w "${l_directory}" ]]
    then
        #The directory is not writeable, lets try to change that
        chmod ugo+w "${l_directory}" 1>/dev/null 2>&1 || { rc=$? && >&2 echo "The directory ${l_directory} can not be written to and permissions could not be modified" && return $rc; }
    fi

    #No Error
    return 0
}

#--------------------------------------------------------------------------
#    FUNCTION       f_setup_file
#    SYNTAX         f_setup_file <file_name>
#    DESCRIPTION    Accepts full file path and verifies if it can be written to
#                   0=Success
#                   1=Failure
#                   2=Error
#--------------------------------------------------------------------------
f_setup_file() #function_version=0.1.1
{
    #Validate the number of passed variables
    if [[ $# -ne 1 ]]
    then
        #Invalid number of arguments
        >&2 echo "Received an invalid number of arguments"
        return 2
    fi

    #Assign variables passed
    declare l_file_path=$1; shift
    typeset l_directory="${l_file_path%/*}"

    f_setup_directory "${l_directory}" || return $?

    #Check if the file already exists
    if [[ -a "${l_file_path}" ]]
    then
        #The file already exists, is it writable?
        if [[ ! -w "${l_file_path}" ]]
        then
            #The file exists but is NOT writeable, lets try changing it
            chmod ugo+w "${l_file_path}" 1>/dev/null 2>&1 || { rc=$? && >&2 echo "File ${l_file_path} exists but is not writeable and permissions could not be modified" && return $rc; }
        fi
    else
        #The file does not exist, lets touch it
        touch "${l_file_path}" 1>/dev/null 2>&1 || { rc=$? && >&2 echo "File ${l_file_path} does not exist and could not be created" && return $rc; }
    fi

    #No Error
    return 0
}

#--------------------------------------------------------------------------
#     MAIN
#--------------------------------------------------------------------------
f_main() #function_version=0.1.6
{
    #getopt is required, make sure it's available
    # -use ! and PIPESTATUS to get exit code with errexit set
    ! getopt --test > /dev/null 
    if [[ ${PIPESTATUS[0]} -ne 4 ]]
    then
        >&2 echo "enhanced getopt is required for this script but not available on this system"
        f_script_exit 1
    fi

    declare l_options=e:f:l:u:
    declare l_options_long=email:,filesystem:,lowerthreshold:,upperthreshold:

    # -use ! and PIPESTATUS to get exit code with errexit set
    ! l_options_parsed=$(getopt --options=$l_options --longoptions=$l_options_long --name "$0" -- "$@")
    if [[ ${PIPESTATUS[0]} -ne 0 ]]
    then
        # getopt did not like the parameters passed
        >&2 echo "getopt did not like the parameters passed"
        f_script_exit 1
    fi

    # read getopt’s output this way to handle the quoting right:
    eval set -- "$l_options_parsed"

    # now enjoy the options in order and nicely split until we see --
    while true
    do
        case "$1" in
            -e|--email)
                g_email_addresses="$2"
                shift 2
                ;;
            -f|--filesystem)
                g_filesystem="$2"
                shift 2
                ;;
            -l|--lowerthreshold)
                g_lower_threshold="$2"
                shift 2
                ;;
            -u|--upperthreshold)
                g_upper_threshold="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                >&2 echo "getopt parsing error"
                f_script_exit 1
                ;;
        esac
    done

    #Check for required parameter
    if [[ -z "${g_filesystem}" ]]
    then
        >&2 echo "-f|--filesystem parameter is required for this script"
        f_script_usage
    fi

    #Check for required parameter
    if [[ -z "${g_lower_threshold}" ]]
    then
        >&2 echo "-l|--lowerthreshold parameter is required for this script"
        f_script_usage
    fi

    #Check for required parameter
    if [[ -z "${g_upper_threshold}" ]]
    then
        >&2 echo "-u|--upperthreshold parameter is required for this script"
        f_script_usage
    fi

    #Make sure the passed filesystem exists
    df -m "${g_filesystem}" 1>/dev/null 2>&1 || { rc=$? && >&2 echo "Filesystem ${g_filesystem} not found" && f_script_exit $rc; }

    #Gather lsof path (/sbin/lsof or /usr/sbin/lsof)
    l_lsof_path=$([[ -f /sbin/lsof ]] && echo '/sbin/lsof' || echo '/usr/sbin/lsof')

    #Validate any dependencies we require exist
    f_check_dependencies ${l_lsof_path} || f_script_exit $?

    #Setup PID tracking file
    g_pid_tracker_file="${g_log_path}/pid.${g_script_flags_hash}.tracker"
    f_setup_file "${g_pid_tracker_file}"

    #Setup tmp tracker file
    g_pid_tracker_file_tmp=$(mktemp ${g_script_name}.XXXXX)

    #Add lsof output for the filesystem
    l_lsof_output=$(mktemp ${g_script_name}.XXXXX)
    ${l_lsof_path} "${g_filesystem}" | tail -n +2 > ${l_lsof_output} 2>/dev/null

    if [[ $(awk -v l_lower_threshold="${g_lower_threshold}" '$7>l_lower_threshold{print $2" "$7" "$9}' ${l_lsof_output} | wc -l) -gt 0 ]]
    then
        #Output filesystem information
        l_df_output=$(mktemp ${g_script_name}.XXXXX)
        df -Pm "${g_filesystem}" | awk '{print $3}' 1>${l_df_output} 2>/dev/null

        i=0
        awk -v l_lower_threshold="${g_lower_threshold}" '$7>l_lower_threshold{print $2" "$7" "$9}' ${l_lsof_output} | while read line
        do
            #Parse LSOF output for data
            l_offending_pid[${i}]=$(echo ${line} | cut -d' ' -f1)
            l_offending_file_size[${i}]=$(echo ${line} | cut -d' ' -f2)
            l_offending_file_path[${i}]="$(echo ${line} | cut -d' ' -f3-)"

            #Add this PID to a new tracking file
            echo "${l_offending_pid[${i}]} ${l_offending_file_path[${i}]}" >> ${g_pid_tracker_file_tmp}

            #Check if we've already gathered data for this pid
            if [[ $(grep -wc "${l_offending_pid[${i}]} ${l_offending_file_path[${i}]}" ${g_pid_tracker_file}) -eq 0 ]] || [[ ${l_offending_file_size[${i}]} -gt ${g_upper_threshold} ]]
            then
                #Gather data for this NEW or upper threshold pid
                l_offending_pid_data_gather[${i}]=1

                #See if the PID is in monsql
                l_offending_pid_monsql[${i}]="$(grep -w ${l_offending_pid[${i}]} ${l_monsql_output})"

                #Get process details
                l_offending_pid_details[${i}]="$(ps fup ${l_offending_pid[${i}]})"

                #Check if this PID/file has exceeded the upper limit
                if [[ $(awk -v l_upper_threshold="${g_upper_threshold}" '$7>l_upper_threshold{print $2" "$7" "$9}' ${l_lsof_output} | grep -c ${l_offending_pid[${i}]}) -gt 0 ]]
                then
                    #Grab all files associated with this pid
                    l_all_offending_file_paths=$(awk -v l_offending_pid="${l_offending_pid}" '{if ($2==l_offending_pid && $5!="DIR") {print $9}}' "${l_lsof_output}" | xargs)

                    #Kill this pid
                    kill -9 ${l_offending_pid[${i}]}

                    #Delete the related files for this PID so they're gone once the process dies
                    rm -f ${l_all_offending_file_paths} 2>/dev/null

                    #Validate the PID was killed
                    #

                    #Track that we killed this PID
                    l_offending_pid_killed[${i}]=1
                fi
            fi

            #Send emails for data gathered PIDs
            if [[ ${l_offending_pid_data_gather[${i}]} -eq 1 ]]
            then
                #Create the message body
                l_email_body="${g_log_path}/${g_script_name}.${g_time_stamp}.email"
                f_setup_file "${l_email_body}" || { rc=$? && >&2 echo "Validating email body file ${g_email_body} failed" && f_script_exit $rc; }

                #Change the email subject if we killed the pid
                if [[ ${l_offending_pid_killed[${i}]} -eq 1 ]]
                then
                    l_email_subject="${g_local_node} - ${g_filesystem} - ${l_offending_pid[${i}]} - Killed"
                else
                    l_email_subject="${g_local_node} - ${g_filesystem} - ${l_offending_pid[${i}]}"
                fi
                
                {
                    echo "PID SIZE FILE"
                    echo "${l_offending_pid[${i}]} ${l_offending_file_size[${i}]} ${l_offending_file_path[${i}]}"
                    echo ""
                    echo "PS OUTPUT"
                    echo "${l_offending_pid_details[${i}]}"
                    echo ""
                    echo "DF OUTPUT"
                    cat ${l_df_output}
                } >> ${l_email_body}

                #Send the email
                if [[ -n ${g_email_addresses:-} ]]
                then
                    mail -s "${l_email_subject}" "${g_email_addresses}" < <(cat ${l_email_body}) || >&2 echo "Sending the email notification failed."
                fi
            fi

            ((i+=1))
        done
    fi

    #Update the tracking file with new data
    mv ${g_pid_tracker_file_tmp} ${g_pid_tracker_file}

    f_script_exit "${g_exit_code:-0}"
}

#Save information about our script
g_script_file="${0##*/}"
g_script_name="${g_script_file%.*}"
g_script_extension="${g_script_file##*.}"
g_script_path=$(readlink -f "$0")
g_script_dir="${g_script_path%/*}"
g_script_flags="$@"
g_script_path_hash=$(echo "${g_script_path}" | cksum 2>/dev/null| awk '{print $1}')
g_script_flags_hash=$(echo "$@" | cksum 2>/dev/null| awk '{print $1}')

#Pulls the local node name, not including any suffix
g_local_node=$(hostname -s)
g_local_node_fqdn=$(hostname -f)
g_local_node_os=$(uname)
g_local_node_os_version=$(cat /etc/system-release 2>/dev/null || cat /etc/oracle-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || echo "Unknown")
g_local_node_os_version=${g_local_node_os_version##* }

#Identifies who is exeucting this script
g_username=$(whoami)

#Timestamp
g_date_stamp=$(date +"%Y.%m.%d")
g_time_stamp=$(date +"%Y.%m.%d.%H.%M.%S")
g_month_stamp=$(date +"%Y-%m")

#Various log files
g_log_dir="/usr/local/bin"
g_log_path="${g_log_dir}/${g_script_name}"
g_log_file="${g_log_path}/${g_script_name}.${g_script_flags_hash}.${g_time_stamp}.log"
g_log_retention=7

#Setup Logs
f_setup_file "${g_log_file}" || { rc=$? && >&2 echo "Validating logfile ${g_log_file} failed" && f_script_exit $rc; }

#See if this script is already running
g_pid_file="/var/run/${g_script_name}_${g_script_flags_hash}.pid"
f_check_execution "${g_pid_file}" || f_script_exit $?

#Set signal handlers to run our script_exit function
trap 'rc=$?; f_script_exit $rc' 0 1 2 3 15

#need to include this for millennium interaction
export TERM=xterm

#Check OS
if [[ "${g_local_node_os}" != "Linux" ]]
then
    >&2 echo ""
    >&2 echo " !!!! Warning: This script was not tested on anything but Linux, proceed at your own risk" | tee -a "${g_log_file}"
    >&2 echo ""
fi

#Execute main
#This syntax is necessary to tee all output to a logfile without calling a subshell. AKA, without using a |
f_main "$@" > >(tee "${g_log_file}") 2>&1

#This exist only exists as a fail safe. Always exit from your main function
f_script_exit 0
