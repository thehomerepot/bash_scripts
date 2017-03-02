#!/bin/ksh
#--------------------------------------------------------------------------
#     Name          : pool_monitor.ksh
#     Purpose       : Monitors zfs pools for their health and execute scrubs every specified days
#     Version       : 1.0
#     Usage         : ./pool_monitor.ksh -p <pool_name> -t <threshold> -s <days> -l <log_path> -e <email_address>
#
#     Change Log    : v1.0    2013-01-29
#                             -    Original Version
#
#--------------------------------------------------------------------------

#--------------------------------------------------------------------------
#     FUNCTION      usage
#     SYNTAX        usage
#     DESCRIPTION   Displays proper usage syntax for the script
#--------------------------------------------------------------------------
function usage
{
     echo "-----------------------------------------------------------"
     echo "Usage   : ./${scriptName}.ksh -p <pool_name> -t <threshold> -s <days> -l <log_path> -e <email_address>"
     echo "-----------------------------------------------------------"
     echo ""
     exit 3
}

#--------------------------------------------------------------------------
#     FUNCTION      executeHealthCheck
#     SYNTAX        executeHealthCheck <pool_name>
#     DESCRIPTION   Performs a health check on a pool
#--------------------------------------------------------------------------
function executeHealthCheck
{     
     #Store poolname to check
     healthPool=$1
     
     #Check the health of the poolName provided - ONLINE, DEGRADED, UNAVAIL, or SUSPENDED
     poolHealth=`zpool list -H -o health ${healthPool} | tee -a $debugLogFile`
     
     echo "Pool Status    : ${poolHealth}" | tee -a $logFile | tee -a $debugLogFile
     
     if [[ "${poolHealth}" != "ONLINE" ]] 
     then
          #ALWAYS EXIT FOR AN UNHEALTHY POOL
          exitScript 2 #Unhealthy
     fi
}

#--------------------------------------------------------------------------
#     FUNCTION      executeScrub
#     SYNTAX        executeScrub <pool_name>
#     DESCRIPTION   Performs a scrub on a pool
#--------------------------------------------------------------------------
function executeScrub
{
     #Store poolname to scrub
     scrubPool=$1
     
     #Log the start time
     scrubStartTime=`date +"%Y-%m-%d %H:%M"`
     
     zpool scrub ${scrubPool}
     returnCode=$?
     if (( $returnCode != 0 ))
     then
          echo "Time To Scrub  : FAILED - SCRUB DID NOT EXECUTE" | tee -a $logFile | tee -a $debugLogFile
          exitScript 2
     else
          #Let's monitor the scrub and wait until it's done to continue
          scrubRunning=0 #0=running 1=stopped
          while [[ $scrubRunning -eq 0 ]]
          do
               zpool status ${scrubPool} | grep -q "scrub in progress"
               scrubRunning=$?
               sleep 60
          done
          
          #Scrub time calculations
          scrubEndTime=`date +"%Y-%m-%d %H:%M"`
          scrubTotalSec=$(($(date -d "${scrubEndTime}" +%s)-$(date -d "${scrubStartTime}" +%s)))
          scrubTotalHrs=`expr ${scrubTotalSec} / 3600`
          scrubTotalMin=`expr $((${scrubTotalSec}-$(($scrubTotalHrs*3600)))) / 60`
          
          echo "Time To Scrub  : ${scrubTotalHrs}H:${scrubTotalMin}M" | tee -a $logFile | tee -a $debugLogFile
          
          #Let's check the health on the pool now that the scrub is complete
          executeHealthCheck ${scrubPool}

          exitCode=1
     fi
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
     
     #Cleanup PID link
     rm $logPath/$script_name".pid"
     
     exit
}

#--------------------------------------------------------------------------
#     MAIN
#--------------------------------------------------------------------------

#Variable to keep track of version for auditing purposes
SCRIPT_VERSION=1.0

#Pulls the script name without directory paths
scriptName=`echo $(basename ${0}) | cut -d"." -f1`

#Pulls the local node name stripping any suffix
localnode=`hostname | cut -d"." -f1`

#Formatting of the timestamp to use
timeStamp=`date +"%Y-%m-%d"`

#Initialize our exit code
exitCode=0

#Make sure that the root user is executing the script
CURRENT_USER=`whoami`
if [[ $CURRENT_USER != "root" ]]
then
     #Not ROOT. Blow up!
     echo "-----------------------------------------------------------"
     echo "ERROR   : This script must be executed as the root user."
     echo "-----------------------------------------------------------"
     echo ""
     exit 3
fi

#Check Incoming Variables and Usage
while getopts p:s:t:l:e: options
do
     case $options in
     p)
          poolName="$OPTARG"
          #CHECK IF –p FLAG IS NULL
          if [[ -z $poolName ]]
               then
                    echo "-----------------------------------------------------------"
                    echo "ERROR   : poolName (-p) was provided on the command line, but the value provided is null"
                    echo "-----------------------------------------------------------"
                    echo ""
                    usage
          fi
     ;;
     s)
          poolScrubThreshold="$OPTARG"
          #CHECK IF –s FLAG IS NULL
          if [[ -z $poolScrubThreshold ]]
               then
                    echo "-----------------------------------------------------------"
                    echo "ERROR   : poolScrubThreshold (-s) was provided on the command line, but the value provided is null"
                    echo "-----------------------------------------------------------"
                    echo ""
                    usage
          fi
     ;;
     t)
          poolSpaceThreshold="$OPTARG"
          #CHECK IF –t FLAG IS NULL
          if [[ -z $poolSpaceThreshold ]]
               then
                    echo "-----------------------------------------------------------"
                    echo "ERROR   : poolSpaceThreshold (-t) was provided on the command line, but the value provided is null"
                    echo "-----------------------------------------------------------"
                    echo ""
                    usage
          fi
     ;;
     l)
          logPath="$OPTARG"
          #CHECK IF –l FLAG IS NULL
          if [[ -z $logPath ]]
               then
                    echo "-----------------------------------------------------------"
                    echo "ERROR   : logPath (-l) was provided on the command line, but the value provided is null"
                    echo "-----------------------------------------------------------"
                    echo ""
                    usage
          fi
     ;;
     e)
          emailAddresses="$OPTARG"
          #CHECK IF –e FLAG IS NULL
          if [[ -z $emailAddresses ]]
               then
                    echo "-----------------------------------------------------------"
                    echo "ERROR   : emailAddresses (-e) was provided on the command line, but the value provided is null"
                    echo "-----------------------------------------------------------"
                    echo ""
                    usage
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
if [[ -z $poolName ]]
then
     echo "-----------------------------------------------------------"
     echo "ERROR   : The parameter -p is required for operation"
     echo "-----------------------------------------------------------"
     echo ""
     usage
fi

if [[ -z $logPath ]]
then
     echo "-----------------------------------------------------------"
     echo "ERROR   : The parameter -l is required for operation"
     echo "-----------------------------------------------------------"
     echo ""
     usage
fi

#Define the logfile name
logFile=$logPath"/"$scriptName"_"$poolName".log"
debugLogFile=$logPath"/"$scriptName"_"$poolName"_debug.log"

#Now lets make sure we can write to debugLogFile
touch $debugLogFile 1>/dev/null 2>&1
if (( $? != 0 ))
then
     echo "-----------------------------------------------------------"
     echo "ERROR   : Could not write to the debuglogfile ${debugLogFile}"
     echo "-----------------------------------------------------------"
     echo ""
     exit 3
else
     > $debugLogFile
fi

#Now lets make sure we can write to logFile
touch $logFile 1>/dev/null 2>&1
if (( $? != 0 ))
then
     echo "-----------------------------------------------------------" | tee -a $debugLogFile
     echo "ERROR   : Could not write to the logfile ${logFile}" | tee -a $debugLogFile
     echo "-----------------------------------------------------------" | tee -a $debugLogFile
     echo "" | tee -a $debugLogFile
     exit 3
else
     > $logFile
fi

#Check for previously running script first
if [[ -L $logPath/$script_name".pid" ]]
then
     pid=$(ls -l $logPath/$script_name".pid" | sed 's/.*-> //')
     if [[ -d /proc/$pid ]]
     then
          #The script is already running
          echo "-----------------------------------------------------------" | tee -a $debugLogFile
          echo "ERROR   : An instance of ${scriptName} is already running for pool ${poolName}" | tee -a $debugLogFile
          echo "-----------------------------------------------------------" | tee -a $debugLogFile
          echo "" | tee -a $debugLogFile
          exit 3
     else
          rm -f $logPath/$script_name".pid"
     fi
fi

#Since no previously running script was found, just keep track of the current instance
echo "STATUS  : The script ${scriptName} is not already running for pool ${poolName}" | tee -a $debugLogFile
ln -s $$ $logPath/$script_name".pid"

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

exitScript $exitCode
