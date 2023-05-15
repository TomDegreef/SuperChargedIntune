<#
.SYNOPSIS
	This Script allows you to setup Configmgr (latest available build) in an unattended way on a server that has internet access.
.DESCRIPTION
        - Fully unattended installation of all prerequisites needed for Configuration Manager Current Branch
        - Fully unattended installation of Configuration manager current branch and updates
.NOTES
    FileName:    Configure-SCCM.ps1
    Blog: 	 http://www.OSCC.Be
    Author:      Tom Degreef
    Twitter:     @TomDegreef
    Email:       Tom.Degreef@OSCC.Be
    Created:     2023-05-09
    Updated:     2023-05-09
    
    Version history
    1.0	  - (2023-05-09) Initial public release after demonstrating it in MMSMOA 2023
.LINK 
	Http://www.OSCC.Be
#>
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
install-module -Name OSCCPsLogging -Force
Install-Module -Name Az -Repository PSGallery -Force

$logmodule = "$env:systemdrive\temp\SCCM_Setup.log"
try { $log = Initialize-CMLogging -LogFileName $logmodule -ConsoleLogLevel off -fileLogLevel info } catch {}
function log-item {
  param(  $logline,
    $severity = "Info" )
  [string]$currentdatetime = get-date
  if (get-module -name OSCCPSLogging) {
    Switch ($severity) {
      "Info" { $log.Info($logline) }
      "Warn" { $log.Warn($logline) }
      "Error" { $log.Error($logline) }
    }
                
  }
  else {
    Switch ($severity) {
      "Info" { [string]$output = $currentdatetime + " - INFO - " + $logline }
      "Warn" { [string]$output = $currentdatetime + " - WARNING - " + $logline }
      "Error" { [string]$output = $currentdatetime + " - ERROR - " + $logline }
    }              
    $output | out-file $Logfile -append
  }
}

function getupdate()
{
  Log-Item -logline "Get CM update..." -severity "Info"
    $CMPSSuppressFastNotUsedCheck = $true
    $updatepacklist= Get-CMSiteUpdate -Fast | ?{$_.State -ne 196612}
    $getupdateretrycount = 0
    while($updatepacklist.Count -eq 0)
    {
        if($getupdateretrycount -eq 3)
        {
            break
        }
        Log-Item -logline "Not found any updates, retry to invoke update check." -severity "Info"
        $getupdateretrycount++
        Log-Item -logline "Invoke CM Site update check..." -severity "Info"
        Invoke-CMSiteUpdateCheck -ErrorAction Ignore
        Start-Sleep 120

        $updatepacklist= Get-CMSiteUpdate | ?{$_.State -ne 196612}
    }

    $updatepack=""

    if($updatepacklist.Count -eq 0)
    {
    }
    elseif($updatepacklist.Count -eq 1)
    {
        $updatepack= $updatepacklist
    }
    else
    {
        $updatepack= ($updatepacklist | sort -Property fullversion)[-1] 
    }
    return $updatepack
}

#----------------------------------------------------
$state=@{
    0 = 'UNKNOWN'
    2 = 'ENABLED'
    #DMP DOWNLOAD
    262145 = 'DOWNLOAD_IN_PROGRESS'
    262146 = 'DOWNLOAD_SUCCESS'
    327679 = 'DOWNLOAD_FAILED'
    #APPLICABILITY
    327681 = 'APPLICABILITY_CHECKING'
    327682 = 'APPLICABILITY_SUCCESS'
    393213 ='APPLICABILITY_HIDE'
    393214 = 'APPLICABILITY_NA'
    393215 = 'APPLICABILITY_FAILED'
    #CONTENT
    65537 = 'CONTENT_REPLICATING'
    65538 = 'CONTENT_REPLICATION_SUCCESS'
    131071 = 'CONTENT_REPLICATION_FAILED'
    #PREREQ
    131073 = 'PREREQ_IN_PROGRESS'
    131074 = 'PREREQ_SUCCESS'
    131075 = 'PREREQ_WARNING'
    196607 = 'PREREQ_ERROR'
    #Apply changes
    196609 = 'INSTALL_IN_PROGRESS'
    196610 = 'INSTALL_WAITING_SERVICE_WINDOW'
    196611 = 'INSTALL_WAITING_PARENT'
    196612 = 'INSTALL_SUCCESS'
    196613 = 'INSTALL_PENDING_REBOOT'
    262143 = 'INSTALL_FAILED'
    #CMU SERVICE UPDATEI
    196614 = 'INSTALL_CMU_VALIDATING'
    196615 = 'INSTALL_CMU_STOPPED'
    196616 = 'INSTALL_CMU_INSTALLFILES'
    196617 = 'INSTALL_CMU_STARTED'
    196618 = 'INSTALL_CMU_SUCCESS'
    196619 = 'INSTALL_WAITING_CMU'
    262142 = 'INSTALL_CMU_FAILED'
    #DETAILED INSTALL STATUS
    196620 = 'INSTALL_INSTALLFILES'
    196621 = 'INSTALL_UPGRADESITECTRLIMAGE'
    196622 = 'INSTALL_CONFIGURESERVICEBROKER'
    196623 = 'INSTALL_INSTALLSYSTEM'
    196624 = 'INSTALL_CONSOLE'
    196625 = 'INSTALL_INSTALLBASESERVICES'
    196626 = 'INSTALL_UPDATE_SITES'
    196627 = 'INSTALL_SSB_ACTIVATION_ON'
    196628 = 'INSTALL_UPGRADEDATABASE'
    196629 = 'INSTALL_UPDATEADMINCONSOLE'
}

if ((gwmi win32_computersystem).partofdomain -eq $true) {
  Log-Item -logline "I am domain joined! We can happily start this setup" -severity "Info"
}
else {
  Log-Item -logline  "Ooops, workgroup! Please join a domain first before continuing setup" -severity "Info"
  Break 
}

Log-Item -logline "Starting SCCM Deployment - The cloud Edition" -severity "Info"
# Windows 11 22H2 ADK
$ADKUrl = "https://go.microsoft.com/fwlink/?linkid=2196127"
# Windows 11 22H2 ADK PE addon
$ADKAddon = "https://go.microsoft.com/fwlink/?linkid=2196224"
# SCCM
$cmurl = "https://go.microsoft.com/fwlink/?linkid=2195628" 
# SQL 2022 Dev edition
$SQLUrl = "https://go.microsoft.com/fwlink/?linkid=2215158"
# SQL 2022 Management Studio
$SQLMSUrl = "https://go.microsoft.com/fwlink/?linkid=2215159"
# SQL 2022 Reporting Services
$SQLRSUrl = "https://go.microsoft.com/fwlink/?linkid=2215160"
# Dotnet 3.5
$DotnetUrl = "https://go.microsoft.com/fwlink/?linkid=2186537"

Log-Item -logline "Configuring windows for SCCM Prerequisites" -severity "Info"
Log-Item -logline "Installing Windows RDC Component" -severity "Info"
add-windowsfeature rdc
Log-Item -logline "Installing WSUS Services" -severity "Info"
add-windowsfeature UpdateServices-API
Log-Item -logline "Installing BITS components" -severity "Info"
Add-windowsfeature BITS, BITS-IIS-EXT, RSAT-BITS-SERVER
Log-Item -logline "Installing IIS Components" -severity "Info"
Add-windowsfeature WEB-MGMT-Compat, WEB-WMI

Log-Item -logline "Adding necessary firewall rules for SQL" -severity "Info"
New-NetFirewallRule -DisplayName "SQL Server" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action allow
New-NetFirewallRule -DisplayName "SQL Admin Connection" -Direction Inbound -Protocol TCP -LocalPort 1434 -Action allow
New-NetFirewallRule -DisplayName "SQL Database Management" -Direction Inbound -Protocol UDP -LocalPort 1434 -Action allow
New-NetFirewallRule -DisplayName "SQL Service Broker" -Direction Inbound -Protocol TCP -LocalPort 4022 -Action allow

New-Item -ItemType Directory -Path C:\InstallBinaries -Force
#Download All binaries
Log-Item -logline "Starting download of ADK" -severity "Info"
Invoke-WebRequest -Uri $adkurl -OutFile C:\InstallBinaries\adksetup.exe
Log-Item -logline "Starting download of ADK WinPE Addon" -severity "Info"
Invoke-WebRequest -Uri $ADKAddon -OutFile C:\InstallBinaries\adksetupwinpe.exe
Log-Item -logline "Starting download of Configmgr Binaries" -severity "Info"
Invoke-WebRequest -Uri $cmurl -OutFile C:\InstallBinaries\cmsetup.exe
Log-Item -logline "Starting download of SQL 2022 Dev edition - installer" -severity "Info"
Invoke-WebRequest -Uri $SQLUrl -OutFile C:\InstallBinaries\SQL2022-SSEI-Dev.exe
Log-Item -logline "Starting download of SQL Management studio" -severity "Info"
Invoke-WebRequest -Uri $SQLMSUrl -OutFile C:\InstallBinaries\sqlms.exe
Log-Item -logline "Starting download of SQL Reporting services" -severity "Info"
Invoke-WebRequest -Uri $SQLRSUrl -OutFile C:\InstallBinaries\sqlrs.exe
#Log-Item -logline "Starting download of Dotnet 3.5" -severity "Info"
#Invoke-WebRequest -Uri $DotnetUrl -OutFile C:\InstallBinaries\dotnetfx35.exe

Log-Item -logline "Starting full download of SQL Server binaries" -severity "Info"
Start-Process -FilePath "C:\InstallBinaries\SQL2022-SSEI-Dev.exe" -ArgumentList "/action=download /mediatype=iso /mediapath=C:\InstallBinaries /quiet" -Wait

Log-Item -logline "Installing Dotnet 3.5" -severity "Info"
DISM /Online /Enable-Feature /FeatureName:NetFx3 /All

#Install ADK
Log-Item -logline "Installing ADK" -severity "Info"
Start-Process -FilePath "C:\InstallBinaries\adksetup.exe" -ArgumentList "/Features OptionId.DeploymentTools OptionId.UserStateMigrationTool /norestart /ceip off /q /log C:\InstallBinaries\adksetup.log " -Wait

#Install ADK-Addon
Log-Item -logline "Installing ADK - WinPE" -severity "Info"
Start-Process -FilePath "C:\InstallBinaries\adksetupwinpe.exe" -ArgumentList "/Features OptionId.WindowsPreinstallationEnvironment /norestart /ceip off /q /log C:\InstallBinaries\adkAddonsetup.log " -Wait

# Start SQL Install
Log-Item -logline "Preparing installation for SQL" -severity "Info"
New-item -ItemType Directory -Path c:\SQLUpdates -Force
$dom = $env:userdomain
$usr = $env:username
Log-Item -logline "Mounting SQL iso" -severity "Info"
$SQLISo = Mount-DiskImage -ImagePath "C:\InstallBinaries\SQLServer2022-x64-ENU-Dev.iso"
$driveLetter = ($SQLISo | Get-Volume).DriveLetter
$sqlSetup = "$driveLetter" + ":\setup.exe"
$Argmtlist = '/ACTION=Install /IACCEPTSQLSERVERLICENSETERMS /UpdateEnabled=1 /UpdateSource=c:\SQLUpdates /features="SQLEngine" /installshareddir="c:\SQL\(X64)" /InstallsharedwowDir="c:\SQL\(X86)" /instancedir="c:\SQL\(X64)" /Instancename=MSSQLSERVER /q /AGTSVCACCOUNT="NT Authority\System" /INSTALLSQLDATADIR="c:\SQL\(X64)" /SQLBACKUPDIR="c:\MSSQLSERVER\BACKUP" /SQLCOLLATION=SQL_Latin1_General_CP1_CI_AS /SQLSYSADMINACCOUNTS="NT AUTHORITY\SYSTEM" "' + "$dom\$usr" + '"' + ' "' + "$dom\aad dc administrators" + '" ' + '/SQLSVCACCOUNT="NT Authority\System" /SQLTEMPDBDIR="c:\MSSQLSERVER\TEMPDB" /SQLTEMPDBLOGDIR="c:\MSSQLSERVER\LOGS" /SQLUSERDBDIR="c:\MSSQLSERVER\USERDB" /SQLUSERDBLOGDIR="c:\MSSQLSERVER\Logs" /INDICATEPROGRESS'
$cmd = $sqlsetup + ' ' + $Argmtlist
Log-Item -logline "Starting SQL Setup with cmdline $cmd" -severity "Info"
Log-Item -logline "This may take a while to complete ..." -severity "Info"
invoke-expression $cmd

Log-Item -logline "Enabling SQL TCPIP Protocol" -severity "Info"
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')
$wmi = New-Object 'Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer' localhost
$tcp = $wmi.ServerInstances['MSSQLSERVER'].ServerProtocols['Tcp']
$tcp.IsEnabled = $true  
$tcp.Alter() 
Log-Item -logline "Restarting SQL Server" -severity "Info"
Restart-Service -Name MSSQLSERVER -Force

#Extract Configmgr Installation
Log-Item -logline "Extract Configmgr Installation binaries from self extracting zipfile" -severity "Info"
Start-Process -Filepath "C:\InstallBinaries\cmsetup.exe" -ArgumentList ('/Auto "' + 'C:\InstallBinaries\CMSource' + '"') -wait

Log-Item -logline "Downloading Configmgr updates (prereqs)" -severity "Info"
New-Item -ItemType Directory -Path C:\InstallBinaries\CMUpdates
start-process "C:\InstallBinaries\CMSource\SMSSETUP\BIN\X64\setupdl.exe" -ArgumentList "/noui C:\InstallBinaries\CMUpdates" -wait

$ConfigIni = @"
[Identification]
Action=InstallPrimarySite


[Options]
ProductID=EVAL
SiteCode=001
SiteName=Cloud CM
SMSInstallDir=C:\Program Files\Microsoft Configuration Manager
SDKServer=REPLACE_WITH_LOCALHOST
RoleCommunicationProtocol=HTTPorHTTPS
ClientsUsePKICertificate=0
PrerequisiteComp=1
PrerequisitePath=C:\InstallBinaries\CMUpdates
MobileDeviceLanguage=0
ManagementPoint=REPLACE_WITH_LOCALHOST
ManagementPointProtocol=HTTP
AdminConsole=1
JoinCEIP=0

[SQLConfigOptions]
SQLServerName=REPLACE_WITH_LOCALHOST
SQLServerPort=1433
DatabaseName=CM_001
SQLSSBPort=4022
SQLDataFilePath=c:\MSSQLSERVER\USERDB\
SQLLogFilePath=c:\MSSQLSERVER\Logs\

[CloudConnectorOptions]
CloudConnector=1
CloudConnectorServer=REPLACE_WITH_LOCALHOST
UseProxy=0
ProxyName=
ProxyPort=

[SystemCenterOptions]
SysCenterId=

[SABranchOptions]
SAActive=1
CurrentBranch=1
SAExpiration=2026-08-05 00:00:00.000

[HierarchyExpansionOption]
"@

Log-Item -logline "Generating Configmgr.ini file for unattended setup" -severity "Info"
$fulldomain = (gwmi -class win32_computersystem).domain
$ConfigIni = $ConfigIni.Replace('REPLACE_WITH_LOCALHOST', "$env:computername.$fulldomain")
$ConfigIni | out-file C:\InstallBinaries\Configmgr.ini

Log-Item -logline "Starting Configmgr installation" -severity "Info"
Log-Item -logline "Patience is a virtue, this will take some time to complete !" -severity "Info"
start-process "C:\InstallBinaries\CMSource\SMSSETUP\BIN\X64\setup.exe" -argumentlist "/SCRIPT C:\InstallBinaries\Configmgr.ini" -wait

Log-Item -logline "Installation of configmgr is finished! Pausing 5 minutes for things to settle down" -severity "Info"
Start-Sleep -Seconds 300

Log-Item -logline "Starting and stopping the configmgr Console to enable the cmdlets" -severity "Info"
Start-Process "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\Microsoft.ConfigurationManagement.exe"
start-sleep -Seconds 150
Stop-Process -Name 'Microsoft.ConfigurationManagement'

Import-Module "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager\configurationmanager.psd1" -force                       
$SiteCode = Get-PSDrive -PSProvider CMSITE
Set-Location "$($SiteCode):\"

if ($DMPState -ne "Running") {
  Log-Item -logline "Starting the DMP Downloader as it was not running" -severity "Info"
  Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\SMS\Components\SMS_Executive\Threads\SMS_DMP_DOWNLOADER" -Name "Requested Operation" -Value "Start"
  Start-sleep -Seconds 30
}

$retrytimes = 0
$downloadretrycount = 0
$updatepack = getupdate
if($updatepack -ne "")
{
  Log-Item -logline "Update package is $($updatepack.Name)" -severity "Info"
}
else
{
  Log-Item -logline "No update package be found." -severity "Info"
}
while($updatepack -ne "")
{
    if($retrytimes -eq 3)
    {
        $upgradingfailed = $true
        break
    }
    $updatepack = Get-CMSiteUpdate -Fast -Name $updatepack.Name 
    while($updatepack.State -eq 327682 -or $updatepack.State -eq 262145 -or $updatepack.State -eq 327679)
    {
        #package not downloaded
        if($updatepack.State -eq 327682)
        {
            Invoke-CMSiteUpdateDownload -Name $updatepack.Name -Force -WarningAction SilentlyContinue
            Start-Sleep 120
            $updatepack = Get-CMSiteUpdate -Name $updatepack.Name -Fast
            $downloadstarttime = get-date
            while($updatepack.State -eq 327682)
            {
                
              Log-Item -logline "Waiting SCCM Upgrade package start to download, sleep 2 min..." -severity "Info"
                Start-Sleep 120
                $updatepack = Get-CMSiteUpdate -Name $updatepack.Name -Fast
                $downloadspan = New-TimeSpan -Start $downloadstarttime -End (Get-Date)
                if($downloadspan.Hours -ge 1)
                {
                    Restart-Service -DisplayName "SMS_Executive"
                    $downloadretrycount++
                    Start-Sleep 120
                    $downloadstarttime = get-date
                }
                if($downloadretrycount -ge 2)
                {
                  Log-Item -logline "Update package $($updatepack.Name) failed to start downloading in 2 hours." -severity "Info"
                    break
                }
            }
        }
        
        if($downloadretrycount -ge 2)
        {
            break
        }
        
        #waiting package downloaded
        $downloadstarttime = get-date
        while($updatepack.State -eq 262145)
        {
          Log-Item -logline "Waiting SCCM Upgrade package download, sleep 2 min..." -severity "Info"
            Start-Sleep 120
            $updatepack = Get-CMSiteUpdate -Name $updatepack.Name -Fast
            $downloadspan = New-TimeSpan -Start $downloadstarttime -End (Get-Date)
            if($downloadspan.Hours -ge 1)
            {
                Restart-Service -DisplayName "SMS_Executive"
                Start-Sleep 120
                $downloadstarttime = get-date
            }
        }

        #downloading failed
        if($updatepack.State -eq 327679)
        {
            $retrytimes++
            Start-Sleep 300
            continue
        }
    }
    
    if($downloadretrycount -ge 2)
    {
        break
    }
    
    #trigger prerequisites check after the package downloaded
    Invoke-CMSiteUpdatePrerequisiteCheck -Name $updatepack.Name
    while($updatepack.State -ne 196607 -and $updatepack.State -ne 131074 -and $updatepack.State -ne 131075)
    {
      Log-Item -logline "Waiting checking prerequisites complete, current pack $($updatepack.Name) state is $($state.($updatepack.State)), sleep 2 min..." -severity "Info"
        Start-Sleep 120
        $updatepack = Get-CMSiteUpdate -Fast -Name $updatepack.Name 
    }
    if($updatepack.State -eq 196607)
    {
        $retrytimes++
        Start-Sleep 300
        continue
    }
    #trigger setup after the prerequisites check
    Install-CMSiteUpdate -Name $updatepack.Name -SkipPrerequisiteCheck -Force
    while($updatepack.State -ne 196607 -and $updatepack.State -ne 262143 -and $updatepack.State -ne 196612)
    {
      Log-Item -logline "Waiting for SCCM Upgrade complete, current pack $($updatepack.Name) state is $($state.($updatepack.State)), sleep 2 min..." -severity "Info"
        Start-Sleep 120
        $updatepack = Get-CMSiteUpdate -Fast -Name $updatepack.Name 
    }
    if($updatepack.State -eq 196612)
    {
      Log-Item -logline "SCCM Upgrade complete, current pack $($updatepack.Name) state is $($state.($updatepack.State)), sleep 2 min..." -severity "Info"
        #we need waiting the copying files finished if there is only one site
        $toplevelsite =  Get-CMSite |where {$_.ReportingSiteCode -eq ""}
        if((Get-CMSite).count -eq 1)
        {
            $path= Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\SMS\Setup' -Name 'Installation Directory'

            $fileversion=(Get-Item ($path+'\cd.latest\SMSSETUP\BIN\X64\setup.exe')).VersionInfo.FileVersion.split('.')[2]
            while($fileversion -ne $toplevelsite.BuildNumber)
            {
                Start-Sleep 120
                $fileversion=(Get-Item ($path+'\cd.latest\SMSSETUP\BIN\X64\setup.exe')).VersionInfo.FileVersion.split('.')[2]
            }
            #Wait for copying files finished
            Start-Sleep 600
        }
        #Get if there are any other updates need to be installed
        $updatepack = getupdate 
        if($updatepack -ne "")
        {
          Log-Item -logline "Found another update package : $($updatepack.Name)" -severity "Info"
            $retrytimes = 0
            continue
        }
    }
    if($updatepack.State -eq 196607 -or $updatepack.State -eq 262143 )
    {
        if($retrytimes -le 3)
        {
            $retrytimes++
            Start-Sleep 300
            continue
        }
    }
}

Log-Item -logline "Configmgr update installed ! Finally ..." -severity "Info"
Log-Item -logline "disable IE ESC" -severity "Info"
#disable IE ESC 
$AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
$UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
Stop-Process -Name Explorer
Write-Host "IE Enhanced Security Configuration (ESC) has been disabled." -ForegroundColor Green

Log-Item -logline "Starting upgrade of configmgr console" -severity "Info"
$arguments = "DefaultSiteServerName=" + $env:computername + "." + $fulldomain + " /q"
Start-Process "C:\Program Files\Microsoft Configuration Manager\tools\ConsoleSetup\ConsoleSetup.exe" -ArgumentList $arguments -wait
Log-Item -logline "Finished upgrade of configmgr console" -severity "Info"
Log-Item -logline "Done with configmgr setup! Rebooting now.." -severity "Info"
Restart-Computer -Force
