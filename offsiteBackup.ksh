#!/usr/bin/ksh
#Variable to keep track of version for auditing purposes
scriptVersion=1.0
#--------------------------------------------------------------------------
#    Name           : offsiteBackup.ksh
#    Purpose        : Backs up configured paths to an offsite location
#    Version        : 1.0
#    Usage          : offsiteBackup.ksh
#
#    Change Log     : v1.0    -    2014-10-08
#                             -    Initial Creation and Use for ubuntu 14.04
#--------------------------------------------------------------------------

#--------------------------------------------------------------------------
#    FUNCTION       checkExecution
#    SYNTAX         checkExecution
#    DESCRIPTION    This function identifies if there is already an instance of this script running
#                   0=Success
#                   1=Failure
#                   2=Error
#--------------------------------------------------------------------------
function checkExecution
{
     #Check for previously running script first
     if [[ -L ${pidFile} ]]
     then
          pid=$(ls -l ${pidFile} | sed 's/.*-> //')
          if [[ -d /proc/$pid ]]
          then
               #The script is already running
               echo "${scriptLogID}An instance of ${scriptName} is already running" >> ${logFile}
               exitScript 1
          else
               rm -f ${pidFile}
          fi
     fi

     #Since no previously running script was found, just keep track of the current instance
     echo "${scriptLogID}The script ${scriptName} is not already running. Creating ${pidFile}" >> ${logFile}
     ln -s $$ ${pidFile}
}

#--------------------------------------------------------------------------
#    FUNCTION      checkPrerequisites
#    SYNTAX        checkPrerequisite
#    DESCRIPTION   Checks dpkg for installed packages needed for this script
#--------------------------------------------------------------------------
function checkPrerequisites
{
     #Define variables as local first
     typeset checkLFTP
     typeset checkFAIL
     
     #Lets audit for installed software that we use for this script
     checkFAIL="FALSE"
     checkLFTP=$(dpkg --get-selections | grep -v deinstall | egrep -ic lftp)
     
     if [[ ${checkLFTP} -lt 1 ]]
     then
          checkFAIL="TRUE"
          echo "lftp was not found to be installed. It is required for this script." | tee -a ${tempFile}
          echo "    - You can install unrar with the following command" | tee -a ${tempFile}
          echo "    - sudo apt-get install -y lftp" | tee -a ${tempFile}
          echo ""  | tee -a ${tempFile}
     fi
     
     if [[ "${checkFAIL}" = "TRUE" ]]
     then
          #Echo failure to the log file
          echo "There were failures checking for pre-requisites. The script cannot continue." | tee -a ${tempFile}
          
          #Mail the failures
          mailx -s "${localNode}: Media Update Execution Failure" ${emailAddresses} < ${tempFile}
          
          #Update the log file
          updateLogs "${tempFile}" "${logFile}" "${errorLogID}"

          #Exit with failure
          exitScript "1"
     fi
}

#--------------------------------------------------------------------------
#    FUNCTION      exitScript
#    SYNTAX        exitScript <return_code>
#    DESCRIPTION   Steps to complete upon exit
#--------------------------------------------------------------------------
function exitScript
{
     #Define variables as local first
     typeset returnCode
     
     #Assign variable values
     returnCode=$1
     
     #Purge old logs
     #sed -r -n -e "/${purgeDate}/,\${p}" ${logFile} > ${tempFile}
     #mv -f ${tempFile} ${logFile}
     
     #Cleanup files
     rm ${tempFile} 1>/dev/null 2>&1
     rm ${tempFileTwo} 1>/dev/null 2>&1
     rm ${tempFileThree} 1>/dev/null 2>&1
     rm ${tempFileFour} 1>/dev/null 2>&1
     rm ${tempFileFive} 1>/dev/null 2>&1
     
     #Exit now
     exit ${returnCode}
}

#--------------------------------------------------------------------------
#    FUNCTION      updateLogs
#    SYNTAX        updateLogs <sourcelogfile> <targetlogfile> <logid> <unique>
#    DESCRIPTION   This function prepends a logid to a source logfile and appends the source logs to the target logs
#--------------------------------------------------------------------------
function updateLogs
{
     #Define variables as local first
     typeset sourceLog
     typeset targetLog
     typeset logid
     typeset unique
     
     #Now assign values to the local variables
     sourceLog=$1
     targetLog=$2
     logid=$3
     unique=$4
     
     #prepend text inline
     sed -i "s|^|${logid}|" ${sourceLog}
     if [[ "${unique}" = "UNIQUE" ]]
     then
          cat ${sourceLog} | sort -u >> ${targetLog}
     else
          cat ${sourceLog} >> ${targetLog}
     fi
     > ${sourceLog}
}


#--------------------------------------------------------------------------
#    FUNCTION      usage
#    SYNTAX        usage
#    DESCRIPTION   Displays proper usage syntax for the script
#--------------------------------------------------------------------------
function usage
{
     echo "Usage:   offsiteBackup.ksh"
     exit 1
}

#--------------------------------------------------------------------------
#    MAIN
#--------------------------------------------------------------------------

#Pulls the script name
scriptName=`echo $(basename ${0}) | cut -d"." -f1`

#Formatting of the timestamp to use
timeStamp=`date +"%yY-%mM-%dD-%HH-%MM"`
purgeDate=$(date -d "now - 1 month" +"%yY-%mM")

#Pulls the local node name, not including any suffix
localNode=`hostname | cut -d"." -f1`

#General Variables
emailAddresses="ryan.flagler@gmail.com"

#Where logs will reside
logPath=/mpool00/Recovery/${scriptName}
pidFile=${logPath}/${scriptName}.pid
logFile=${logPath}/${scriptName}.log
tempFile=${logPath}/${scriptName}.tmp
tempFileTwo=${logPath}/${scriptName}.tmptwo

#Create the logPath directory
mkdir -pm 777 ${logPath}

#Lets touch all the log files to prevent dumb errors
touch ${logFile}
touch ${tempFile}
touch ${tempFileTwo}

#Logfile identifiers
errorLogID="<ERROR>!${timeStamp}!"
scriptLogID="<SCRIPT>!${timeStamp}!"
lftpLogID="<LFTP>!${timeStamp}!"

#Directories configured for backup
dirLocalPath[0]="/mpool00/Data"
dirRemotePath[0]="/mpool00/Recovery/${localNode}_offsiteBackup/Data"

dirLocalPath[1]="/mpool00/Media/Other"
dirRemotePath[1]="/mpool00/Recovery/${localNode}_offsiteBackup/Media/Other"

dirLocalPath[2]="/mpool00/Media/Pictures"
dirRemotePath[2]="/mpool00/Recovery/${localNode}_offsiteBackup/Media/Pictures"

dirLocalPath[3]="/mpool00/Uploads"
dirRemotePath[3]="/mpool00/Recovery/${localNode}_offsiteBackup/Uploads"

#Identify how many directories are configured for backup
dirCount=${#dirLocalPath[*]}

#Remote server connection information
sftpServer=sftp://theoffsitebackup.homenet.org
sftpUsername='rflagler'
sftpPassword='BLANK'
sftpPort=22
sftpOptions=""
sftpMirrorCommand="mirror --reverse --no-empty-dirs --parallel=4 --log=${tempFile}"
sftpPurgeCommand="mirror --reverse --delete --parallel=4 --log=${tempFile}"

#First check if the script is already running
checkExecution

#Check if any prerequisites are complete
checkPrerequisites

#Run through the directories to backup and kick off the backup for them
i=0
while [[ $i -lt $dirCount ]]
do
     echo "${scriptLogID}Starting lftp sync for ${dirLocalPath[$i]}" >> ${logFile}
     
     #Execute the lftp sync job
     lftp -p ${sftpPort} -u ${sftpUsername},${sftpPassword} -e "${sftpOptions} ${sftpMirrorCommand} ${dirLocalPath[$i]} ${dirRemotePath[$i]}; bye;" ${sftpServer}

     #Cleanup the lftp sync log a bit
     cat ${tempFile} | grep -v chmod | cut -d':' -f5 | grep -e '^$' -v > ${tempFileTwo}
     > ${tempFile}
     
     #Lets add the update our log with this sync log
     updateLogs "${tempFileTwo}" "${logFile}" "${lftpLogID}"
     
     echo "${scriptLogID}Completed lftp sync for ${dirLocalPath[$i]}" >> ${logFile}
     ((i+=1))
done

echo "Offsite Backup Report" > ${tempFile}
mailx -s "${localNode}: Offsite Backup Report" ${emailAddresses} < ${tempFile}

exitScript 0

