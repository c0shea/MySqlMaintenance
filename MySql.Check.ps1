#
# This script checks all databases on the server,
# which performs an integrity check for errors for all tables.
#
. "$PSScriptRoot\MySql.Core.ps1"

$LogFileName         = Get-LogFileName -LogName "MySql.Check"
$MySqlCheckPath      = [System.IO.Path]::Combine($MySqlBinPath, "mysqlcheck.exe")

#
# Validate Parameters
#

if (!(Test-Path $MySqlCheckPath))
{
    Write-Log "mysqlcheck.exe doesn't exist at '$MySqlCheckPath'." -Level Error
}


#
# Main
#

$Databases = Get-Databases

foreach ($DatabaseName in $Databases)
{
    Write-Log "Checking $DatabaseName"

    & "$MySqlCheckPath" --defaults-file="$MySqlConfigPath" --databases $DatabaseName --check

    if (!$?)
    {
        Write-Log "Failed to check $DatabaseName" -Level Error
    }

    Write-Log "Finished checking $DatabaseName"
}

Write-Log "Finished checking all databases"
