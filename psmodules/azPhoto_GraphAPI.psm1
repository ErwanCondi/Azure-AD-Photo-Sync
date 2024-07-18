# import required .NET namespaces
#using namespace System.Collections
using namespace System.Security.Cryptography
using namespace System.Security.Cryptography.X509Certificates
using namespace System.Text
using module .\azPhoto__Classes.psm1


function formatHttpError
{
    $streamError = $_.Exception.Response.GetResponseStream()
    $jsonError = [System.IO.StreamReader]::new( $streamError ).ReadToEnd()
    $objError = ($jsonError | ConvertFrom-Json).Error
    return $objError | select Code, `                                message, `                                @{n='Date';e={[datetime]::Parse($_.innererror.date)}}, `                                @{n='RequestId';e={$_.innererror.'request-id'}}, `                                @{n='ClientRequestId ';e={$_.innererror.'client-request-id' }}
}

function getUrl($url, $caller)
{
    $retry = 1
    do
    {
        $retry++
        try
        {
        	$authorizationHeader = @{Authorization = "Bearer $($accessToken.token)"}
            $getRequest = $null
            [print]::Display("$caller : Querying $url", "Info")
            $getRequest = Invoke-WebRequest -Method GET `
										-Uri $url `
										-headers $authorizationHeader `
										-ContentType "application/json" `
										-UseBasicParsing `                                        -ErrorAction Stop
        }
        catch [System.Net.WebException]
        {
            $cleanError = formatHttpError

            
            [print]::Display("$caller : Response code    - $($cleanError.code)", "error")
            [print]::Display("$caller : Response message - $($cleanError.message)", "error")
            [print]::Display("$caller : Request ID       - $($cleanError.RequestId)", "error")

            if ($cleanError.code -eq 'InvalidAuthenticationToken')
            {
                [print]::Display("$caller : Refreshing token", "info")
                ConnectToGraphAPI -TenantID $accessToken.TenantID -AppId $accessToken.AppId -CertificatePath $accessToken.CertificatePath
            }
            elseif ($cleanError.code -eq 'ImageNotFound' -or `                    $cleanError.code -eq 'Request_BadRequest' -or `                    $cleanError.code -eq 'EnterpriseEntityNotFound' -or `                    $cleanError.code -eq 'Request_ResourceNotFound' -or `                    $cleanError.code -eq 'Request_BadRequest')
            {
                break
            }
            else
            {   
                Start-Sleep -Milliseconds $($retry*1000*0.5)
                [print]::Display("$caller : Retrying $url", "Warning")
            }
        }
        catch
        {
            [print]::Display("$caller : $_", "error")
        }
    } while ($getRequest.StatusCode -ne 200 -and $retry -le 10)

    return $getRequest
}


function ConnectToGraphAPI
{
	param
	(
		# Base function to get a token from the Graph API using a certificate from local store
		$TenantID,
		$AppId,
		$CertificatePath
	)
	
	$Scope = "https://graph.microsoft.com/.default"

    # Get the certificate from store
    $Certificate = Get-Item $CertificatePath -ErrorAction Stop

    # Create base64 hash of certificate
    $CertificateBase64Hash = [Convert]::ToBase64String($Certificate.GetCertHash())

    # Create JWT timestamp for expiration
    $StartDate = (Get-Date "1970-01-01T00:00:00Z" ).ToUniversalTime()
    $JWTExpirationTimeSpan = (New-TimeSpan -Start $StartDate -End (Get-Date).ToUniversalTime().AddMinutes(2)).TotalSeconds
    $JWTExpiration = [math]::Round($JWTExpirationTimeSpan,0)

    # Create JWT validity start timestamp
    $NotBeforeExpirationTimeSpan = (New-TimeSpan -Start $StartDate -End ((Get-Date).ToUniversalTime())).TotalSeconds
    $NotBefore = [math]::Round($NotBeforeExpirationTimeSpan,0)

    # Create JWT header
    $JWTHeader = @{
        alg = "RS256"
        typ = "JWT"
        x5t = $CertificateBase64Hash -replace '\+','-' -replace '/','_' -replace '='
    }

    # Create JWT payload
    $JWTPayLoad = @{
        aud = "https://login.microsoftonline.com/$TenantID/oauth2/token" # What endpoint is allowed to use this JWT
        exp = $JWTExpiration # Expiration timestamp
        iss = $AppId # Issuer
        jti = [guid]::NewGuid() # JWT ID: random guid
        nbf = $NotBefore # Not to be used before
        sub = $AppId # JWT Subject
    }

    # Convert header and payload to base64
    $JWTHeaderToByte = [Encoding]::UTF8.GetBytes(($JWTHeader | ConvertTo-Json -Compress))
    $EncodedHeader = [Convert]::ToBase64String($JWTHeaderToByte)

    $JWTPayLoadToByte =  [Encoding]::UTF8.GetBytes(($JWTPayload | ConvertTo-Json -Compress))
    $EncodedPayload = [Convert]::ToBase64String($JWTPayLoadToByte)

    # Join header and Payload with "." to create a valid (unsigned) JWT
    $JWT = $EncodedHeader + "." + $EncodedPayload

    # Get the private key object of your certificate
    $PrivateKey = [RSACertificateExtensions]::GetRSAPrivateKey( $Certificate )

    # Create a signature of the JWT
    $Signature = [Convert]::ToBase64String(
        $PrivateKey.SignData([Encoding]::UTF8.GetBytes($JWT),[HashAlgorithmName]::SHA256,[RSASignaturePadding]::Pkcs1)
    ) -replace '\+','-' -replace '/','_' -replace '='

    # Join the signature to the JWT with "."
    $JWT = $JWT + "." + $Signature

    # Create a hash with body parameters
    $Body = @{
        client_id = $AppId
        client_assertion = $JWT
        client_assertion_type = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
        scope = $Scope
        grant_type = "client_credentials"
    }

    # Use the self-generated JWT as Authorization
    $Header = @{
        Authorization = "Bearer $JWT"
    }

    # Splat the parameters for Invoke-Restmethod for cleaner code
    $PostSplat = @{
        ContentType = 'application/x-www-form-urlencoded'
        Method = 'POST'
        Body = $Body
        Uri = "https://login.microsoftonline.com/$TenantID/oauth2/v2.0/token"
        Headers = $Header
    }

    $Request = Invoke-RestMethod @PostSplat
    $Global:accessToken = $Request | select @{n='expires';e={[datetime]::Now.AddSeconds($_.expires_in)}}, `
                                            @{n='token';e={$_.access_token}}, `
                                            @{n='TenantID';e={$TenantID}}, `
                                            @{n='appID';e={$AppId}}, `
                                            @{n='CertificatePath';e={$CertificatePath}}
}


function GetGraphUserPhotoMetadata
{
    # Function to get the etag (unique id) of the picture of each users.
    # uses the batch url (if more than one user is provided) to lower the amout of requests done to the api.
    # 20 items per batch as maximum allowed.

    param (
        [Parameter(Mandatory, ParameterSetName="single")]
        [String]$user,
        [Parameter(Mandatory, ParameterSetName="multi")]
        [Array]$users,
        [Parameter(ParameterSetName="multi")]
        [Switch]$useBatch
    )

    begin
    {
        # Build base variables
        $fnOutput = @()
        $batchUrl = "https://graph.microsoft.com/v1.0/`$batch"
        $usersUrl = "https://graph.microsoft.com/v1.0/users"
        [int]$requestID = 0
        $batchRequests = @()
        $usersTempOut = @()
        $batchNumber = 1
        $usersProcessed = 0
    }

    process
    {
        if ($users -and $useBatch)
        {
            foreach ($user in $users)
            {
                Write-Progress -Activity "fetching photo Ids" -PercentComplete $( 100*$fnOutput.Count / $users.Count ) -Status "Batch number : $batchNumber"

                $requestID ++
                $usersProcessed++
                # Create a custom object to store user information
                $userData = [PSCustomObject]@{
                            requestID = $requestID
                            id = $user
                            photoID = ''
                }
                $usersTempOut += $userData

                # Construct the body of individual requests and add it to the global
                $photoRequest = [pscustomobject][ordered]@{
                    id     = $requestID.ToString()
                    method = "GET"
                    url    = "/users/$($userData.id)/photo"
                }
                $batchRequests += $photoRequest

                # when global request reaches 20 items, it's time to make the query.
                if ($requestID -eq 20 -or $usersProcessed -eq $users.count)
                {
                    [print]::Display("Fetching batch $batchNumber", "info")
                    $allBatchRequests =  [pscustomobject][ordered]@{ 
                        requests = $batchRequests
                    }
            
                    $batchBody = $allBatchRequests | ConvertTo-Json -Compress

                    # Check if the token is expired and refresh if it is
                    if ($accessToken.expires -lt [datetime]::Now)
                    {
                        ConnectToGraphAPI -TenantID $accessToken.TenantID -AppId $accessToken.AppId -CertificatePath $accessToken.CertificatePath
                    }

                    # Make the query
                    try
                    {
        			    $authorizationHeader = @{Authorization = "Bearer $($accessToken.token)"}
                        $getBatchRequests = Invoke-RestMethod -Method Post `
															    -Uri $batchUrl `
															    -Body $batchBody `
															    -headers $authorizationHeader `
															    -ContentType "application/json" `
															    -UseBasicParsing
                    }
                    catch
                    {
                        $_
                        break
                    }

                    # Format properly the etag
                    foreach ($response in $getBatchRequests.responses)
                    {
                        if ($response.status -eq 200)
                        {
                            $usersTempOut[$response.id -1 ].photoId = [regex]::Match(  $response.body.'@odata.mediaEtag', '\w{64}').Value
                        }
                    }

                    # add the responses to the global output dictionary of the command
                    $usersTempOut | % { $fnOutput += [PSCustomObject]@{
                                                                            AzureId = $_.id
                                                                            PhotoId = $_.photoId
                                                                         }
                                      }
                    $requestID = 0
                    $batchRequests = @()
                    $usersTempOut = @()
                    $batchNumber++
                }
            }
        }
        elseif ($users)
        {
            foreach ($user in $users)
            {
                Write-Progress -Activity "fetching photo Ids" -PercentComplete $( 100*$fnOutput.Count / $users.Count ) -Status "Fetching for : $user"

                
                $url = $usersUrl + "/$user/photo"
                $request = getUrl -url $url -caller $MyInvocation.MyCommand.Name

                # Create a custom object to store user information
                $content = $null

                if ($request.Content)
                {
                    $content = $request.Content | ConvertFrom-Json
                }

                $fnOutput += [PSCustomObject]@{
                                                       AzureId = $user
                                                       PhotoId = [regex]::Match(  $content.'@odata.mediaEtag', '\w{64}').Value
                                                   }
            }
        }
        elseif ($user)
        {
            $url = $usersUrl + "/$user/photo"
            $request = getUrl -url $url -caller $MyInvocation.MyCommand.Name

            # Create a custom object to store user information
            $content = $null

            if ($request.Content)
            {
                $content = $request.Content | ConvertFrom-Json
            }
                
            $fnOutput = [PSCustomObject]@{
                                                AzureId = $user
                                                PhotoId = [regex]::Match(  $content.'@odata.mediaEtag', '\w{64}').Value
                                            }
        }
    }
    end
    {
        return $fnOutput
    }
}


function GetGraphUserPhoto
{
    # Function to actually download the photo data from the API
    param (
    [string]$user
    )

    begin
    {
        $url = "https://graph.microsoft.com/v1.0/users/$user/photo/`$value"
    }
    process
    {
        $request = getUrl -url $url -caller $MyInvocation.MyCommand.Name
    }
    end
    {
        if ($request.Content)
        {
            # return output as [Byte[]]
            $byte = $request.Content | ConvertFrom-Json
            return [UserImage]::GetFromByteArray($byte)
        }
    }
}


function GetGraphUsersAll
{
    # Function to get all users from Azure
    begin
    {
		# Check if the token is expired and refresh if it is
		if ($accessToken.expires -lt [datetime]::Now)
		{
			ConnectToGraphAPI -TenantID $accessToken.TenantID -AppId $accessToken.AppId -CertificatePath $accessToken.CertificatePath
		}

        $authorizationHeader = @{Authorization = "Bearer $($accessToken.token)"}
        $url = "https://graph.microsoft.com/v1.0/users?`$count=true&`$filter=userType eq 'Member'&`$select=id,employeeId,onPremisesExtensionAttributes&`$top=999"
        $users = @()
    }
    process
    {
        # Make the calls.
        # Each call returns a "odata.nextLink" if more objects are available to return.
        # Loop recurse until no "odata.nextLink" is returned wich means we've reach the end
        do
        {
            $jsonOutPut = Invoke-WebRequest -Method Get `
											-Uri $url `
											-Headers $authorizationHeader `
											-ContentType 'Application/Json' `
											-UseBasicParsing
            $operationResult = $jsonOutPut.Content | ConvertFrom-Json
            $users += $operationResult.Value
            $url = $operationResult.'@odata.nextLink'

        } while ($operationResult.'@odata.nextLink')
    }
    end
    {
        # returns an array of UserPrincipalNames
        return $users | select id,employeeId,@{n='ExtensionAttributes';e={$_.onPremisesExtensionAttributes}}
    }
}


function GetGraphUser
{
    param(
        [string]$identity
        )

    # Function to get all infos from Az AD user
    begin
    {
        $url = "https://graph.microsoft.com/v1.0/users/$($identity)?`$select=displayName,surname,givenName,userPrincipalName,onPremisesSecurityIdentifier,id,employeeId,onPremisesExtensionAttributes"
    }
    process
    {

        $request = getUrl -url $url -caller $MyInvocation.MyCommand.Name

        if ($request.Content)
        {
            $content = $request.Content | ConvertFrom-Json
        }

        $output = $content | select DisplayName, `                                    Surname, `                                    GivenName, `                                    UserPrincipalName, `                                    @{n='OnPremSID';e={$_.onPremisesSecurityIdentifier}}, `                                    @{n='AzureId';e={$_.id}},`                                    EmployeeId, `
                                    PhotoId, `                                    @{n='ExtensionAttributes';e={$_.onPremisesExtensionAttributes}}
    }
    end
    {
        return $output
    }
}


Export-ModuleMember -Function ConnectToGraphAPI,
                              GetGraphUserPhotoMetadata,
                              GetGraphUserPhoto,
                              GetGraphUsersAll,
                              GetGraphUser


                                                