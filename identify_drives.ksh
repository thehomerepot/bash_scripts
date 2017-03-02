#!/bin/ksh
#Variable to keep track of version for auditing purposes
SCRIPT_VERSION=1.2.0
#--------------------------------------------------------------------------
#     Name          : identifyDrives.ksh
#     Purpose       : Identify drives on your system
#     Version       : 1.2.0
#     Usage         : ./identifyDrives.ksh
#
#     Change Log    : v1.2.0  2016-01-20
#                       - Rewrote the script to be more accurate based on enclosure settings
#                       - Added HDD Temperatures
#                       - Added creation of vdev_id.conf file
#
#                   : v1.1.0  2015-11-11
#                       - Rewrote the script to be more simplified and to include HDD temps
#
#                   : v1.0.0  2014-10-09
#                       -    Original Version
#
#--------------------------------------------------------------------------

#--------------------------------------------------------------------------
#    FUNCTION      checkPrerequisites
#    SYNTAX        checkPrerequisite
#    DESCRIPTION   Checks things needed for this script
#--------------------------------------------------------------------------
function checkPrerequisites
{
     #Define variables as local first
     typeset checkSAS2IRCU
     typeset checkHDDTEMP
     typeset checkFAIL

     #Lets audit for installed software that we use for this script
     checkFAIL="FALSE"
     checkSAS2IRCU=$(which sas2ircu 2>/dev/null | wc -l)
     checkHDDTEMP=$(which hddtemp 2>/dev/null | wc -l)

     if [[ ${checkSAS2IRCU} -lt 1 ]]
     then
          checkFAIL="TRUE"
          echo "sas2ircu was not found to be installed. It is required for this script."
          echo ""
     fi

     if [[ ${checkHDDTEMP} -lt 1 ]]
     then
          checkFAIL="TRUE"
          echo "hddtemp was not found to be installed. It is required for this script."
          echo ""
     fi

     if [[ "${checkFAIL}" = "TRUE" ]]
     then
          #Echo failure to the log file
          echo "There were failures checking for pre-requisites. The script cannot continue."

          #Exit with failure
          exit 1
     fi
}

#--------------------------------------------------------------------------
#     FUNCTION      usage
#     SYNTAX        usage
#     DESCRIPTION   Displays proper usage syntax for the script
#--------------------------------------------------------------------------
function usage
{
     echo "-----------------------------------------------------------"
     echo "Usage   : ./${scriptName}.${scriptExtension}"
     echo "-----------------------------------------------------------"
     echo ""
     exit 3
}

#--------------------------------------------------------------------------
#     MAIN
#--------------------------------------------------------------------------

#Pulls the script name
scriptName=$(echo $(basename ${0}) | cut -d"." -f1)
scriptExtension=$(echo $(basename ${0}) | cut -d"." -f2)

#Formatting of the timestamp to use
timeStamp=$(date +"%yY-%mM-%dD-%HH-%MM")

#Pulls the local node name, not including any suffix
localNode=$(hostname | cut -d"." -f1)

#Initialize our exit code
exitCode=0

#Make sure that the root user is executing the script
CURRENT_USER=$(whoami)
if [[ $CURRENT_USER != "root" ]]
then
     #Not ROOT. Blow up!
     echo "-----------------------------------------------------------"
     echo "ERROR   : This script must be executed as the root user."
     echo "-----------------------------------------------------------"
     echo ""
     exit 3
fi

#Verify we can run
checkPrerequisites

#Find the controller indexes
i=0
sas2ircu list | awk 'c-->0;$0~s{if(b)for(c=b+1;c>1;c--)print r[(NR-c+1)%b];print;c=a}b{r[NR%b]=$0}' b=0 a=1 s="-----" | egrep -v '(-----)' | awk '{print $1}' | while read line
do
     controllerIDs[i]=$line
     ((i+=1))
done

numControllers=${#controllerIDs[*]}

#Get All Enclosure ID's
i=0
while [[ $i -lt $numControllers ]]
do
     enclosureIDs[i]=$(sas2ircu ${i} display | egrep '(Enclosure#)' | awk '{print $3}')
     ((i+=1))
done

#Find out how many unique enclosures there are
numEnclosures=$(echo ${enclosureIDs[@]} | tr ' ' '\n' | sort -u | wc -l)

#Define the column headers
col[0]="Enc#"
col[1]="Slot#"
col[2]="State"
col[3]="SizeInMB"
col[4]="Manuf."
col[5]="Model#"
col[6]="Serial#"
col[7]="Dev_Path"
col[8]="vDev_Alias"
col[9]="Protocol"
col[10]="Temp-F"
col[11]="SAS_Addr"

#Initialize the column header widths
i=0
while [[ $i -lt ${#col[*]} ]]
do
    len[$i]=${#col[$i]}
    ((i+=1))
done

#Initialize the number of drives variable
numAllDrives=0

#Parse data for all attached devices on each controller
i=0
while [[ $i -lt ${numControllers} ]]
do
    c=-1
	sas2ircu ${i} display | sed -n \
	-e '/^\s\sEnclosure\s#.*$/p' \
	-e '/^\s\sSlot\s#.*$/p' \
	-e '/^\s\sState.*$/p' \
	-e '/^\s\sSize.*$/p' \
	-e '/^\s\sManufacturer.*$/p' \
	-e '/^\s\sModel\sNumber.*$/p' \
	-e '/^\s\sSerial\sNo.*$/p' \
	-e '/^\s\sGUID.*$/p' \
	-e '/^\s\sProtocol.*$/p' \
    -e '/^\s\sSAS\sAddress.*$/p' | while read line
	do
		descriptor=$(echo $line | awk '{print $1}')
		case $descriptor in
		Enclosure)
            #Define the index value of the column array 1 time so it's easy to change later
            x=0
			if [[ $c -ge 0 ]]
			then
				row[${i},${c}]=${devEnclosure[${i},${c}]}"!"${devSlot[${i},${c}]}"!"${devState[${i},${c}]}"!"${devSizeMB[${i},${c}]}"!"${devManufacturer[${i},${c}]}"!"${devModelNumber[${i},${c}]}"!"${devSerialNumber[${i},${c}]}"!"${devPath[${i},${c}]}"!"${devAlias[${i},${c}]}"!"${devProtocol[${i},${c}]}"!"${devTemp[${i},${c}]}
			fi
			((c+=1))
			devEnclosure[${i},${c}]=$(echo $line | cut -d':' -f2 | sed -e 's/^[ \t]*//;s/[ \t]*$//')
            [[ ${#devEnclosure[${i},${c}]} -gt ${len[${x}]} ]] && len[${x}]=${#devEnclosure[${i},${c}]}
		;;
		Slot)
            x=1
			devSlot[${i},${c}]=$(echo $line | cut -d':' -f2 | sed -e 's/^[ \t]*//;s/[ \t]*$//')
            #Make slot number 2 digits
            while test "${#devSlot[${i},${c}]}" -lt 2; do devSlot[${i},${c}]="0${devSlot[${i},${c}]}"; done
            [[ ${#devSlot[${i},${c}]} -gt ${len[${x}]} ]] && len[${x}]=${#devSlot[${i},${c}]}
		;;
		State)
            x=2
			devState[${i},${c}]=$(echo $line | cut -d':' -f2 | sed -e 's/^[ \t]*//;s/[ \t]*$//')
            [[ ${#devState[${i},${c}]} -gt ${len[${x}]} ]] && len[${x}]=${#devState[${i},${c}]}
		;;
		Size)
            x=3
			devSizeMB[${i},${c}]=$(echo $line | cut -d':' -f2 | sed -e 's/^[ \t]*//;s/[ \t]*$//' | cut -d'/' -f1)
            [[ ${#devSizeMB[${i},${c}]} -gt ${len[${x}]} ]] && len[${x}]=${#devSizeMB[${i},${c}]}
		;;
		Manufacturer)
            x=4
			devManufacturer[${i},${c}]=$(echo $line | cut -d':' -f2 | sed -e 's/^[ \t]*//;s/[ \t]*$//')
            [[ ${#devManufacturer[${i},${c}]} -gt ${len[${x}]} ]] && len[${x}]=${#devManufacturer[${i},${c}]}
		;;
		Model)
            x=5
			devModelNumber[${i},${c}]=$(echo $line | cut -d':' -f2 | sed -e 's/^[ \t]*//;s/[ \t]*$//')
            [[ ${#devModelNumber[${i},${c}]} -gt ${len[${x}]} ]] && len[${x}]=${#devModelNumber[${i},${c}]}
		;;
		Serial)
            x=6
			devSerialNumber[${i},${c}]=$(echo $line | cut -d':' -f2 | sed -e 's/^[ \t]*//;s/[ \t]*$//')
            [[ ${#devSerialNumber[${i},${c}]} -gt ${len[${x}]} ]] && len[${x}]=${#devSerialNumber[${i},${c}]}
		;;
		GUID)
			devGUID[${i},${c}]=$(echo $line | cut -d':' -f2 | sed -e 's/^[ \t]*//;s/[ \t]*$//')

            #x=7
			#devPath[${i},${c}]=$(readlink -f /dev/disk/by-id/wwn-0x${devGUID[${i},${c}]})
            #[[ ${#devPath[${i},${c}]} -gt ${len[${x}]} ]] && len[${x}]=${#devPath[${i},${c}]}
            #[[ -n ${devPath[${i},${c}]} ]] && ((numAllDrives+=1)) && devTemp[${i},${c}]=$(hddtemp -u F -n ${devPath[${i},${c}]})

			#linkWWN[${i},${c}]=$(find -L /dev/disk/by-id/ -samefile ${devPath[${i},${c}]} 2>/dev/null | grep -i wwn)
			#linkVDEV[${i},${c}]=$(find -L /dev/disk/by-vdev/ -samefile ${devPath[${i},${c}]} 2>/dev/null )
			#linkATA[${i},${c}]=$(find -L /dev/disk/by-id/ -samefile ${devPath[${i},${c}]} 2>/dev/null | grep -i ata)
			#linkSCSI[${i},${c}]=$(find -L /dev/disk/by-id/ -samefile ${devPath[${i},${c}]} 2>/dev/null | grep -i scsi)
			#linkPATH[${i},${c}]=$(find -L /dev/disk/by-path/ -samefile ${devPath[${i},${c}]} 2>/dev/null )
		;;
		Protocol)
            x=9
			devProtocol[${i},${c}]=$(echo $line | cut -d':' -f2 | sed -e 's/^[ \t]*//;s/[ \t]*$//')
            [[ ${#devProtocol[${i},${c}]} -gt ${len[${x}]} ]] && len[${x}]=${#devProtocol[${i},${c}]}
		;;
        SAS)
			devSAS[${i},${c}]=$(echo $line | cut -d':' -f2 | sed -e 's/^[ \t]*//;s/[ \t]*$//;s/-//g')

            x=7
            devFile=$(find /dev/disk/by-path -name "*${devSAS[${i},${c}]}*" | grep -v part)
			devPath[${i},${c}]=$(readlink -f ${devFile})
            [[ ${#devPath[${i},${c}]} -gt ${len[${x}]} ]] && len[${x}]=${#devPath[${i},${c}]}
            [[ -n ${devPath[${i},${c}]} ]] && ((numAllDrives+=1)) && devTemp[${i},${c}]=$(hddtemp -u F -n ${devPath[${i},${c}]})

			linkWWN[${i},${c}]=$(find -L /dev/disk/by-id/ -samefile ${devPath[${i},${c}]} 2>/dev/null | grep -i wwn)
			linkVDEV[${i},${c}]=$(find -L /dev/disk/by-vdev/ -samefile ${devPath[${i},${c}]} 2>/dev/null )
			linkATA[${i},${c}]=$(find -L /dev/disk/by-id/ -samefile ${devPath[${i},${c}]} 2>/dev/null | grep -i ata)
			linkSCSI[${i},${c}]=$(find -L /dev/disk/by-id/ -samefile ${devPath[${i},${c}]} 2>/dev/null | grep -i scsi)
			linkPATH[${i},${c}]=$(find -L /dev/disk/by-path/ -samefile ${devPath[${i},${c}]} 2>/dev/null )
            
            x=8
			devAlias[${i},${c}]=$(basename ${linkVDEV[${i},${c}]} 2>/dev/null )
            [[ ${#devAlias[${i},${c}]} -gt ${len[${x}]} ]] && len[${x}]=${#devAlias[${i},${c}]}

            x=10
            [[ ${#devTemp[${i},${c}]} -gt ${len[${x}]} ]] && len[${x}]=${#devTemp[${i},${c}]}
		;;
		\?)
			clear
		;;
		*)
			clear
		;;
		esac
	done
    row[${i},${c}]=${devEnclosure[${i},${c}]}"!"${devSlot[${i},${c}]}"!"${devState[${i},${c}]}"!"${devSizeMB[${i},${c}]}"!"${devManufacturer[${i},${c}]}"!"${devModelNumber[${i},${c}]}"!"${devSerialNumber[${i},${c}]}"!"${devPath[${i},${c}]}"!"${devAlias[${i},${c}]}"!"${devProtocol[${i},${c}]}"!"${devTemp[${i},${c}]}
	(( i+=1 ))
done

#Echo Info
echo ""
echo "GENERAL INFO"
echo "-------------------------------------------------"
echo "Number of Enclosures         = "${numEnclosures}
echo "Number of Controllers        = "${numControllers}
echo "Number of Attached Drives    = "${numAllDrives}

i=0
while [[ $i -lt ${numControllers} ]]
do
    echo ""
    echo "CONTROLLER 0"
    echo "-------------------------------------------------"
    printf "%-${len[0]}s%1s%-${len[1]}s%1s%-${len[2]}s%1s%-${len[3]}s%1s%-${len[4]}s%1s%-${len[5]}s%1s%-${len[6]}s%1s%-${len[7]}s%1s%-${len[8]}s%1s%-${len[9]}s%1s%-${len[10]}s\n" "${col[0]}" " " "${col[1]}" " " "${col[2]}" " " "${col[3]}" " " "${col[4]}" " " "${col[5]}" " " "${col[6]}" " " "${col[7]}" " " "${col[8]}" " " "${col[9]}" " " "${col[10]}"
    > /tmp/vdev_id.conf
    c=0
    while [[ $c -lt ${numAllDrives} ]]
    do
        printf "%${len[0]}s%1s%${len[1]}s%1s%-${len[2]}s%1s%${len[3]}s%1s%-${len[4]}s%1s%-${len[5]}s%1s%-${len[6]}s%1s%-${len[7]}s%1s%-${len[8]}s%1s%-${len[9]}s%1s%-${len[10]}s\n" "${devEnclosure[${i},${c}]}" " " "${devSlot[${i},${c}]}" " " "${devState[${i},${c}]}" " " "${devSizeMB[${i},${c}]}" " " "${devManufacturer[${i},${c}]}" " " "${devModelNumber[${i},${c}]}" " " "${devSerialNumber[${i},${c}]}" " " "${devPath[${i},${c}]}" " " "${devAlias[${i},${c}]}" " " "${devProtocol[${i},${c}]}" " " "${devTemp[${i},${c}]}"
        echo "alias Bay${devSlot[${i},${c}]} $(basename ${linkATA[${i},${c}]})" >> /tmp/vdev_id.conf
        (( c+=1 ))
    done
    (( i+=1 ))
done

echo ""
echo "ENABLE LED COMMAND"
echo "------------------------------------"
echo "sas2ircu <controller> locate <encl:slot> ON"

echo ""
echo "DISABLE LED COMMAND"
echo "------------------------------------"
echo "sas2ircu <controller> locate <encl:slot> OFF"

echo ""
echo "VDEV CONFIGURATION FILE"
echo "------------------------------------"
echo "A vdev_id.conf file based on this data is located at /tmp/vdev_id.conf"
echo "To use the new vdev file, do the following"
echo "  cat /tmp/vdev_id.conf > /etc/zfs/vdev_id.conf"
echo "  udevadm trigger"
echo ""
echo ""

exit
