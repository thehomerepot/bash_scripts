#!/bin/bash
#--------------------------------------------------------------------------
#   Name            : update_certs.sh
#   Purpose         : Update certificates from OPNSense to Nginx
#   URL             : https://github.com/thehomerepot/bash_scripts
#--------------------------------------------------------------------------
#Variable to keep track of version for auditing purposes
script_version=0.1.0

#Set environment options
#set -o errexit      # -e Any non-zero output will cause an automatic script failure
#set -o pipefail     #    Any non-zero output in a pipeline will return a failure
set -o noclobber    # -C Prevent output redirection from overwriting an existing file
set -o nounset      # -u Prevent use of uninitialized variables
#set -o xtrace       # -x Same as verbose but with variable expansion

#Global Variables
g_log_base_path="/mnt/storage/recovery"
g_retention_days=30

#What domain are we checking certs for
g_domain="thehomenet.org"

#OPNSense Configuration
g_opn_ip="192.168.20.1"
g_opn_user="certs"
g_opn_path="/var/etc/acme-client/home/${g_domain}"
g_opn_cert="fullchain.cer"
g_opn_key="${g_domain}.key"
g_opn_chain="ca.cer"

#Nginx Configuration
g_nginx_path="/etc/docker/containers/nginx-proxy/certs"
g_nginx_cert="${g_domain}.crt"
g_nginx_key="${g_domain}.key"
g_nginx_chain="${g_domain}.chain.pem"

#--------------------------------------------------------------------------
#    FUNCTION       f_script_exit
#    SYNTAX         f_script_exit <exitCode>
#    DESCRIPTION    Cleans up logs, traps, flocks, and performs any other exit tasks
#--------------------------------------------------------------------------
f_script_exit()
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
    if [[ ${l_exit_code} -ne 11  ]]
    then
        f_check_execution "STOP${g_pid_file}" || >&2 echo "Removing file descriptor locks failed"
    fi

    #Remove empty log files
    if [[ -f "${g_log_file}" ]] && [[ ! -s "${g_log_file}" ]]
    then
        rm "${g_log_file}" || >&2 echo "Removing null log file ${g_log_file} failed"
    fi

    #Cleanup before exiting
    rm -rf "${g_tmp_path}"

    #Cleanup old files
    while read -r line
    do
        rm "${line}" || >&2 echo "Removing old file ${line} failed"
    done < <(find "${g_log_path}" -type f -daystart -mtime +${g_retention_days} -print0 | xargs -0 grep -l ${g_domain})

    #Exit
    exit "${l_exit_code}"
}

#--------------------------------------------------------------------------
#    FUNCTION       f_check_execution
#    SYNTAX         f_check_execution <pid_file>
#    DESCRIPTION    This function identifies if there is already an instance of this script running
#                   0=Success
#                   1=Failure
#                   2=Error
#--------------------------------------------------------------------------
f_check_execution()
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
        flock -u 9 1>/dev/null 2>&1 || (rc=$? && >&2 echo "File ${l_pid_file:4} could not be unlocked" && return $rc)

        #Remove the lock file
        rm "${l_pid_file:4}" 1>/dev/null 2>&1
        if [[ -f "${l_pid_file:4}" ]]
        then
            >&2 echo "Lock file ${l_pid_file:4} could not be removed"
            return 1
        fi
    else
        #Use a file descriptor to track a file for locking so we can utilize flock
        exec 9>"${l_pid_file}" || (rc=$? && >&2 echo "File descriptor redirection to ${l_pid_file} failed" && return $rc)

        #Acquire an exclusive lock to file descriptor 9 or fail
        flock -n 9 1>/dev/null 2>&1 || (rc=$? && >&2 echo "${l_pid_file} already has a file lock" && return $rc)
    fi
}

#--------------------------------------------------------------------------
#    FUNCTION       f_setup_directory
#    SYNTAX         f_setup_directory <DirectoryName>
#    DESCRIPTION    Accepts full directory path and verifies if it can be written to
#                   0=Success
#                   1=Failure
#                   2=Error
#--------------------------------------------------------------------------
f_setup_directory()
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
    if [[ ! -a "${l_directory}" ]]
    then
        #The directory doesn't exist, try to create it
        mkdir -p "${l_directory}" 1>/dev/null 2>&1 || (rc=$? && >&2 echo "The directory ${l_directory} does not exist and could not be created" && return $rc)
    fi

    #Check if the direcotory is writeable
    if [[ ! -w "${l_directory}" ]]
    then
        #The directory is not writeable, lets try to change that
        chmod ugo+w "${l_directory}" 1>/dev/null 2>&1 || (rc=$? && >&2 echo "The directory ${l_directory} can not be written to and permissions could not be modified" && return $rc)
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
f_setup_file()
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
            chmod ugo+w "${l_file_path}" 1>/dev/null 2>&1 || (rc=$? && >&2 echo "File ${l_file_path} exists but is not writeable and permissions could not be modified" && return $rc)
        fi
    else
        #The file does not exist, lets touch it
        touch "${l_file_path}" 1>/dev/null 2>&1 || (rc=$? && >&2 echo "File ${l_file_path} does not exist and could not be created" && return $rc)
    fi

    #No Error
    return 0
}

#--------------------------------------------------------------------------
#    FUNCTION       f_update_certs
#    SYNTAX         f_update_certs
#    DESCRIPTION    Updates the certs
#                   0=Success
#                   1=Failure
#                   2=Error
#--------------------------------------------------------------------------
f_update_certs()
{
    echo "Copying ${g_opn_cert} to ${g_nginx_path}/${g_nginx_cert}"
    cp "${g_tmp_path}/${g_opn_cert}" "${g_nginx_path}/${g_nginx_cert}" 2>/dev/null || (rc=$? && >&2 echo "${g_opn_cert} could not be copied to ${g_nginx_path}/${g_nginx_cert}" && f_script_exit $rc)

    echo "Copying ${g_opn_key} to ${g_nginx_path}/${g_nginx_key}"
    cp "${g_tmp_path}/${g_opn_key}" "${g_nginx_path}/${g_nginx_key}" 2>/dev/null || (rc=$? && >&2 echo "${g_opn_key} could not be copied to ${g_nginx_path}/${g_nginx_key}" && f_script_exit $rc)

    echo "Copying ${g_opn_chain} to ${g_nginx_path}/${g_nginx_chain}"
    cp "${g_tmp_path}/${g_opn_chain}" "${g_nginx_path}/${g_nginx_chain}" 2>/dev/null || (rc=$? && >&2 echo "${g_opn_chain} could not be copied to ${g_nginx_path}/${g_nginx_chain}" && f_script_exit $rc)

    #No Error
    return 0
}

#--------------------------------------------------------------------------
#     MAIN
#--------------------------------------------------------------------------
f_main()
(
    #Copy the latest certs from OPNSense
    scp -oBatchMode=yes -i ~/.ssh/id_rsa -rp ${g_opn_user}@${g_opn_ip}:${g_opn_path}/* ${g_tmp_path}/ || (rc=$? && >&2 echo "Certs could not be copied from ${g_opn_user}@${g_opn_ip}:${g_opn_path}/*" && f_script_exit $rc)

    #Open up permissions on all the files
    chmod 777 ${g_tmp_path}/*
    
    #Check the cert file
    if [[ -f ${g_tmp_path}/${g_opn_cert} ]]
    then
        l_new_hash=$(cksum ${g_tmp_path}/${g_opn_cert} 2>/dev/null | awk '{print $1}')
        l_old_hash=$(cksum ${g_nginx_path}/${g_nginx_cert} 2>/dev/null | awk '{print $1}')
        if [[ ${l_new_hash} -ne ${l_old_hash} ]]
        then
            #Certs seem updated, update them all!
            echo "Source ${g_opn_cert} hash changed. Updating all certificates for this domain."
            f_update_certs
        fi
    else
        >&2 echo "Source ${g_opn_cert} file not found in download path. Cannot check hash."
    fi

    #Check the key file
    if [[ -f ${g_tmp_path}/${g_opn_key} ]]
    then
        l_new_hash=$(cksum ${g_tmp_path}/${g_opn_key} 2>/dev/null | awk '{print $1}')
        l_old_hash=$(cksum ${g_nginx_path}/${g_nginx_key} 2>/dev/null | awk '{print $1}')
        if [[ ${l_new_hash} -ne ${l_old_hash} ]]
        then
            #Certs seem updated, update them all!
            echo "Source ${g_opn_key} hash changed. Updating all certificates for this domain."
            f_update_certs
        fi
    else
        >&2 echo "Source ${g_opn_key} file not found in download path. Cannot check hash."
    fi

    #Check the chain file
    if [[ -f ${g_tmp_path}/${g_opn_chain} ]]
    then
        l_new_hash=$(cksum ${g_tmp_path}/${g_opn_chain} 2>/dev/null | awk '{print $1}')
        l_old_hash=$(cksum ${g_nginx_path}/${g_nginx_chain} 2>/dev/null | awk '{print $1}')
        if [[ ${l_new_hash} -ne ${l_old_hash} ]]
        then
            #Certs seem updated, update them all!
            echo "Source ${g_opn_chain} hash changed. Updating all certificates for this domain."
            f_update_certs
        fi
    else
        >&2 echo "Source ${g_opn_chain} file not found in download path. Cannot check hash."
    fi

    f_script_exit "${g_exit_code:-0}"
)

#Save information about our script
g_script_file="${0##*/}"
g_script_name="${g_script_file%.*}"
g_script_extension="${g_script_file##*.}"
g_script_path=$(readlink -f "$0")
g_script_dir="${g_script_path%/*}"
g_script_flags="$@"
g_script_path_hash=$(echo "${g_script_path}" | cksum 2>/dev/null| awk '{print $1}')

#See if this script is already running
g_pid_file="/var/run/${g_script_name}_${g_script_path_hash}.pid"
f_check_execution "${g_pid_file}" || f_script_exit 11

#Set signal handlers to run our script_exit function
trap 'rc=$?; f_script_exit $rc' 0 1 2 3 15

#Pulls the local node name, not including any suffix
g_local_node=$(hostname -s)
g_local_node_fqdn=$(hostname -f)
g_local_node_os=$(uname)

#Timestamp
g_date_stamp=$(date +"%Y.%m.%d")
g_time_stamp=$(date +"%Y.%m.%d.%H.%M.%S")

#Various log files
g_log_path="${g_log_base_path}/${g_script_name}"
g_log_file="${g_log_path}/${g_domain}.${g_time_stamp}.log"

#Setup Logs
f_setup_file "${g_log_file}" || (rc=$? && >&2 echo "Validating logfile ${g_log_file} failed" && f_script_exit $rc)

#Create temp directory
g_tmp_path=$(mktemp -d)

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