#
# This script analyzes all databases on the server,
# which updates statistics for all tables
#
. "$PSScriptRoot\MySql.Core.ps1"

$LogFileName         = Get-LogFileName -LogName "MySql.Analyze"
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
    Write-Log "Analyzing $DatabaseName"

    & "$MySqlCheckPath" --defaults-file="$MySqlConfigPath" --databases $DatabaseName --analyze | Out-File $LogFileName -Append

    if (!$?)
    {
        Write-Log "Failed to analyze $DatabaseName" -Level Error
    }

    Write-Log "Finished analyzing $DatabaseName"
}

Write-Log "Finished analyzing all databases"
