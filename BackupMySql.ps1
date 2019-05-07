$BackupPath          = "D:\Backup\MySQL"
$MySqlDumpPath       = "C:\Program Files\MySQL\MySQL Server 5.7\bin\mysqldump.exe"
$DaysToKeep          = 8

$MySqlDumpConfigPath = [System.IO.Path]::Combine($PSScriptRoot, "mysqldump.cnf")
$MySqlDataDllPath    = [System.IO.Path]::Combine($PSScriptRoot, "MySql.Data.dll")
$ProtobufDllPath     = [System.IO.Path]::Combine($PSScriptRoot, "Google.Protobuf.dll")

#
# Validate Parameters
#
if (!(Test-Path $BackupPath))
{
    Write-Error "The specified backup path '$backupPath' doesn't exist."
    exit 1
}

if (!(Test-Path $MySqlDumpPath))
{
    Write-Error "The specified path '$MySqlDumpPath' to mysqldump.exe doesn't exist."
    exit 2
}

if (!(Test-Path $MySqlDumpConfigPath))
{
    Write-Error "mysqldump.cnf doesn't exist at '$MySqlDumpConfigPath'."
    exit 4
}

if (!(Test-Path $MySqlDataDllPath))
{
    Write-Error "MySql.Data.dll doesn't exist at '$MySqlDataDllPath'."
    exit 8
}

if (!(Test-Path $ProtobufDllPath))
{
    Write-Error "Google.Protobuf.dll doesn't exist at '$ProtobufDllPath'."
    exit 16
}

Add-Type -Assembly 'System.IO.Compression'
Add-Type -Assembly 'System.IO.Compression.FileSystem'
Add-Type -Path $ProtobufDllPath
Add-Type -Path $MySqlDataDllPath

#
# Functions
#
# Get-IniFile from https://stackoverflow.com/a/43697842/4403297
function Get-IniFile 
{  
    param(  
        [parameter(Mandatory = $true)] [string] $filePath  
    )  

    $anonymous = "NoSection"

    $ini = @{}  
    switch -regex -file $filePath  
    {  
        "^\[(.+)\]$" # Section  
        {  
            $section = $matches[1]  
            $ini[$section] = @{}  
            $CommentCount = 0  
        }  

        "^(;.*)$" # Comment  
        {  
            if (!($section))  
            {  
                $section = $anonymous  
                $ini[$section] = @{}  
            }  
            $value = $matches[1]  
            $CommentCount = $CommentCount + 1  
            $name = "Comment" + $CommentCount  
            $ini[$section][$name] = $value  
        }   

        "(.+?)\s*=\s*(.*)" # Key  
        {  
            if (!($section))  
            {  
                $section = $anonymous  
                $ini[$section] = @{}  
            }  
            $name,$value = $matches[1..2]  
            $ini[$section][$name] = $value  
        }  
    }  

    return $ini  
}

function Log
{
    Param ([parameter(Mandatory = $true)][string] $message)

    Write-Host "$((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) | $message"
}

function Get-Databases
{
    Log "Getting list of databases"
    [string[]] $databases = @()

    try
    {
        $iniFile = Get-IniFile "$MySqlDumpConfigPath"

        $connectionStringBuilder = New-Object -TypeName MySql.Data.MySqlClient.MySqlConnectionStringBuilder
        $connectionStringBuilder.Server = "localhost"
        $connectionStringBuilder.UserID = $iniFile.mysqldump.user
        $connectionStringBuilder.Password = $iniFile.mysqldump.password

        $db = New-Object -TypeName MySql.Data.MySqlClient.MySqlConnection
        $db.ConnectionString = $connectionStringBuilder.ToString()
        $db.Open()

        $query = New-Object -TypeName MySql.Data.MySqlClient.MySqlCommand
        $query.Connection = $db
        $query.CommandText = "select schema_name from information_schema.schemata where schema_name not in ('performance_schema', 'information_schema') order by schema_name;"
    
        $reader = $query.ExecuteReader()
        while ($reader.Read())
        {
            $Databases += $reader["schema_name"]
        }
    }
    finally
    {
        $reader.Dispose()
        $query.Dispose()
        $db.Dispose()
    }

    return $databases
}

function Get-BackupFileName
{
    Param ([parameter(Mandatory = $true)][string] $databaseName)

    $databaseBackupPath = [System.IO.Path]::Combine($BackupPath, $databaseName)
    $backupFileName = [System.IO.Path]::Combine($databaseBackupPath, "$databaseName-$((Get-Date).ToString("yyyy-MM-ddTHH-mm-ss")).sql")
    
    if(!(Test-Path $databaseBackupPath))
    {
        Log "Creating directory '$databaseBackupPath'"
        # Pipe output to Out-Null otherwise the path created is prepended to the $backupFileName
        # which causes errors for the caller
        New-Item -ItemType Directory -Force -Path "$databaseBackupPath" | Out-Null
    }
    
    return $backupFileName
}

function Compress-File
{
    Param ([parameter(Mandatory = $true)][string] $fileName)

    $zipFileName = [System.IO.Path]::ChangeExtension($fileName, ".zip")
    $fileNameWithoutPath = [System.IO.Path]::GetFileName($fileName)

    try
    {
        [System.IO.Compression.ZipArchive] $zipArchive = [System.IO.Compression.ZipFile]::Open($zipFileName, ([System.IO.Compression.ZipArchiveMode]::Create))
        # Assign the output to $null to suppress writing the ZipArchive to the console
        $null = [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zipArchive, $fileName, $fileNameWithoutPath)
    }
    finally
    {
        $zipArchive.Dispose()
    }

    return $zipFileName
}

function Remove-OldBackups
{
    $removeBackupsOlderThanDate = (Get-Date).AddDays(-$DaysToKeep)
    Log "Removing backups older than $removeBackupsOlderThanDate"

    Get-ChildItem $BackupPath -Recurse | Where-Object { $_.LastWriteTime -lt $removeBackupsOlderThanDate } | Remove-Item
}

#
# Main
#
$Databases = Get-Databases

foreach ($databaseName in $Databases)
{
    Log "Backing up $databaseName"

    $backupFileName = Get-BackupFileName -databaseName $databaseName
    
    & "$MySqlDumpPath" --defaults-file="$MySqlDumpConfigPath" --databases $databaseName --result-file="$backupFileName" --routines --triggers --events

    if (!$?)
    {
        Log "Failed to backup $databaseName"
        exit 32
    }

    $compressedBackupFileName = Compress-File -fileName $backupFileName

    if (!$?)
    {
        Log "Failed to compress backup '$backupFileName'"
        exit 64
    }

    Remove-Item -Path $backupFileName

    Log "Finished backing up $databaseName to '$compressedBackupFileName'"
}

Remove-OldBackups

if (!$?)
{
    Log "Failed to remove old backups"
    exit 128
}

Log "Finished backing up all databases"
