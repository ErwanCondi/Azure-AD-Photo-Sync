
using namespace System.IO

$assemblies = $('System.Drawing',
                'System.IO',
                'System.Collections')


foreach ($assembly in $assemblies)
{
    $dll = gci "C:\Windows\Microsoft.NET\assembly" -Recurse -File -Filter $($assembly + '.dll')
    Add-Type -Path $dll.FullName
}

$sqLitePath = [Path]::Combine( $PSScriptRoot, "bin", "SQLite", "System.Data.SQLite.dll")
$sqLitePath
[void] [System.Reflection.Assembly]::LoadFile($sqLitePath)