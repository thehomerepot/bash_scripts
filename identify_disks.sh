#!/bin/bash
#--------------------------------------------------------------------------
#   Name            : identify_disks.sh
#   Purpose         : Gather information about the hard drives in your system
#   Author          : Ryan Flagler
#   Source          : https://github.com/thehomerepot/bash_scripts/blob/master/identify_disks.sh
#   Usage           : ./identify_drives.sh
#--------------------------------------------------------------------------

#Variable to keep track of version for auditing purposes
script_version=1.3.4

#Set environment options
#set -o errexit      # -e Any non-zero output will cause an automatic script failure
#set -o pipefail     #    Any non-zero output in a pipeline will return a failure
#set -o noclobber    # -C Prevent output redirection from overwriting an existing file
#set -o nounset      # -u Prevent use of uninitialized variables
#set -o xtrace       # -x Same as verbose but with variable expansion

#--------------------------------------------------------------------------
#    FUNCTION       f_check_execution
#    SYNTAX         f_check_execution <PID_FILE>
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
        rm "${l_pid_file:4}" 1>/dev/null 2>&1 || (rc=$? && >&2 echo "Lock file ${l_pid_file:4} could not be removed" && return $rc)
    else
        #Use a file descriptor to track a file for locking so we can utilize flock
        exec 9>"${l_pid_file}" || (rc=$? && >&2 echo "File descriptor redirection to ${l_pid_file} failed" && return $rc)

        #Acquire an exclusive lock to file descriptor 9 or fail
        flock -n 9 1>/dev/null 2>&1 || (rc=$? && >&2 echo "${l_pid_file} already has a file lock" && return $rc)
    fi
}

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
    if [[ ! -s "${g_log_file}" ]]
    then
        rm "${g_log_file}" || >&2 echo "Removing null log file ${g_log_file} failed"
    fi

    #Check if we should send an email
    #if [[ "${l_exit_code}" -ne 0 ]] && [[ -n ${g_email_addresses:-} ]]
    #then
    #    #Cleanup non-ascii characters
    #    tr -cd '\11\12\15\40-\176' < "${g_log_file}" >| "${g_log_file}.email"
    #
    #    #Add space to the end of lines to prevent outlook from removing newlines
    #    sed -i 's/$/   /g' "${g_log_file}.email"
    #
    #    #Send the email
    #    mail -s "${g_script_file} Notification" "${g_email_addresses}" < "${g_log_file}.email" || >&2 echo "Sending the email notification failed."
    #fi

    #Exit
    exit "${l_exit_code}"
}

#--------------------------------------------------------------------------
#     FUNCTION      f_script_usage
#     SYNTAX        f_script_usage
#     DESCRIPTION   Displays proper usage syntax for the script
#--------------------------------------------------------------------------
f_script_usage()
{
    echo ""
    echo "Usage: ./${SCRIPT_NAME}.${SCRIPT_EXTENSION}"
    echo "  OPTIONAL PARAMETERS"
    echo "      -m|--map        : The file containing enclosure/bay/phy mapping"
    echo ""

    f_script_exit 1
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
#     MAIN
#--------------------------------------------------------------------------
f_main()
{
    #getopt is required, make sure it's available
    # -use ! and PIPESTATUS to get exit code with errexit set
    ! getopt --test >| /dev/null
    if [[ ${PIPESTATUS[0]} -ne 4 ]]
    then
        >&2 echo "enhanced getopt is required for this script but not available on this system"
        f_script_exit 1
    fi

    declare l_options=m:
    declare l_options_long=map:

    # -use ! and PIPESTATUS to get exit code with errexit set
    ! l_options_parsed=$(getopt --options=$l_options --longoptions=$l_options_long --name "$0" -- "$@")
    if [[ ${PIPESTATUS[0]} -ne 0 ]]
    then
        # getopt did not like the parameters passed
        >&2 echo "getopt did not like the parameters passed"
        f_script_exit 1
    fi

    # read getopt's output this way to handle the quoting right:
    eval set -- "$l_options_parsed"

    # now enjoy the options in order and nicely split until we see --
    while true
    do
        case "$1" in
            -m|--map)
                g_map_file="${2}"
                shift 2
            ;;
            --)
                shift
                break
                ;;
            *)
                f_script_usage
                ;;
        esac
    done

    #Check for pre-requisites
    for prereq in lsscsi lsblk udevadm
    do
        if [[ -z $(which ${prereq} 2>/dev/null) ]]
        then
            l_prereq_check="FAIL"
            echo "${prereq} is a required tool. Make sure it is installed before executing this script"
        fi
    done

    if [[ -n $(which zdb 2>/dev/null) ]] && [[ -z $(which partx 2>/dev/null) ]]
    then
        echo "partx is a required tool. Make sure it is installed before executing this script"
    fi

    #Find hardware information
    enclosure_identifiers=($(find /sys/class/sas_device/expander*/device/port*/end_device*/ -name "enclosure_identifier" -exec cat {} \; | sed 's/.*0x//g' | sort -u))

    original_ifs=$IFS
    IFS='!'
    disk_wwn=($(lsblk --paths --nodeps --pairs --output WWN,TYPE,PHY-SEC,LOG-SEC,TRAN,MODEL | grep -Ev 'WWN=""|nvme' | grep -E 'TYPE="disk"' | sed 's/0x//g' | sort -u | grep -o 'WWN="[^"]*["$]' | cut -d'"' -f2 | tr '\n' '!'))
    disk_sector_physical=($(lsblk --paths --nodeps --pairs --output WWN,TYPE,PHY-SEC,LOG-SEC,TRAN,MODEL | grep -Ev 'WWN=""|nvme' | grep -E 'TYPE="disk"' | sed 's/0x//g' | sort -u | grep -o 'PHY-SEC="[^"]*["$]' | cut -d'"' -f2 | tr '\n' '!'))
    disk_sector_logical=($(lsblk --paths --nodeps --pairs --output WWN,TYPE,PHY-SEC,LOG-SEC,TRAN,MODEL | grep -Ev 'WWN=""|nvme' | grep -E 'TYPE="disk"' | sed 's/0x//g' | sort -u | grep -o 'LOG-SEC="[^"]*["$]' | cut -d'"' -f2 | tr '\n' '!'))
    disk_transport=($(lsblk --paths --nodeps --pairs --output WWN,TYPE,PHY-SEC,LOG-SEC,TRAN,MODEL | grep -Ev 'WWN=""|nvme' | grep -E 'TYPE="disk"' | sed 's/0x//g' | sort -u | grep -o 'TRAN="[^"]*["$]' | cut -d'"' -f2 | tr '\n' '!'))
    disk_model=($(lsblk --paths --nodeps --pairs --output WWN,TYPE,PHY-SEC,LOG-SEC,TRAN,MODEL | grep -Ev 'WWN=""|nvme' | grep -E 'TYPE="disk"' | sed 's/0x//g' | sort -u | grep -o 'MODEL="[^"]*["$]' | cut -d'"' -f2 | tr -d ' ' | tr '\n' '!'))
    IFS=$original_ifs

    #Create a temp file for output
    output_temp_file=$(mktemp)
    echo "ENCLOSURE  BAY  SIZE  MODEL  FIRMWARE  SERIAL  PATH  HCTL  MPATH  ZPOOL  ZPATH" > ${output_temp_file}

    #Parse through all hardware information and get detailed data
    cnt_i=0
    while [[ ${cnt_i} -lt ${#disk_wwn[@]} ]]
    do
        disk_path[${cnt_i}]=$(lsblk --paths --nodeps --pairs --output WWN,TYPE,NAME,HCTL,PHY-SEC,LOG-SEC,TRAN,MODEL | grep ${disk_wwn[${cnt_i}]} | grep -o 'NAME="[^"]*["$]' | cut -d'"' -f2 | xargs | tr ' ' ',')
        disk_hctl[${cnt_i}]=$(lsblk --paths --nodeps --pairs --output WWN,TYPE,NAME,HCTL,PHY-SEC,LOG-SEC,TRAN,MODEL | grep ${disk_wwn[${cnt_i}]} | grep -o 'HCTL="[^"]*["$]' | cut -d'"' -f2 | cut -d':' -f1-3 | xargs | tr ' ' ',')
        disk_size[${cnt_i}]=$(lsscsi -g -s ${disk_hctl[${cnt_i}]%,*} 2>/dev/null | rev | awk '{print $1}' | rev )
        disk_firmware[${cnt_i}]=$(lsscsi ${disk_hctl[${cnt_i}]%,*} 2>/dev/null | rev | awk '{print $2}' | rev )

        #Check for multipath configuration
        disk_multipath[${cnt_i}]=$(find /dev/mapper -name "$(multipath -ll ${disk_path[${cnt_i}]%,*} 2>/dev/null | head -n 1 | awk '{print $1}')")
        if [[ -z ${disk_multipath[${cnt_i}]} ]]
        then
            disk_multipath[${cnt_i}]="N/A"
        fi

        #Check for zfs config
        if [[ -n $(which zdb 2>/dev/null) ]]
        then
            temp_zfs_pool=$(zdb -l ${disk_path[${cnt_i}]%,*} 2>/dev/null)
            return_code=$?
            if [[ ${return_code} -ne 0 ]]
            then
                for partition in $(partx --noheadings --raw --output NR ${disk_path[${cnt_i}]%,*} 2>/dev/null | xargs)
                do
                    temp_zfs_pool=$(zdb -l ${disk_path[${cnt_i}]%,*}${partition} 2>/dev/null)
                    return_code=$?
                    if [[ ${return_code} -eq 0 ]]
                    then
                        temp_disk_path=${disk_path[${cnt_i}]%,*}${partition}
                        break
                    fi
                done
            else
                temp_disk_path=${disk_path[${cnt_i}]%,*}
            fi
            if [[ -n ${temp_disk_path} ]]
            then
                disk_zfs_pool[${cnt_i}]=$(echo "${temp_zfs_pool}" | grep -Ew 'name:' | awk '{print $2}' | tr -d "'")
                disk_zfs_type[${cnt_i}]=$(zdb -l ${temp_disk_path} 2>/dev/null | grep -Ew 'type:' | head -n1 | awk '{print $2}' | tr -d "'")
                disk_zfs_id[${cnt_i}]=$(zdb -l ${temp_disk_path} 2>/dev/null | grep -Ew 'id:' | head -n1 | awk '{print $2}')
                for temp_zfs_path in $(zdb -l ${temp_disk_path} 2>/dev/null | grep -Ew 'path:' | awk '{print $2}' | tr -d "'" | xargs)
                do
                    temp_disk_serial=$(udevadm info --query=all --name=${temp_disk_path} 2>/dev/null | grep -o 'ID_SERIAL_SHORT=[^.]\+' | cut -d'=' -f2)
                    temp_zfs_serial_count=$(udevadm info --query=all --name=${temp_zfs_path} 2>/dev/null | grep -c ${temp_disk_serial})
                    if [[ ${temp_zfs_serial_count} -gt 0 ]]
                    then
                        disk_zfs_path[${cnt_i}]="${temp_zfs_path}"
                        break
                    fi
                done
                temp_disk_path=""
                print_zpool[${cnt_i}]="${disk_zfs_pool[${cnt_i}]}-${disk_zfs_type[${cnt_i}]}:${disk_zfs_id[${cnt_i}]}"
                print_zpath[${cnt_i}]="${disk_zfs_path[${cnt_i}]}"
            else
                print_zpool[${cnt_i}]="N/A"
                print_zpath[${cnt_i}]="N/A"
            fi
        else
            print_zpool[${cnt_i}]="N/A"
            print_zpath[${cnt_i}]="N/A"
        fi

        disk_bus[${cnt_i}]=$(udevadm info --query=all --name=${disk_path[${cnt_i}]%,*} | grep -o 'ID_BUS=[^.]\+' | cut -d'=' -f2)
        if [[ "${disk_bus[${cnt_i}]}" = "scsi" ]]
        then
            disk_serial[${cnt_i}]=$(udevadm info --query=all --name=${disk_path[${cnt_i}]%,*} | grep -o 'SCSI_IDENT_SERIAL=[^.]\+' | cut -d'=' -f2 | cut -c 1-8)
        elif [[ "${disk_bus[${cnt_i}]}" = "ata" ]]
        then
            disk_serial[${cnt_i}]=$(udevadm info --query=all --name=${disk_path[${cnt_i}]%,*} | grep -o 'ID_SERIAL_SHORT=[^.]\+' | cut -d'=' -f2 | cut -c 1-8)
        fi

        disk_sas_address[${cnt_i}]=$(lsscsi --transport -L ${disk_hctl[${cnt_i}]%,*} 2>/dev/null | grep -E 'sas_address' | sed 's/.*=0x//g')
        if [[ -z ${disk_sas_address[${cnt_i}]} ]]
        then
            disk_sas_address[${cnt_i}]="N/A"
        fi

        disk_root_path=$(find /sys/class/sas_device/expander*/device/phy*/port*/end_device*/sas_device/ -type d -name "end_device*" 2>/dev/null| grep -Ew ${disk_hctl[${cnt_i}]/,/|})
        disk_root_path=$(find /sys/class/sas_device/expander*/device/phy*/port*/end_device*/ -type d -name "target${disk_hctl[${cnt_i}]%,*}" 2>/dev/null)
        disk_root_path=$(dirname ${disk_root_path} 2>/dev/null)

        disk_enclosure_identifier[${cnt_i}]=$(cat ${disk_root_path}/sas_device/end_device*/enclosure_identifier 2>/dev/null | sed 's/.*0x//g')
        if [[ -n ${g_map_file} ]] && [[ $(grep -Ec "^enclosure ${disk_enclosure_identifier[${cnt_i}]:-NULL}" ${g_map_file} 2>/dev/null) -gt 0 ]]
        then
            print_enclosure_identifier[${cnt_i}]=$(grep -E "^enclosure ${disk_enclosure_identifier[${cnt_i}]}" ${g_map_file} | awk '{print $3}')
        else
            print_enclosure_identifier[${cnt_i}]=${disk_enclosure_identifier[${cnt_i}]}
        fi
        if [[ -z ${disk_enclosure_identifier[${cnt_i}]} ]]
        then
            disk_enclosure_identifier[${cnt_i}]="N/A"
            print_enclosure_identifier[${cnt_i}]="N/A"
        fi

        disk_phy_identifier[${cnt_i}]=$(cat ${disk_root_path}/sas_device/end_device*/phy_identifier 2>/dev/null | sed 's/.*0x//g')
        if [[ -n ${g_map_file} ]] && [[ $(grep -Ec "^phy ${disk_phy_identifier[${cnt_i}]}" ${g_map_file} 2>/dev/null) -gt 0 ]]
        then
            print_phy_identifier[${cnt_i}]=$(grep -E "^phy ${disk_phy_identifier[${cnt_i}]}" ${g_map_file} | awk '{print $3}')
        else
            print_phy_identifier[${cnt_i}]=${disk_phy_identifier[${cnt_i}]}
        fi
        if [[ -z ${disk_phy_identifier[${cnt_i}]} ]]
        then
            disk_phy_identifier[${cnt_i}]="N/A"
            print_phy_identifier[${cnt_i}]="N/A"
        fi

        disk_bay_identifier[${cnt_i}]=$(cat ${disk_root_path}/sas_device/end_device*/bay_identifier 2>/dev/null | sed 's/.*0x//g')
        if [[ -n ${g_map_file} ]] && [[ $(grep -Ec "^bay ${disk_bay_identifier[${cnt_i}]}" ${g_map_file} 2>/dev/null) -gt 0 ]]
        then
            print_bay_identifier[${cnt_i}]=$(grep -E "^bay ${disk_bay_identifier[${cnt_i}]}" ${g_map_file} | awk '{print $3}')
        else
            print_bay_identifier[${cnt_i}]=${disk_bay_identifier[${cnt_i}]}
        fi
        if [[ -z ${disk_bay_identifier[${cnt_i}]} ]]
        then
            disk_bay_identifier[${cnt_i}]="N/A"
            print_bay_identifier[${cnt_i}]="N/A"
        fi

        #Find all SAS addresses for a disk?
        #sdparm -t sas -p pcd /dev/sdb | grep -e 'SASA' | awk '{print $2}'

        echo "${print_enclosure_identifier[${cnt_i}]}  ${print_bay_identifier[${cnt_i}]}  ${disk_size[${cnt_i}]}  ${disk_model[${cnt_i}]}  ${disk_firmware[${cnt_i}]}  ${disk_serial[${cnt_i}]}  ${disk_path[${cnt_i}]} ${disk_hctl[${cnt_i}]} ${disk_multipath[${cnt_i}]}  ${print_zpool[${cnt_i}]}  ${print_zpath[${cnt_i}]}"

        ((cnt_i+=1))
    done | sort -k 1,1 -k 2,2n >> ${output_temp_file}

    column -t ${output_temp_file}
    rm ${output_temp_file}
}

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
g_log_dir="/var/log"
g_log_path="${g_log_dir}/${g_script_name}"
g_log_file="${g_log_path}/${g_script_name}.${g_time_stamp}.log"

#Setup Logs
f_setup_file "${g_log_file}" || (rc=$? && >&2 echo "Validating logfile ${g_log_file} failed" && f_script_exit $rc)

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
