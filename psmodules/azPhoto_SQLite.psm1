

using namespace System.Data.SQLite
using namespace System.IO
using namespace System.Data

using module .\azPhoto__Classes.psm1


# helper functions
function ConvertParameters
{
    param(
        [Hashtable]$Param,
        [validateSet('Where','Set','Insert')]
        [string]$Statement
    )

    if ($Param)
    {
        $conditions = foreach ($key in $Param.Keys)
        {
            try
            {
                $value = $Param[$key]
                $typeName = $value.GetType().FullName

                switch ($typeName)
                {
                    { $_ -eq 'System.Boolean' }
                    {
                        @{$key=$([convert]::ToInt16($value))}
                        break
                    }

                    { $_ -eq 'System.String' }
                    {
                        @{$key="`"$($value)`""}
                        break
                    }

                    { $_ -match 'System.Int' -or $_ -eq 'System.Double' -or $_ -eq 'System.Decimal' }
                    {
                        @{$key=$([convert]::ToDouble($value))}
                        break
                    }
                }
            }catch {continue}
        }

        if ($Statement -eq "Where")
        {
            return "WHERE $( [String]::Join(' AND ', $( $conditions | % { "$($_.Keys)=$($_.Values)" } )))"
        }
        elseif ($Statement -eq "Set")
        {
            return "SET $( [String]::Join(',', $( $conditions | % { "$($_.Keys)=$($_.Values)" } )))"
        }
        elseif ($Statement -eq "Insert")
        {
            return "( $([String]::Join(',', $conditions.Keys)) ) VALUES ( $( [String]::Join(',', $conditions.Values ) ) )"
        }
    }
}

function CheckDBNull($value)
{
    if ($value -eq [System.DBNull]::Value){return $null}
    else{return $value}
}


# general functions
function SQLiteConnect
{
    param(
        [string]$databasePath
        )
    try
    {
        $global:SqLiteConnection = [System.Data.SQLite.SQLiteConnection]::new()
        $SqLiteConnection.ConnectionString = "Data Source=$databasePath"
        $SqLiteConnection.Open()
        [print]::Display("Database file is open. $databasePath", "info")
    }
    catch
    {
        [print]::Display("Database file failed open. $databasePath", "error")
        [print]::Display("$_", "error")
    }
}

function SQLiteCommand
{
    param(
    [String]$Command,
    [switch]$noOut)

    try
    {
        [print]::Display($Command, "Info")
        $sqlQuery = $SqLiteConnection.CreateCommand()
        $sqlQuery.CommandText = $Command

        $adapter = [SQLiteDataAdapter]::new( $sqlQuery )
        $data = [DataSet]::New()
        [void]$adapter.Fill($data)
        if (!$noOut)
        {
            return $data
        }
    }
    catch
    {
        [print]::Display($Command, "error")
        [print]::Display($_, "error")
        throw $_
    }
}

function SQLiteListAllTables
{
    $sqLiteCommand = "SELECT * FROM sqlite_master"
    return SQLiteCommand -Command $sqLiteCommand | select -ExpandProperty Tables
}

# Users table functions
function SQLiteAddUser
{
    param
    (
        [HashTable]$Insert
    )

    $InsertStatement = ConvertParameters -Param $Insert -Statement Insert
    # Add a user
    $sqLiteCommand = "INSERT OR REPLACE INTO users$InsertStatement;"
    SQLiteCommand -Command $sqLiteCommand -noOut
}

function SQLiteGetUser
{
    param(
        [Hashtable]$Where
    )
    
    $whereStatement = ConvertParameters -Param $Where -Statement Where

    $sqLiteCommand = "SELECT * FROM users $whereStatement;"

    $table = SQLiteCommand -Command $sqLiteCommand | select -ExpandProperty Tables

    return $table.Rows | select id,
                                dateadded,
                                @{n='displayname';e={CheckDBNull -value $_.displayname}},
                                @{n='surname';e={CheckDBNull -value $_.surname}},
                                @{n='givenname';e={CheckDBNull -value $_.givenname}},
                                userprincipalname,
                                @{n='onpremsid';e={CheckDBNull -value $_.onpremsid}},
                                @{n='employeeId';e={CheckDBNull -value $_.employeeId}},
                                @{n='photoid';e={CheckDBNull -value $_.photoid}}
}

function SQLiteUpdateUser
{
    param(
        [HashTable]$Where,
        [HashTable]$Set
    )
    
    $setStatement = ConvertParameters -Param $Set -Statement Set
    $whereStatement = ConvertParameters -Param $Where -Statement Where
    $sqLiteCommand = "UPDATE users $setStatement $whereStatement;"
    SQLiteCommand -Command $sqLiteCommand -noOut
}

# Photos table functions
function SQLiteAddPhoto
{
    param
    (
        [HashTable]$Insert # id, filename, belongsto
    )
    
    $InsertStatement = ConvertParameters -Param $Insert -Statement Insert
    # Add a photo
    $sqLiteCommand = "INSERT OR REPLACE INTO photos$InsertStatement;"
    SQLiteCommand -Command $sqLiteCommand -noOut
}

function SQLiteGetPhoto
{
    param(
        [Hashtable]$Where
    )
    
    $whereStatement = ConvertParameters -Param $Where -Statement Where

    $sqLiteCommand = "SELECT * FROM photos $whereStatement;"

    $table = SQLiteCommand -Command $sqLiteCommand | select -ExpandProperty Tables
    return $table.Rows
}

# actions table functions
function SQLiteAddAction
{
    param
    (
        [HashTable]$Insert # actionname, thirdparty, userid, currentpicture, newpicture
    )
    
    $InsertStatement = ConvertParameters -Param $Insert -Statement Insert
    # Add a photo
    $sqLiteCommand = "INSERT OR REPLACE INTO actions$InsertStatement;"
    SQLiteCommand -Command $sqLiteCommand -noOut
}

function SQLiteGetAction
{
    param(
        [Hashtable]$Where
    )
    
    $whereStatement = ConvertParameters -Param $Where -Statement Where

    $sqLiteCommand = "SELECT * FROM actions $whereStatement;"
    
    $table = SQLiteCommand -Command $sqLiteCommand | select -ExpandProperty Tables
    return $table.Rows | select id,
                         dateadded,
                         actionname,
                         thirdparty,
                         @{n='isactive';e={[convert]::ToBoolean($_.isactive) }},
                         @{n='isreported';e={[convert]::ToBoolean($_.isreported)}},
                         actionresults,
                         userid,
                         attempts,
                         @{n='error';e={CheckDBNull -value $_.errors}},
                         @{n='currentpicture';e={CheckDBNull -value $_.currentpicture}},
                         @{n='newpicture';e={CheckDBNull -value $_.newpicture}}
}

function SQLiteUpdateAction
{
    param(
        [HashTable]$Where,
        [HashTable]$Set
    )
    
    $setStatement = ConvertParameters -Param $Set -Statement Set
    $whereStatement = ConvertParameters -Param $Where -Statement Where
    $sqLiteCommand = "UPDATE actions $setStatement $whereStatement;"
    SQLiteCommand -Command $sqLiteCommand -noOut
}

Export-ModuleMember -Function SQLiteConnect,
                              SQLiteCommand,
                              SQLiteListAllTables,
                              SQLiteAddUser,
                              SQLiteGetUser,
                              SQLiteUpdateUser,
                              SQLiteAddPhoto,
                              SQLiteGetPhoto,
                              SQLiteAddAction,
                              SQLiteGetAction,
                              SQLiteUpdateAction


<#
$local_PhotoMapping | % { SQLiteAddUser -azureid $_.azureid `                                        -displayname $_.displayName `                                        -surname $_.surname `                                        -givenname $_.givenname `                                        -userprincipalname $_.userprincipalname `                                        -onpremsid $_.OnPremSID `                                        -employeeid $_.employeeid `                                        -photoid $_.photoid }





$actions | % { SQLiteAddAction -ActionName $_.ActionName -ThirdParty $_.ThirdParty -UserId $_.User.AzureId -CurrentPicture $_.User.PhotoId -NewPicture $([guid]::NewGuid().Guid.Replace('-','')) }

$SqLiteConnection.Close()
#>


$Where = @{userid='e0293d2b-66d7-4f06-b7f2-816c74bb3fd7';isactive=$false;actionresults="NotStarted"}


$conditions = @()
$conditions = foreach ($key in $Where.Keys)
{
    $value = $Where[$key]
    $typeName = $value.GetType().FullName

    switch ($typeName)
    {
        { $_ -eq 'System.Boolean' }
        {
            "$key=$([convert]::ToInt16($value))"
            break
        }

        { $_ -eq 'System.String' }
        {
            "$key=`"$($value)`""
            break
        }

        { $_ -eq 'System.Int32' -or $_ -eq 'System.Double' -or $_ -eq 'System.Decimal' }
        {
            "$key=$value"
            break
        }
    }
}

if ($conditions)
{
    $whereStatement = "WHERE $([string]::Join(',', $conditions))"
}

