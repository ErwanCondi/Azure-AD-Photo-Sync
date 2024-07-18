using module .\azPhoto__Classes.psm1

try
{
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch
{
    throw $_
}

function LocateDc
{
    param($domain)

    $dcLocator = nltest /dsgetdc:$domain
    
    if($dcLocator)
    {
        $dc = ($dcLocator | ? {$_ -Match 'DC: \\'}).Split('\\')[2]
        return $dc
    }
    else
    {
        throw
    }
}

function ReadImageFromAD
{
    param(
        [String]$Identity,
        [PsCredential]$Credentials,
        [string]$Dc
    )
    
    try
    {
        $byte = Get-ADUser $Identity -Properties ThumbnailPhoto -ErrorAction Stop -Credential $Credentials -Server $Dc | select -ExpandProperty ThumbnailPhoto
        return [UserImage]::New($byte)
    }
    catch
    {
        $_
    }
}

function WriteImageToADUser
{
    param(
        [string]$Identity,
        [UserImage]$Image,
        [bool]$WhatIf,
        [PsCredential]$Credentials,
        [string]$Dc
    )
    
    # WhatIf, to test the command without actually modifying
    if ($WhatIf)
    {
        Get-ADUser $Identity -Server $Dc -Credential $Credentials -ErrorAction Stop | Out-Null
        Write-Host "WhatIf: Writing picture to $Identity" -ForegroundColor Yellow -BackgroundColor Black
    }
    else
    {
        Set-ADUser $Identity -Replace @{ThumbnailPhoto=$Image.PictureByte } -Credential $Credentials -Server $Dc -ErrorAction Stop
    }
}

function RemoveImageFromAD
{
    param(
        [String]$Identity,
        [bool]$WhatIf,
        [PsCredential]$Credentials,
        [string]$Dc
    )
    
    # WhatIf, to test the command without actually modifying
    if ($WhatIf)
    {
        Get-ADUser $Identity -Server $Dc -Credential $Credentials -ErrorAction Stop | Out-Null
        Write-Host "WhatIf: Removing picture to $Identity" -ForegroundColor Yellow -BackgroundColor Black
    }
    else
    {
        Set-ADUser -Identity $Identity -Clear thumbnailphoto -Credential $Credentials -Server $Dc -ErrorAction Stop
    }
}

Export-ModuleMember -Function ReadImageFromAD,
                              WriteImageToADUser,
                              RemoveImageFromAD,
                              LocateDc