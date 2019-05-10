#
# This script backups up all databases on the server
#
. "$PSScriptRoot\MySql.Core.ps1"

# Begin Configuration
$BackupPath          = "D:\Backup\MySQL"
$DaysOfBackupsToKeep = 8
# End Configuration

$LogFileName         = Get-LogFileName -LogName "MySql.Backup"
$MySqlDumpPath       = [System.IO.Path]::Combine($MySqlBinPath, "mysqldump.exe")

Add-Type -Assembly 'System.IO.Compression'
Add-Type -Assembly 'System.IO.Compression.FileSystem'

#
# Functions
#

function Get-BackupFileName
{
    Param
    (
        [Parameter(Mandatory = $true)]
        [string] $DatabaseName
    )

    $DatabaseBackupPath = [System.IO.Path]::Combine($BackupPath, $DatabaseName)
    $BackupFileName = [System.IO.Path]::Combine($DatabaseBackupPath, "$DatabaseName-$((Get-Date).ToString("yyyy-MM-ddTHH-mm-ss")).sql")
    
    if (!(Test-Path $DatabaseBackupPath))
    {
        Write-Log "Creating directory '$DatabaseBackupPath'"
        # Pipe output to Out-Null otherwise the path created is prepended to the $backupFileName
        # which causes errors for the caller
        New-Item -ItemType Directory -Force -Path "$DatabaseBackupPath" | Out-Null
    }
    
    return $BackupFileName
}

function Compress-File
{
    Param
    (
        [Parameter(Mandatory = $true)]
        [string] $FileName
    )

    Write-Log "Compressing '$FileName'"

    $ZipFileName = [System.IO.Path]::ChangeExtension($FileName, ".zip")
    $FileNameWithoutPath = [System.IO.Path]::GetFileName($FileName)

    try
    {
        [System.IO.Compression.ZipArchive] $ZipArchive = [System.IO.Compression.ZipFile]::Open($ZipFileName, ([System.IO.Compression.ZipArchiveMode]::Create))
        # Assign the output to $null to suppress writing the ZipArchive to the console
        $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($ZipArchive, $FileName, $FileNameWithoutPath)
    }
    finally
    {
        $ZipArchive.Dispose()
    }

    return $ZipFileName
}

function Remove-OldBackups
{
    $RemoveBackupsOlderThanDate = (Get-Date).AddDays(-$DaysOfBackupsToKeep)
    Write-Log "Removing backups older than $RemoveBackupsOlderThanDate"

    Get-ChildItem $BackupPath -Recurse | Where-Object { $_.LastWriteTime -lt $RemoveBackupsOlderThanDate } | Remove-Item
}

#
# Validate Parameters
#
if (!(Test-Path $BackupPath))
{
    Write-Log "The specified backup path '$BackupPath' doesn't exist." -Level Error
}

if (!(Test-Path $MySqlDumpPath))
{
    Write-Log "mysqldump.exe doesn't exist at '$MySqlDumpPath'." -Level Error
}


#
# Main
#

$Databases = Get-Databases

foreach ($DatabaseName in $Databases)
{
    Write-Log "Backing up $DatabaseName"

    $BackupFileName = Get-BackupFileName -databaseName $DatabaseName
    
    & "$MySqlDumpPath" --defaults-file="$MySqlConfigPath" --databases $DatabaseName --result-file="$BackupFileName" --routines --triggers --events | Out-File $LogFileName -Append

    if (!$?)
    {
        Write-Log "Failed to backup $DatabaseName" -Level Error
    }

    $CompressedBackupFileName = Compress-File -fileName $BackupFileName

    if (!$?)
    {
        Write-Log "Failed to compress backup '$BackupFileName'" -Level Error
    }

    Remove-Item -Path $BackupFileName

    Write-Log "Finished backing up $DatabaseName to '$CompressedBackupFileName'"
}

Remove-OldBackups

if (!$?)
{
    Write-Log "Failed to remove old backups" -Level Error
}

Write-Log "Finished backing up all databases"
