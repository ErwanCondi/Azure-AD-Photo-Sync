# import required .NET namespaces
using namespace System.Management.Automation
using namespace System.Collections.Generic
using namespace System.IO

# import base assemblies and custom classes
using module .\psmodules\azPhoto__Classes_load_assemblies.psm1
using module .\psmodules\azPhoto__Classes.psm1


if ($psISE){
    $ScriptRoot  = [Path]::GetDirectoryName($psISE.CurrentFile.FullPath)
}
else{
    $ScriptRoot  = $PSScriptRoot
}

$ROOT_DIR_MODULES     = "$ScriptRoot\psmodules"
$ROOT_DIR_DATA        = "$ScriptRoot\data"
$TEMP_DIR_PICTURE     = "$ScriptRoot\picturesTemp"
$PERM_DIR_PICTURE     = "$ScriptRoot\picturesPermanent"
$USER_MAPPING_FILE    = "$ROOT_DIR_DATA\users_mapping.xml"
$SQLITE_DB_FILE       = "$ROOT_DIR_DATA\main_sqlite.db"
$ACTIONS_FILE         = "$ROOT_DIR_DATA\actions.xml"
$DEFAULT_PICTURE_FILE = "$ROOT_DIR_DATA\default_pic.jpg"
$CONFIG_FILE          = "$ROOT_DIR_DATA\main_config-$env:USERNAME.json"
$TRANSCRIPT_FILE      = "$ROOT_DIR_DATA\transcript_photoAzUsers_Action.txt"

Start-Transcript -Path $TRANSCRIPT_FILE

try{
    # Load the configuarion file
    $CONFIG = Get-Content $CONFIG_FILE -ErrorAction Stop | ConvertFrom-Json

    # Import the custom modules
    gci $ROOT_DIR_MODULES -Filter *.psm1 | select -ExpandProperty FullName | % {Import-Module $_ -Force}
    
    # Load the private key to sign jwt
    [Print]::Display("Getting certificate from store", 'Info')
    $CERT_PATH = "Cert:\CurrentUser\My\$($CONFIG.graphAPI.certificateThumbprint)"

    # Get a graph api auth token.
    [Print]::Display("Connecting to graph API", 'Info')
    ConnectToGraphAPI -TenantID $CONFIG.graphAPI.tenantID -AppId $CONFIG.graphAPI.appID -CertificatePath $CERT_PATH

    # List all azure AD users 
    [Print]::Display("Getting the list of all users from graph API", 'Info')
    $ALL_USERS = GetGraphUsersAll
    [Print]::Display("Found $($ALL_USERS.Count)", 'Info')

    # Get the picture id if exists
    [Print]::Display("Getting the new photo mapping from graph API", 'Info')
    $GRAPH_PHOTO_MAPPING = GetGraphUserPhotoMetadata -users $ALL_USERS.id -useBatch
    
    # Connect to the DB
    SQLiteConnect -databasePath $SQLITE_DB_FILE

    # list all tables
    $tables = SQLiteListAllTables

    if ($tables.tbl_name -contains 'users' -and 'actions' -and 'photos'){
        # Loop across all AZ users comparing with saved data
        $i = 0
        foreach ($graphItem in $GRAPH_PHOTO_MAPPING){
            try{
                Write-Progress -Activity "Processing user $($graphItem.AzureId)" -PercentComplete $(100*$i / $GRAPH_PHOTO_MAPPING.Count)
                [Print]::Display("Processing user $($graphItem.AzureId)", 'Info')
                $i++
                $graphPhoto = $null
                $savedUser = SQLiteGetUser -Where @{id=$graphItem.AzureId}

                ###### Check for removed pictures
                if (!$graphItem.PhotoId -and ![string]::IsNullOrEmpty( $savedUser.photoid )){
                    # Get user information from Graph API
                    $graphUser = GetGraphUser -identity $graphItem.AzureId

                    [Print]::Display("Action : `"Remove`" on user $($graphUser.displayName) - $($graphUser.userPrincipalName)", 'Info')
                    [Print]::Display("Old Id : $($savedUser.photoid)", 'Info')

                    # Check again if the user actually have no picture, batch requests are not 100% accurate.
                    Start-Sleep -Seconds 2
                    $secondCheck = GetGraphUserPhotoMetadata -user $graphItem.AzureId
                    if ($secondCheck.PhotoId){
                        [Print]::Display("Change process dropped after 2nd check $($graphUser.displayName)", 'Info')
                        continue
                    }
            
                    
                    $savedPicName = SQLiteGetPhoto -Where @{id=$savedUser.photoid}
                    $filePath = [path]::Combine( $PERM_DIR_PICTURE, $savedPicName)

                    foreach ($thirdParty in $CONFIG.thirdParties){
                        SQLiteAddAction -Insert @{ actionname="Remove";                                                   thirdparty=$thirdParty.name;                                                   userid=$graphItem.AzureId;                                                   currentpicture=$savedUser.photoid}
                    }

                    # Remove picture id from the user
                    SQLiteUpdateUser -Where @{id=$graphItem.AzureId} -Set @{photoid=''}
                }

                ###### Check for updated pictures
                elseif($graphItem.PhotoId -ne $savedUser.photoid -and !$([string]::IsNullOrEmpty($savedUser.photoid) )){
                    # Get user information from Graph API
                    $graphUser = GetGraphUser -identity $graphItem.AzureId

                    [Print]::Display("Action : `"Update`" on user $($graphUser.displayName) - $($graphUser.userPrincipalName)", 'Info')
                    [Print]::Display("Old Id : $($savedUser.photoid) - New Id : $($graphItem.PhotoId)", 'Info')
                    
                    # Get the user's photo from graph API
                    $graphPhoto = GetGraphUserPhoto -user $graphItem.AzureId

                    $fileName = $graphItem.photoid + '_' + $graphUser.userPrincipalName + '.jpeg'
                    $filePath = [Path]::Combine( $PERM_DIR_PICTURE, $fileName)
                    $graphPhoto.WriteImageToFile($filePath)
                    
                    SQLiteAddPhoto  -Insert @{id=$graphItem.PhotoId;                                              filename=$fileName;                                              belongsto=$graphUser.AzureId}

                    foreach ($thirdParty in $CONFIG.thirdParties){
                        SQLiteAddAction -Insert @{ actionname = "Update";                                                   thirdparty = $thirdParty.name;                                                   userid = $graphItem.AzureId;                                                   currentpicture = $savedUser.photoid;                                                   newpicture = $graphItem.PhotoId}
                    }

                    # Update the PhotoId in the db
                    SQLiteUpdateUser -Where @{id=$graphItem.AzureId} -Set @{photoid=$graphItem.PhotoId}
                }

                ###### Check if the user newly added a photo or is created recently
                elseif ($graphItem.PhotoId -and [string]::IsNullOrEmpty( $savedUser.photoid )){
                    # Get user information from Graph API
                    $graphUser = GetGraphUser -identity $graphItem.AzureId

                    [Print]::Display("Action : `"Add`" on user $($graphUser.displayName) - $($graphUser.userPrincipalName)", 'Info')
                    [Print]::Display("New Id : $($graphItem.PhotoId)", 'Info')

                    # Get the user's photo from graph API
                    $graphPhoto = GetGraphUserPhoto -user $graphItem.AzureId
                
                    $fileName = $graphItem.photoid + '_' + $graphUser.userPrincipalName + '.jpeg'
                    $filePath = [Path]::Combine( $PERM_DIR_PICTURE, $fileName)

                    # Write new photo to long term storage
                    $graphPhoto.WriteImageToFile($filePath)

                    SQLiteAddPhoto -Insert @{ id = $graphItem.PhotoId;                                              filename = $fileName;                                              belongsto = $graphUser.AzureId}

                    foreach ($thirdParty in $CONFIG.thirdParties){
                        SQLiteAddAction -Insert @{ actionname = "Add";                                                   thirdparty = $thirdParty.name;                                                   userid = $graphItem.AzureId;                                                   newpicture = $graphItem.PhotoId}
                    }

                    # Add the user to the global list
                    SQLiteAddUser -Insert @{id = $graphUser.azureid;                                            displayname = $graphUser.displayName;                                            surname = $graphUser.surname;                                            givenname = $graphUser.givenname;                                            userprincipalname = $graphUser.userprincipalname;                                            onpremsid = $graphUser.OnPremSID;                                            employeeid = $graphUser.employeeid;                                            photoid = $graphItem.PhotoId}
                }
            }
            catch{
                [print]::Display("Failed to process user", "Error")
                [print]::Display($_, "Error")
                continue
            }
        }
    }
    else{
        [Print]::Display("Script 1st run", 'Info')


        New-Item -Path $TEMP_DIR_PICTURE -ItemType Directory -Force
        New-Item -Path $PERM_DIR_PICTURE -ItemType Directory -Force


        # Create the users table
        [Print]::Display("Creating users table", 'Info')
        $sqLiteCommand = "CREATE TABLE IF NOT EXISTS users(
                            id TEXT UNIQUE PRIMARY KEY,
                            dateadded DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
                            displayname TEXT,
                            surname TEXT,
                            givenname TEXT,
                            userprincipalname TEXT NOT NULL,
                            onpremsid TEXT,
                            employeeId TEXT,
                            photoid TEXT
                            );"
        SQLiteCommand -Command $sqLiteCommand -noOut

        # Create the photo table
        [Print]::Display("Creating photos table", 'Info')
        $sqLiteCommand = "CREATE TABLE photos (
                            id TEXT PRIMARY KEY,
                            dateadded DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
                            filename TEXT NOT NULL,
                            belongsto TEXT NOT NULL);"
        SQLiteCommand -Command $sqLiteCommand -noOut

        # Create the actions table
        [Print]::Display("Creating actions table", 'Info')
        $sqLiteCommand = "CREATE TABLE actions (
                            id INTEGER PRIMARY KEY,
                            dateadded DATETIME DEFAULT CURRENT_TIMESTAMP NOT NULL,
                            actionname TEXT NOT NULL,
                            thirdparty TEXT NOT NULL,
                            isactive INTEGER DEFAULT 1 NOT NULL,
                            isreported INTEGER DEFAULT 0 NOT NULL,
                            actionresults TEXT DEFAULT `"NotStarted`" NOT NULL,
                            userid TEXT NOT NULL,
                            attempts INTEGER DEFAULT 0 NOT NULL,
                            error TEXT,
                            currentpicture TEXT,
                            newpicture TEXT
                            );"
        SQLiteCommand -Command $sqLiteCommand -noOut

        $i = 0
        foreach ($graphItem in $GRAPH_PHOTO_MAPPING ){
            Write-Progress -Activity "Fetching users infos for first run" -PercentComplete $(100*$i / $GRAPH_PHOTO_MAPPING.Count)
            $i++
        
            $user = GetGraphUser -identity $graphItem.AzureId
            $user.PhotoId = $graphItem.photoid

            SQLiteAddUser -Insert @{id = $user.azureid;                                    displayname = $user.displayName;                                    surname = $user.surname;                                    givenname = $user.givenname;                                    userprincipalname = $user.userprincipalname;                                    onpremsid = $user.OnPremSID;                                    employeeid = $user.employeeid;                                    photoid = $user.photoid}
        
            if ($graphItem.photoid){
                # Get the user's photo from graph API
                $graphPhoto = GetGraphUserPhoto -user $graphItem.AzureId
        
                [Print]::Display("Saving photo - $($User.DisplayName) - $($User.UserPrincipalName)", 'Info')
                $fileName = $graphItem.photoid + '_' + $User.UserPrincipalName + '.jpeg'
                $filePath = [Path]::Combine( $PERM_DIR_PICTURE, $fileName )
                $graphPhoto.WriteImageToFile( $filePath )

                SQLiteAddPhoto -Insert @{ id = $graphItem.photoid;
                                          filename = $fileName;
                                          belongsto = $user.azureid}
            }
        }
    }
}
catch{
    ## Send error email
    & "C:\ScheduledTasks\Infra_tasks\_Mail_Reporter\_Mail_Reporter.ps1" `
    -From "infrastructure.system@uefa.ch" `
    -To "eco@uefa.ch" `
    -Subject "Azure Photos Sync - Error" `
    -MainContent "Dear admins<br/>
                    The script ran into fatal error and had to stop. Troubleshooting is required.<br/>
                    $($_ | Out-String)<br/>
                    Best regards" `
    -MainTitle "Azure Photos Sync" `
    -SecondaryTitle "Error" `    -ColorTheme Red
    [Print]::Display("Script ran into an fatal error and has to stop.", 'Error')
    break
}

[Print]::Display("Starting processing actions if any", 'Info')
$actions = SQLiteGetAction -Where @{isactive=$true}
foreach ($action in $actions){
    try{
        $action.Attempts++

        $sqliteUser = SQLiteGetUser -Where @{id=$action.userid}


        if ($action.newpicture){
            $sqliteNewPicture = SQLiteGetPhoto -Where @{id = $action.newpicture}
            $picturePath = $([Path]::Combine( $PERM_DIR_PICTURE, $sqliteNewPicture.filename))
            $newPicture = [UserImage]::GetFromFile($picturePath)
        }
        else{
            if ($sqliteUser.surname -and $sqliteUser.givenname){
                $newPicture = [UserImage]::CreateFromInitials( $sqliteUser.surname, $sqliteUser.givenname )
            }
            else{
                $newPicture = [UserImage]::CreateFromInitials( $sqliteUser.displayname)
            }
        }
        [Print]::Display("Processing : $($sqliteUser.displayName) - $($sqliteUser.Id)", 'Info')
        [Print]::Display("Action : $($action.ActionName) on $($action.ThirdParty)", 'Info')

        $thirdParty = $CONFIG.thirdParties | ? Name -eq $action.ThirdParty


        if ($thirdParty.type -eq 'azStorage'){
            $context = $(Get-Variable -Name "StorageContext_*" -ErrorAction Stop | ? Name -eq "StorageContext_$( $thirdParty.name)").Value
            
            if (!$context){
                [Print]::Display("Connecting to Az Storage", 'Info')
                $context = StorageLogin -certThumbprint $thirdParty.certificateThumbprint `                            -AppId $thirdParty.appID `                            -Tenant $thirdParty.tenantID `                            -Subscription $thirdParty.storageSubscription `                            -StorageAccount $thirdParty.storageAccount
                New-Variable -Name "StorageContext_$( $thirdParty.name)" -Value $context -Force
            }
         
            $newPicture.Resize($thirdParty.picMaxSize, $thirdParty.picMaxWeight)

            # Export picture to a file
            $filePath = [Path]::Combine( $TEMP_DIR_PICTURE, $($sqliteUser.UserPrincipalName + "_" + $action.id + '.jpeg') )
            $newPicture.WriteImageToFile($filePath)

            # Create the metadata for FAME and SAP to read
            $metaData = @{
                            "upn" = $sqliteUser.UserPrincipalName
                        }

            if ($sqliteUser.employeeId){
                $metaData.Add("sapId", $sqliteUser.employeeId)
            }

            # make the upload to storage container
            UploadToStorage -File $newPicture.PicturePath -Container $thirdParty.storageContainer -MetaData $metaData -StorageContext $context
            $action.actionresults = "Success"
        }
        elseif ($thirdParty.type -eq 'activeDirectory'){
            $ADCreds = [pscredential]::new($thirdParty.userName, $($thirdParty.password | ConvertTo-SecureString))
            
            # Trying to locate closest DC for this site
            $dc = LocateDc -domain $thirdParty.domain
            [Print]::Display("Located DC $dc for the domain $($thirdParty.domain)", 'Info')

            $whatIfValue = [bool]::Parse( $thirdParty.whatIf )
            
            if ($sqliteUser.onpremsid){
                if ($action.actionname -match "Add|Update"){
                    [Print]::Display( "Resize the picture of $($sqliteUser.userprincipalname)", 'Info')
                    $newPicture.Resize($thirdParty.picMaxSize, $thirdParty.picMaxWeight)

                    # Write image to AD user
                    [Print]::Display("Setting picture in AD", 'Info')
                    WriteImageToADUser -Identity $sqliteUser.onpremsid -Image $newPicture.PictureByte -Credentials $ADCreds -DC $dc -WhatIf $whatIfValue
                    $action.actionresults = "Success"
                }
                elseif ($action.actionname -eq 'Remove'){
                    # Clear the picture from AD
                    [Print]::Display("Removing picture from AD", 'Info')
                    RemoveImageFromAD -Identity $sqliteUser.onpremsid -Credentials $ADCreds -DC $dc -WhatIf $whatIfValue
                    $action.actionresults = 'Success'
                }
            }
            else{
                [Print]::Display("User is not from on-prem sync. Skipping active directory update.", 'Info')
                $action.error = "User is not from on-prem sync. Skipping active directory update."
                $action.actionresults = 'Skipped'
            }
        }
        else{
            throw "Third party not found"
        }
    
        $action.isactive = $false
        [Print]::Display("Action Is Success", 'Info')
    }
    catch{
        [Print]::Display("Action failed", 'Error')
        $action.error = $_.ToString()
        $action.actionresults = "Error"
    }
    finally{
        SQLiteUpdateAction -Where @{id=$action.id} -Set @{  isactive=$action.isactive;
                                                            actionresults=$action.actionresults;
                                                            attempts=$action.attempts;
                                                            errors=$action.errors}
    }
}

try{
    [Print]::Display("Deleting temp pictures if any.", 'Info')
    gci $TEMP_DIR_PICTURE -File | % {Remove-Item $_.Fullname -Force -ErrorAction Stop}
    [Print]::Display("Success", 'Info')
}
catch{
    [Print]::Display("Failed", 'Error')
}

[Print]::Display("Closing database", 'Info')
$SqLiteConnection.Close()

[Print]::Display("Script ended", 'Info')
Stop-Transcript