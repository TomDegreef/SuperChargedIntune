<#
.SYNOPSIS
	This Script configures a cloud management gateway.
.DESCRIPTION
        - Once the Configure-SCCM Script has run and updated SCCM to version 2303 (or beyond). This script can be used to setup the CMG.
        The script currently uses self-signed certificates to allow unattended setup, but once the setup is done, you can replace the certificates with your own PKI or public certificates.
.NOTES
    FileName:    Configure-CMG.ps1
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
[CmdletBinding()]
param (
    [Parameter(
        Mandatory=$true,
        HelpMessage="Provide the subscription ID for your Azure subscription that the CMG will be created in."
    )]
    [String]$SubscriptionID,
    [Parameter(
        Mandatory=$true,
        HelpMessage="Provide the name of the resource group that the CMG will be created in."
    )]
    [String]$groupname,
    [Parameter(
        Mandatory=$true,
        HelpMessage="Provide the name of the Azure Region that the CMG be created in."
    )]
    [ValidateSet(
        'eastus', 'eastus2', 'centralus', 'southcentralus', 'westus', 'northcentralus', 'westcentralus',
        'canadacentral', 'canadaeast', 'brazilsouth', 'northeurope', 'westeurope', 'uksouth', 'ukwest',
        'francecentral', 'francesouth', 'switzerlandnorth', 'switzerlandwest', 'germanywestcentral',
        'germanynorth', 'norwayeast', 'norwaywest', 'netherlandswest', 'australiacentral', 'australiasoutheast',
        'australiaeast', 'southeastasia', 'eastasia', 'japaneast', 'japanwest', 'koreacentral', 'koreasouth',
        'southafricanorth', 'southafricawest', 'uaecentral', 'uaenorth', 'centralindia', 'southindia',
        'westindia', 'indonesiacentral', 'indonesiaeast', 'vietnamnortheast', 'malaysia', 'eastus2euap',
        'westus3', 'southafricawest2'
    )]
    [string]$region
)

# This script will create a new CMG with a new self signed certificate and a new AAD app registration
Import-Module -Name Az

$SelfSignedPath = 'C:\selfsigned'
$rootCAparams = @{
    DnsName           = 'Temp CloudCM Root Cert'
    KeyLength         = 2048
    KeyAlgorithm      = 'RSA'
    HashAlgorithm     = 'SHA256'
    KeyExportPolicy   = 'Exportable'
    NotAfter          = (Get-Date).AddYears(5)
    CertStoreLocation = 'Cert:\LocalMachine\My'
    KeyUsage          = 'CertSign', 'CRLSign' #fixes invalid certificate error
}

new-item -itemtype directory $SelfSignedPath
sl $SelfSignedPath
$rootCA = New-SelfSignedCertificate @rootCAparams

$CertStore = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Store([System.Security.Cryptography.X509Certificates.StoreName]::Root, 'LocalMachine')
$CertStore.open('MaxAllowed')
$CertStore.add($rootCA)
$CertStore.close()

$rootCA
Write-Host "Created RootCA with thumbprint $($rootCA.Thumbprint)"

Export-Certificate -Cert $rootCA -FilePath C:\selfsigned\rootCA.cer

$randnr = Get-Random -Minimum 1000000 -Maximum 9999999
$Dnsname = "MycloudCmg$randnr.westeurope.cloudapp.azure.com"

$ServerCertParams = @{
    DnsName           = $Dnsname
    Signer            = $rootCA # &amp;amp;amp;amp;amp;lt;------ Notice the Signer is the newly created RootCA
    KeyLength         = 2048
    KeyAlgorithm      = 'RSA'
    HashAlgorithm     = 'SHA256'
    KeyExportPolicy   = 'Exportable'
    NotAfter          = (Get-Date).AddYears(2)
    CertStoreLocation = 'Cert:\LocalMachine\My'
}
$ServerCert = New-SelfSignedCertificate @ServerCertParams
Export-PfxCertificate -Cert $ServerCert -FilePath C:\selfsigned\ServerCert.pfx -Password (ConvertTo-SecureString -String 'P@ssw0rd' -Force -AsPlainText)
Write-Host "Created ServerCert with thumbprint $($ServerCert.Thumbprint)"

Connect-AzAccount -Subscription $SubscriptionID

Import-Module "C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager\configurationmanager.psd1" -force                       
$SiteCode = Get-PSDrive -PSProvider CMSITE
Set-Location "$($SiteCode):\"

Write-host "Creating Azure AD App..."
$i = 1
do {
    $i
    $serverapp = New-CMAADServerApplication -AppName "CloudCMADDSServerApp$randnr"
    Write-Host "Trying to Register the Azure AD Server App..."
    $i += 1
    start-sleep -Seconds 20
}
until ($serverapp -ne $null -or $i -ge 13)

If ($serverapp -eq $null) { 
    Write-error "Failed to create ServerApp, halting script"
    Break 
}
Write-host "ServerApp created successfully"
$clientapp = New-CMAADClientApplication -AppName "CloudCMADDSClientApp$randnr" -InputObject $serverapp
Write-host "ClientApp created successfully"

New-CMCloudManagementAzureService -ClientApp $clientapp -ServerApp $serverapp -Name "CloudCMADDS CloudManagement"
Write-host "Azure Service created successfully"
Set-CMCloudManagementAzureService -name "Cloudcmadds cloudmanagement" -EnableAADGroupSync $true
Write-host "AAD Group Sync enabled successfully"

start-sleep -Seconds 120 #waiting for azure services to be fully configured before starting CMG install

Write-host "Creating CMG..."
new-cmcloudmanagementgateway -servicecertpassword (ConvertTo-SecureString -String 'P@ssw0rd' -Force -AsPlainText) -servicecertpath "C:\selfsigned\ServerCert.pfx" -enableclouddpfunction $true -environmentsetting AzurePublicCloud -region $region -subscriptionid $SubscriptionID -groupname $groupname

Do {
    $CMGStatus = Get-CMCloudManagementGateway
    Write-Host "Waiting for CMG to be ready. Status is $($CMGStatus.State) and statusdetails is $($CMGStatus.Statusdetails)"
    start-sleep -Seconds 30
}   until ($CMGStatus.State -eq 0 -and $CMGStatus.StatusDetails -eq 1) 

$fulldomain = (gwmi -class win32_computersystem).domain
Write-host "Creating the CMG Connection Point..."
Add-CMCloudManagementGatewayConnectionPoint -CloudManagementGatewayName $Dnsname -sitesystemservername "$env:computername.$fulldomain"
Write-host "Configuring the CMG Connection Point..."
Set-CMManagementPoint -EnableCloudGateway $true -SiteSystemServerName "$env:computername.$fulldomain"

$boundarygroup = Get-CimInstance -Namespace root\sms\site_001 -ClassName SMS_DefaultBoundaryGroup
$servernalpath = (Get-CMDistributionPoint).NalPath
Invoke-CimMethod -InputObject $BoundaryGroup -MethodName AddSiteSystem -Arguments @{ServerNALPath = [string[]]"$servernalpath"; Flags = ([System.UInt32[]]0) } -Verbose

Write-host "Configuring the client settings for cloud management..."
Set-CMClientSetting -CloudService -AllowCloudDistributionPoint $true -Name 'Default Client Agent Settings' 
set-cmclientsetting -ClientPolicy -EnableUserPolicy $true -EnableUserPolicyOnInternet $true -Name 'Default Client Agent Settings'
Write-host "Configuring the boundary groups for cloud management..."
Set-CMDefaultBoundaryGroup -IncludeCloudBasedSources $true -PreferCloudBasedSources $true
Set-CMSoftwareMeteringSetting -AutoCreateDisabledRule $False
Write-host "All done! Enjoy your supercharged Intune environment!"