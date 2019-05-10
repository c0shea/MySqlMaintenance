#
# This script optimizes all databases on the server,
# which performs index maintenance and physical storage reorganization for all tables.
#
. "$PSScriptRoot\MySql.Core.ps1"

$LogFileName         = Get-LogFileName -LogName "MySql.Optimize"
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
    Write-Log "Optimizing $DatabaseName"

    & "$MySqlCheckPath" --defaults-file="$MySqlConfigPath" --databases $DatabaseName --optimize | Out-File $LogFileName -Append

    if (!$?)
    {
        Write-Log "Failed to optimize $DatabaseName" -Level Error
    }

    Write-Log "Finished optimizing $DatabaseName"
}

Write-Log "Finished optimizing all databases"
