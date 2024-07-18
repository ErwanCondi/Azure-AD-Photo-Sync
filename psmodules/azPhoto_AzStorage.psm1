
Import-Module Az.Accounts -RequiredVersion 2.10.3 -ErrorAction Stop
Import-Module Az.Storage -ErrorAction Stop

function StorageLogin
{
    param ([string]$certThumbprint,
           [string]$AppId,
           [string]$Tenant,
           [string]$Subscription,
           [string]$StorageAccount)

    # connect to az account
    Connect-AzAccount -CertificateThumbprint $certThumbprint -ApplicationId $AppId -Tenant $Tenant -Subscription $Subscription -ErrorAction Stop | Out-Null

    # Create a context object using Azure AD credentials
    $StorageContext = New-AzStorageContext -StorageAccountName $StorageAccount -UseConnectedAccount -ErrorAction Stop
    return $StorageContext
}

function UploadToStorage
{
    param ([string]$File,
           [string]$Container,
           [Hashtable]$Metadata,
           [Microsoft.WindowsAzure.Commands.Storage.AzureStorageContext]$StorageContext)

    # upload the file
    Set-AzStorageBlobContent -File $File -Container $Container -Properties @{"ContentType" = [System.Web.MimeMapping]::GetMimeMapping($File)} -Context $StorageContext -Force -Metadata $Metadata -ErrorAction Stop | Out-Null
}
