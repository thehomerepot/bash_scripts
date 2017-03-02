#!/usr/bin/ksh
#Variable to keep track of version for auditing purposes
scriptVersion=1.4
#--------------------------------------------------------------------------
#    Name           : lftp_sync.ksh
#    Purpose        : Syncs to the seedbox. Renames/moves media with filebot. Updates plex.
#    Version        : 1.4
#    Usage          : lftp_sync.ksh
#
#    Change Log     : v1.4    -    2014-05-12
#                             -    Fixed an issue where extra folder names were inaccurately qualifying as exclusions
#                                  Was related to some grep's/cuts being in the wrong order
#
#                   : v1.3    -    2014-05-05
#                             -    Added \ escapes to the extVideo and extCompressed variables. It was ignoring the "." without them.
#
#                   : v1.2    -    2014-04-21
#                             -    Added pre-requisite checks (lftp, plex, unrar, filebot)
#                             -    Added the exitScript function for exiting the script
#
#                   : v1.1    -    2014-04-15
#                             -    Major update
#                             -    Now waits for the lftp process to finish to allow post-processing
#                             -    Added a .pid file to track running instances
#                             -    Added lftp parameters as variables
#                             -    Added email functionality
#                             -    Added enhanced parsing of the synced folder names. Now adds escapes for necessary characters
#                             -    Added auto extraction and renaming of media using filebot
#                             -    Added auto syncing of your plex library
#                             -    Added internal documentation
#                             -    Added variable arrays for more flexible use
#                             -    Added purging option with the -p flag
#
#                   : v1.0    -    2013-01-02
#                             -    Initial Creation and Use for Ubuntu 12.04
#--------------------------------------------------------------------------

#--------------------------------------------------------------------------
#    FUNCTION      checkPrerequisites
#    SYNTAX        checkPrerequisite
#    DESCRIPTION   Checks dpkg for installed packages needed for this script
#--------------------------------------------------------------------------
function checkPrerequisites
{
     #Define variables as local first
     typeset checkLFTP
     typeset checkUNRAR
     typeset checkPLEX
     typeset checkFILEBOT
     typeset checkFAIL
     
     #Lets audit for installed software that we use for this script
     checkFAIL="FALSE"
     checkLFTP=$(dpkg --get-selections | grep -v deinstall | egrep -ic lftp)
     checkUNRAR=$(dpkg --get-selections | grep -v deinstall | egrep -ic unrar)
     checkLFILEBOT=$(dpkg --get-selections | grep -v deinstall | egrep -ic filebot)
     checkLPLEX=$(dpkg --get-selections | grep -v deinstall | egrep -ic plexmediaserver)
     
     if [[ ${checkLFTP} -lt 1 ]]
     then
          checkFAIL="TRUE"
          echo "lftp was not found to be installed. It is required for this script." | tee -a ${tempFile}
          echo "    - You can install lftp with the following command" | tee -a ${tempFile}
          echo "    - sudo apt-get install -y lftp" | tee -a ${tempFile}
          echo ""  | tee -a ${tempFile}
     fi
     if [[ ${checkUNRAR} -lt 1 ]]
     then
          checkFAIL="TRUE"
          echo "unrar was not found to be installed. It is required for this script." | tee -a ${tempFile}
          echo "    - You can install unrar with the following command" | tee -a ${tempFile}
          echo "    - sudo apt-get install -y unrar" | tee -a ${tempFile}
          echo ""  | tee -a ${tempFile}
     fi
     if [[ ${checkLFILEBOT} -lt 1 ]]
     then
          checkFAIL="TRUE"
          echo "filebot was not found to be installed. It is required for this script." | tee -a ${tempFile}
          echo "    - You can download filebot at the following website" | tee -a ${tempFile}
          echo "    - http://www.filebot.net/download.php?mode=s&type=deb&arch=amd64" | tee -a ${tempFile}
          echo ""  | tee -a ${tempFile}
     fi
     if [[ ${checkLPLEX} -lt 1 ]]
     then
          checkFAIL="TRUE"
          echo "plexmediaserver was not found to be installed. It is required for this script." | tee -a ${tempFile}
          echo "    - You can download plex at the following website" | tee -a ${tempFile}
          echo "    - https://plex.tv/downloads#pms-desktop" | tee -a ${tempFile}
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
     
     #Cleanup files
     rm ${tempFile}
     rm ${tempFileTwo}
     rm ${tempFileThree}

     #Cleanup pidFile
     trackResponse=$(trackExecution ${pidFile} "STOP")
     
     #Exit now
     exit ${returnCode}
}

#--------------------------------------------------------------------------
#    FUNCTION      syncLFTP
#    SYNTAX        syncLFTP <libArrayIndex> <purge>
#    DESCRIPTION   Initiates an lftp mirror job to sync to an SFTP server
#--------------------------------------------------------------------------
function syncLFTP
{
     #Define variables as local first
     typeset libArrayIndex
     typeset purge
     
     #Now assign values to the local variables
     libArrayIndex=$1
     purge=$2
     
     if [[ "${purge}" = "TRUE" ]]
     then
          lftp -p ${lftpPORT} -u ${lftpUN},${lftpPW} -e "${lftpOPTIONS} ${lftpPURGECOMMAND} ${libFTPDIR[${libArrayIndex}]} ${libSYNCDIR[${libArrayIndex}]}; bye;" ${lftpSERVER}
     else
          lftp -p ${lftpPORT} -u ${lftpUN},${lftpPW} -e "${lftpOPTIONS} ${lftpMIRRORCOMMAND} ${libFTPDIR[${libArrayIndex}]} ${libSYNCDIR[${libArrayIndex}]}; bye;" ${lftpSERVER}
     fi
}

#--------------------------------------------------------------------------
#    FUNCTION      syncPlex
#    SYNTAX        syncPlex <libraryName>
#    DESCRIPTION   Initiate a Plex Sync
#--------------------------------------------------------------------------
function syncPlex
{
     #Define variables as local first
     typeset libraryName
     typeset sectionID
     typeset plexlog
     
     #Now assign values to the local variables
     libraryName=$1
     plexlog=$2
     
     #Setup our environment to run the plex media scanner
     export LD_LIBRARY_PATH="/usr/lib/plexmediaserver" LANG="en_US.UTF-8"
     export PLEX_MEDIA_SERVER_MAX_PLUGIN_PROCS="6"
     export PLEX_MEDIA_SERVER_TMPDIR="/tmp"
     export PLEX_MEDIA_SERVER_HOME="/usr/lib/plexmediaserver"
     export PLEX_MEDIA_SERVER_APPLICATION_SUPPORT_DIR="/var/lib/plexmediaserver/Library/Application Support"
     
     #Pull the sectionID using the libraryName
     sectionID=$(/usr/lib/plexmediaserver/Plex\ Media\ Scanner -l | egrep -i ": ${libraryName}" | cut -d':' -f1 | sed -e 's/^[ \t]*//;s/[ \t]*$//')
     
     #Tell plex to update the sectionID we found using the libraryName
     /usr/lib/plexmediaserver/Plex\ Media\ Scanner -r -s -c ${sectionID}
}

#--------------------------------------------------------------------------
#    FUNCTION      trackExecution
#    SYNTAX        trackExecution <PIDFILE> <START|STOP|CHECK>
#    DESCRIPTION   Tracks the execution and running PID of the script
#--------------------------------------------------------------------------
function trackExecution
{
     #Define variables as local first
     typeset trackFile
     typeset trackMode
     typeset trackStatus
     typeset trackPID
     
     #Now assign values to the local variables
     trackFile=$1
     trackMode=$2
     trackStatus=""
     trackPID=""
     
     case ${trackMode} in
     'CHECK')
          if [[ -L $trackFile ]]
          then
               trackPID=$(ls -l $trackFile | sed 's/.*-> //')
               if [[ -d /proc/${trackPID} ]]
               then
                    trackStatus="RUNNING"
               else
                    trackStatus="STOPPED"
               fi
          else
               trackStatus="STOPPED"
          fi
          echo ${trackStatus}
     ;;
     'START')
          trackStatus=$(trackExecution ${trackFile} "CHECK")
          if [[ "${trackStatus}" = "STOPPED" ]]
          then
               ln -s $$ ${trackFile} 2>/dev/null
               echo "SUCCESS"
          else
               echo "FAILED"
          fi
     ;;
     'STOP')
          rm -f ${trackFile} 2>/dev/null
          if [[ -L ${trackFile} ]]
          then
               echo "FAILED"
          else
               echo "SUCCESS"
          fi
     ;;
     esac
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
#    FUNCTION      updatePermissions
#    SYNTAX        updatePermissions <mode> <directory>
#    DESCRIPTION   This function updates permissions recursively on directories
#--------------------------------------------------------------------------
function updatePermissions
{
     #Define variables as local first
     typeset mode
     typeset directory
     
     #Now assign values to the local variables
     mode=$1
     directory=$2
     
     #prepend text inline
     chmod -R ${mode} ${directory} 
}

#--------------------------------------------------------------------------
#    MAIN
#--------------------------------------------------------------------------

#Pulls the script name
scriptName=`echo $(basename ${0}) | cut -d"." -f1`

#Formatting of the timestamp to use
timeStamp=`date +"%yY-%mM-%dD-%HH-%MM"`

#Pulls the local node name, not including any suffix
localNode=`hostname | cut -d"." -f1`

#General Variables
emailAddresses="ryan.flagler@gmail.com"
sendProcessedEmail="FALSE" #DO NOT MODIFY
extVideo="(\.mkv$|\.avi$|\.mpg$|\.mpeg$|\.mp4$|\.wmv$|\.divx$|\.ts$)"
extCompressed="(\.zip$|\.rar$|\.7z$)"

#Where logs will reside
logPath=/mpool00/Torrents/${scriptName}
pidFile=${logPath}/${scriptName}.pid
logFile=${logPath}/${scriptName}.log
tempFile=${logPath}/${scriptName}.tmp
tempFileTwo=${logPath}/${scriptName}.tmptwo
tempFileThree=${logPath}/${scriptName}.tmpthree

#Create the logPath directory
mkdir -pm 777 ${logPath}

#Lets touch all the log files to prevent dumb errors
touch ${logFile}
touch ${tempFile}
touch ${tempFileTwo}
touch ${tempFileThree}

#Logfile identifiers
errorLogID="<ERROR>!${timeStamp}!"
lftpLogID="<LFTP>!${timeStamp}!"
filebotLogID="<FILEBOT>!${timeStamp}!"
processedLogID="<PROCESSED>!${timeStamp}!"
skippedLogID="<SKIPPED>!${timeStamp}!"
excludedLogID="<EXCLUDED>!${timeStamp}!"

#LFTP Variables
lftpPURGE="FALSE"
lftpPORT=21
lftpUN="theseedbox"
lftpPW="th3s33db0x"
lftpOPTIONS="set ftp:ssl-force true; set ftp:ssl-auth TLS; set ftp:ssl-protect-data true;"
lftpMIRRORCOMMAND="mirror --no-empty-dirs --parallel=4 --log=${tempFile} --no-perms"
lftpPURGECOMMAND="mirror --delete --parallel=4 --log=${tempFile} --no-perms"
lftpSERVER="ftp://euh30.seed.st"

#Configure An Additional Index For Each Of The Following Arrays For Each Library/Section
#TV Shows
libID[0]="RF-TV"
libNAME[0]="TV Shows"
libDIR[0]="/mpool00/Media/TVShows"
libFTPDIR[0]="downloads/Completed/${libID[0]}"
libSYNCDIR[0]="/mpool00/Torrents/Completed/${libID[0]}"
libFORMAT[0]="${libDIR[0]}/{n}/Season {s}/{s}x{e.pad(2)} - {t}"
libDB[0]="TheTVDB"
libEXCLUDE[0]="(sample|subs|proof|\.nfo)"
libFLAG[0]="FALSE"
libPROCESS[0]="TRUE"

#Movies
libID[1]="RF-MOVIE"
libNAME[1]="Movies"
libDIR[1]="/mpool00/Media/Movies"
libFTPDIR[1]="downloads/Completed/${libID[1]}"
libSYNCDIR[1]="/mpool00/Torrents/Completed/${libID[1]}"
libFORMAT[1]="${libDIR[1]}/{n} ({y})/{n}"
libDB[1]="IMDb"
libEXCLUDE[1]="(sample|subs|proof|\.nfo)"
libFLAG[1]="FALSE"
libPROCESS[1]="TRUE"

#Misc
libID[2]="RF-MISC"
libNAME[2]=""
libDIR[2]=""
libFTPDIR[2]="downloads/Completed/${libID[2]}"
libSYNCDIR[2]="/mpool00/Torrents/Completed/${libID[2]}"
libFORMAT[2]=""
libDB[2]=""
libEXCLUDE[2]=""
libFLAG[2]="FALSE"
libPROCESS[2]="FALSE"

#Example
#libID[0]="RF-TV"
#    The text string used to identify the media type as far as directory structure goes.
#    Will be used throughout syncing to/from ftp/local servers and searching for media to extract/rename
#
#libNAME[0]="TV Shows"
#    The name of the library/section as configured in Plex
#
#libDIR[0]="/mpool00/Media/TVShows"
#    The local directory where the media will be placed after renaming/extraction.
#    The directory you point Plex to
#
#libFTPDIR[0]="downloads/Completed/${libID[0]}"
#    The directory on the ftp server to sync completed torrents from
#
#libSYNCDIR[0]="/mpool00/Torrents/Completed/${libID[0]}"
#    The directory on the local server to sync completed torrents to
#
#libFORMAT[0]="${libDIR[0]}/{n}/Season {s}/{s}x{e.pad(2)} - {t}"
#    The filebot naming format. http://www.filebot.net/naming.html
#    Include the associated libDIR
#
#libDB[0]="TheTVDB"
#    The DB to use for renaming this media. Needs to work with filebot.
#    TV:       TVRage, AniDB, TheTVDB
#    Movie:    OpenSubtitles, IMDb, TheMovieDB
#
#libEXCLUDE[0]="(sample|subs)"
#    A list of text you want to use as an identifier of files/folders to exclude from processing
#
#libFLAG[0]="FALSE"
#    A flag to track whether this library needs scanned. Should always be FALSE until the script changes it
#
#libPROCESS[0]="TRUE"
#    A flag to track whether this media type needs processed via filebot and plex. FALSE will just sync the directories

#Before we do anything, make sure the script isn't already running
trackResponse=$(trackExecution $pidFile "START")
if [[ "${trackResponse}" = "FAILED" ]]
then
     echo "The script is already running!"
     exit 0
fi

#Check Incoming Variables and Usage
while getopts p options
do
     case $options in
     p)
          #Performa a purge
          lftpPURGE="TRUE"
     ;;
     \?)
          clear
     ;;
     *)
          clear
     ;;
     esac
done

#Identify how many libraries/sections are setup to be synced/processed
libCount=${#libID[*]}

#Lets parse through the libraries and sync up to the SFTP server
i=0
while [[ $i -lt $libCount ]]
do
     syncLFTP "$i" "${lftpPURGE}"
     updateLogs "${tempFile}" "${logFile}" "${lftpLogID}"
     ((i+=1))
done

#The libraries should be synced now. Lets parse for newly synced folders that we can run through filebot
i=0
while [[ $i -lt $libCount ]]
do
     if [[ "${libPROCESS[$i]}" = "TRUE" ]]
     then
          #Pulls the sync logs from lftp
          cat ${logFile} | egrep "${lftpLogID}" | egrep "${libID[$i]}" | cut -d"!" -f3- | while read folder
          do
               #This will catch folder names without special characters
               echo $folder | egrep -i '^get -' | grep -v \" | cut -d' ' -f3 | egrep -vi "${libEXCLUDE[$i]}" >> ${tempFile}
               #And now lets track skipped files due to an exclusion
               echo $folder | egrep -i '^get -' | grep -v \" | cut -d' ' -f3 | egrep -i "${libEXCLUDE[$i]}" >> ${tempFileTwo}
               
               #This will catch folder names with special characters (filebot puts them in quotes)
               #We need to escape any special characters that linux doesn't like
               echo $folder | egrep -i '^get -' | grep \" | cut -d'"' -f2 | egrep -vi "${libEXCLUDE[$i]}" | perl -pe 's/([!'\ '^&()=`\$])/\\\1/g' >> ${tempFile}
               #And now lets track skipped files due to an exclusion
               echo $folder | egrep -i '^get -' | grep \" | cut -d'"' -f2 | egrep -i "${libEXCLUDE[$i]}" | perl -pe 's/([!'\ '^&()=`\$])/\\\1/g' >> ${tempFileTwo}
          done
          
          #Lets output this log with only unique entries and with the filebotLogID
          updateLogs "${tempFile}" "${logFile}" "${filebotLogID}" "UNIQUE"
          
          #Lets output this log with only unique entries and with the excludedLogID
          updateLogs "${tempFileTwo}" "${logFile}" "${excludedLogID}" "UNIQUE"
          
          #Now lets pull the folders and find video files to pass through filebot
          cat ${logFile} | egrep "${filebotLogID}" | egrep "${libID[$i]}" | cut -d"!" -f3- | while read folder
          do
               #Find video files
               ls -1 $folder | egrep -i "${extVideo}" | egrep -vi "${libEXCLUDE[$i]}" | while read file
               do
                    #Copy and rename
                    filebot --action copy --conflict fail --db ${libDB[$i]} --format "${libFORMAT[$i]}" -rename -non-strict ${folder}/${file}
                    if [[ $? -eq 0 ]]
                    then
                         #Log that we processed a file
                         libFLAG[$i]="TRUE"
                         echo "${folder}/${file}" >> ${tempFile}
                    else
                         echo "${folder}/${file}" >> ${tempFileThree}
                    fi
               done
               
               #Find video files skipped due to an exclusion
               ls -1 $folder | egrep -i "${extVideo}" | egrep -i "${libEXCLUDE[$i]}" | while read file
               do
                    echo "${folder}/${file}" >> ${tempFileTwo}
               done
               
               #Find compressed files
               ls -1 $folder | egrep -i "${extCompressed}" | egrep -vi "${libEXCLUDE[$i]}" | rev | cut -d'.' -f1 | rev | sort -u | while read extension
               do 
                    #Extract compressed files
                    unrar e -y "${folder}/*.${extension}" ${folder}
                    if [[ $? -ne 0 ]]
                    then
                         echo "${folder}/${file}" >> ${tempFileThree}
                    fi
                    
                    ls -1 $folder | egrep -i "${extVideo}" | egrep -vi "${libEXCLUDE[$i]}" | while read file
                    do
                         #Move, and rename
                         filebot --action move --conflict fail --db ${libDB[$i]} --format "${libFORMAT[$i]}" -rename -non-strict ${folder}/${file}
                         if [[ $? -eq 0 ]]
                         then
                              #Log that we processed a file
                              libFLAG[$i]="TRUE"
                              echo "${folder}/${file}" >> ${tempFile}
                         else
                              echo "${folder}/${file}" >> ${tempFileThree}
                              rm ${folder}/${file}
                         fi
                    done
               done
               
               #Find compressed files skipped due to an exclusion
               ls -1 $folder | egrep -i "${extCompressed}" | egrep -i "${libEXCLUDE[$i]}" | while read file
               do
                    echo "${folder}/${file}" >> ${tempFileTwo}
               done
          done

          #Lets output this log with the processedLogID
          updateLogs "${tempFile}" "${logFile}" "${processedLogID}"

          #Lets output this log with the excludedLogID
          updateLogs "${tempFileTwo}" "${logFile}" "${excludedLogID}" "UNIQUE"
          
          #Lets output this log with the skippedLogID
          updateLogs "${tempFileThree}" "${logFile}" "${skippedLogID}" "UNIQUE"
     fi
     ((i+=1))
done

#The files should all be processed through filebot now. Lets see if we need to update plex libraries
i=0
while [[ $i -lt $libCount ]]
do
     #Check if the flag shows files were processed for this library
     if [[ "${libFLAG[$i]}" = "TRUE" ]]
     then
          sendProcessedEmail="TRUE"
          syncPlex ${libNAME[$i]}
     fi
     
     #Optional, but I like the files wide open
     if [[ -n ${libDIR[$i]} ]]
     then
          updatePermissions "777" "${libDIR[$i]}"
     fi
     if [[ -n ${libSYNCDIR[$i]} ]]
     then
          updatePermissions "777" "${libSYNCDIR[$i]}"
     fi
     updatePermissions "777" "${libSYNCDIR[$i]}"
     ((i+=1))
done

#Check whether we should send an email or not
skippedCount=$(cat ${logFile} | egrep -c "${skippedLogID}")
excludedCount=$(cat ${logFile} | egrep -c "${excludedLogID}")
if [[ ${skippedCount} -gt 0 ]] || [[ ${excludedCount} -gt 0 ]] || [[ "${sendProcessedEmail}" = "TRUE" ]]
then
     if [[ "${sendProcessedEmail}" = "TRUE" ]]
     then
          echo "PROCESSED - Media that has been downloaded, extracted, renamed, moved, and scanned into plex" >> ${tempFile}
          cat ${logFile} | egrep "${processedLogID}" | cut -d"!" -f3- | rev | cut -d'/' -f1,2 | rev >> ${tempFile}
          echo "" >> ${tempFile}
          echo "" >> ${tempFile}
     fi
     if [[ ${excludedCount} -gt 0 ]]
     then
          echo "EXCLUDED - Media that was matched to a libEXCLUDE[x] varible and therefore not processed" >> ${tempFile}
          cat ${logFile} | egrep "${excludedLogID}" | cut -d"!" -f3- | rev | cut -d'/' -f1,2 | rev >> ${tempFile}
          echo "" >> ${tempFile}
          echo "" >> ${tempFile}
     fi
     if [[ ${skippedCount} -gt 0 ]]
     then
          echo "SKIPPED - Media that was skipped due to a failure in extraction or a failure/duplicate when renaming with filebot" >> ${tempFile}
          cat ${logFile} | egrep "${skippedLogID}" | cut -d"!" -f3- | rev | cut -d'/' -f1,2 | rev >> ${tempFile}
          echo "" >> ${tempFile}
          echo "" >> ${tempFile}
     fi
     
     mailx -s "${localNode}: Media Update Report" ${emailAddresses} < ${tempFile}
fi

#Exit with success
exitScript "0"
