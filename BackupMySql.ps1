$BackupPath          = "D:\Backup\MySQL"
$MySqlDumpPath       = "C:\Program Files\MySQL\MySQL Server 5.7\bin\mysqldump.exe"
$DaysToKeep          = 8
$LogFilePath         = "D:\Apps\Logs"

$LogFileName         = [System.IO.Path]::Combine($LogFilePath, "BackupMySql-$((Get-Date).ToString("yyyy-MM-ddTHH-mm-ss")).log")
$MySqlDumpConfigPath = [System.IO.Path]::Combine($PSScriptRoot, "mysqldump.cnf")
$MySqlDataDllPath    = [System.IO.Path]::Combine($PSScriptRoot, "MySql.Data.dll")
$ProtobufDllPath     = [System.IO.Path]::Combine($PSScriptRoot, "Google.Protobuf.dll")

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

function Write-Log
{
    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory = $true)]
        [string] $Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("Error", "Warn", "Info")]
        [string]$Level = "Info"
    )

    $FormattedMessage = "$((Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) | $($Level.ToUpper()) | $Message"

    if (!(Test-Path $LogFileName))
    {
        New-Item -ItemType File -Force -Path "$LogFileName" | Out-Null
    }

    $FormattedMessage | Out-File -FilePath $LogFileName -Append

    switch ($Level)
    {
        'Error'
        {
            Write-Error $FormattedMessage
            exit 1
        }

        'Warn'
        {
            Write-Warning $FormattedMessage
        }

        'Info'
        {
            Write-Host $FormattedMessage
        }
    }
}

function Get-Databases
{
    Write-Log "Getting list of databases"
    [string[]] $Databases = @()

    try
    {
        $IniFile = Get-IniFile "$MySqlDumpConfigPath"

        $ConnectionStringBuilder = New-Object -TypeName MySql.Data.MySqlClient.MySqlConnectionStringBuilder
        $ConnectionStringBuilder.Server = "localhost"
        $ConnectionStringBuilder.UserID = $IniFile.mysqldump.user
        $ConnectionStringBuilder.Password = $IniFile.mysqldump.password

        $Db = New-Object -TypeName MySql.Data.MySqlClient.MySqlConnection
        $Db.ConnectionString = $ConnectionStringBuilder.ToString()
        $Db.Open()

        $Query = New-Object -TypeName MySql.Data.MySqlClient.MySqlCommand
        $Query.Connection = $Db
        $Query.CommandText = "select schema_name from information_schema.schemata where schema_name not in ('performance_schema', 'information_schema') order by schema_name;"
    
        $Reader = $Query.ExecuteReader()
        while ($Reader.Read())
        {
            $Databases += $Reader["schema_name"]
        }
    }
    finally
    {
        $Reader.Dispose()
        $Query.Dispose()
        $Db.Dispose()
    }

    return $Databases
}

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
    $RemoveBackupsOlderThanDate = (Get-Date).AddDays(-$DaysToKeep)
    Write-Log "Removing backups older than $RemoveBackupsOlderThanDate"

    Get-ChildItem $BackupPath -Recurse | Where-Object { $_.LastWriteTime -lt $RemoveBackupsOlderThanDate } | Remove-Item
}

#
# Validate Parameters
#
if (!(Test-Path $BackupPath))
{
    Write-Log "The specified backup path '$backupPath' doesn't exist." -Level Error
}

if (!(Test-Path $MySqlDumpPath))
{
    Write-Log "The specified path '$MySqlDumpPath' to mysqldump.exe doesn't exist." -Level Error
}

if (!(Test-Path $MySqlDumpConfigPath))
{
    Write-Log "mysqldump.cnf doesn't exist at '$MySqlDumpConfigPath'." -Level Error
}

if (!(Test-Path $MySqlDataDllPath))
{
    Write-Log "MySql.Data.dll doesn't exist at '$MySqlDataDllPath'." -Level Error
}

if (!(Test-Path $ProtobufDllPath))
{
    Write-Log "Google.Protobuf.dll doesn't exist at '$ProtobufDllPath'." -Level Error
}

Add-Type -Assembly 'System.IO.Compression'
Add-Type -Assembly 'System.IO.Compression.FileSystem'
Add-Type -Path $ProtobufDllPath
Add-Type -Path $MySqlDataDllPath

#
# Main
#
$Databases = Get-Databases

foreach ($DatabaseName in $Databases)
{
    Write-Log "Backing up $DatabaseName"

    $BackupFileName = Get-BackupFileName -databaseName $DatabaseName
    
    & "$MySqlDumpPath" --defaults-file="$MySqlDumpConfigPath" --databases $DatabaseName --result-file="$BackupFileName" --routines --triggers --events

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
