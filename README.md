# azure-ad-photo-sync
This script is responsible for syncing photos from Azure to other systems.
It is composed of main scripts in the root folder which will handle the logic and module scipts that contain functions and 
classes definition.

## Main Scripts definitions
### photoAzUsers_Action.ps1:
Runs the main logic, it maintain and update the local data file.
Parameters are stored in a config file, main_config.json

## Authentication and permissions
All authentications to azure is done via azure app and certificate. Certificate is imported in service account certificate store on the server running the script.
Certificate details must be addded to the GraphAPI section in the config file. Permissions are given to the App to access the GraphAPI -> Users.Read.All

## Modules definition
### azPhoto__Classes.psm1 :
Contains classes definitions. These classes will be called in main scripts and other modules to handle spcecific objects.
Relies on namespaces System.Collections/System.Drawing/System.IO which are built in.
		
### azPhoto__Classes_load_assemblies.psm1 :
Responsible for loading the necessary assemblies into the environement prior to call the "using module" on azPhoto__Classes module.
This is to address a known bug in powershell still present in PS 5 but fixed in PS 7
		
### azPhoto_ActiveDirectory.psm1 :
Provides a set of functions to interact with a local Active Directory. Read/Write/Remove an image in AD.
Relies on ActiveDirectory that can be installed with RSAT and azPhoto__Classes modules.
		
### azPhoto_AzStorage.psm1 :
Provides a set of functions to upload pictures in an azure storage.
Relies on Az.Accounts and Az.Storage modules which can be downloaded from the PS store
		
### azPhoto_GraphAPI.psm1 :
Provides a set of functions to interact with the graph API. Get User information, download user's photos
		
## How to create a certificate and import it it the Azure app and on the server :
To migrate to a different server, 1 and 2 can be skipped and just import the cert to the new server.

### 1. Create a certificate in powershell and export the .cer and .pfx. Can be ran from any computer :
```powershell
$certName = 'NAME_OF_THE_CERTIFICATE'
$cert = New-SelfSignedCertificate -Subject "CN=$certName" -KeyExportPolicy Exportable -KeySpec Signature -KeyLength 2048 -KeyAlgorithm RSA -HashAlgorithm SHA256  -CertStoreLocation "Cert:\CurrentUser\My" -NotAfter ([datetime]::Now.AddYears(20))
# Export public key
Export-Certificate -Cert $cert -FilePath "C:\Users\$env:USERNAME\Downloads\$($certname)_256_public.cer"
#export private key
$mypwd = ConvertTo-SecureString -String 'VERY_STRONG_PASSWORD_FOR_THE_PRIVATE_KEY' -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "C:\Users\$env:USERNAME\Downloads\$($certname)_256_private.pfx" -Password $mypwd -CryptoAlgorithmOption AES256_SHA256
# Optional to delete the key from your computer
Remove-Item -Path "Cert:\CurrentUser\My\$($cert.Thumbprint)" -DeleteKey
```
### 2. Import the public key in the Azure app
From https://portal.azure.com/, Go to Enterprise Applications and add the certificate to the app that has been previously created and have access to the Graph API.
### 3. Import the private key in the certificate store of the service account on the server
```powershell
Import-PfxCertificate -FilePath "PATH.pfx" -CertStoreLocation Cert:\CurrentUser\My -Password $(ConvertTo-SecureString -AsPlainText 'VERY_STRONG_PASSWORD_FOR_THE_PRIVATE_KEY' -Force)
```