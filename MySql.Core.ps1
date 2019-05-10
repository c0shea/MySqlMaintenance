# Begin Configuration
$MySqlBinPath        = "C:\Program Files\MySQL\MySQL Server 8.0\bin"
$LogFilePath         = "D:\Apps\Logs"
# End Configuration

$MySqlConfigPath     = [System.IO.Path]::Combine($PSScriptRoot, "mysql.cnf")
$ProtobufDllPath     = [System.IO.Path]::Combine($PSScriptRoot, "Google.Protobuf.dll")
$MySqlDataDllPath    = [System.IO.Path]::Combine($PSScriptRoot, "MySql.Data.dll")

Add-Type -Path $ProtobufDllPath
Add-Type -Path $MySqlDataDllPath

#
# Functions
#

# Get-IniFile from https://stackoverflow.com/a/43697842/4403297
function Get-IniFile 
{
    [CmdletBinding()]
    param
    (  
        [parameter(Mandatory = $true)] [string] $FilePath  
    )  

    $Anonymous = "NoSection"

    $Ini = @{}  
    switch -regex -file $FilePath
    {  
        "^\[(.+)\]$" # Section  
        {  
            $Section = $Matches[1]  
            $Ini[$Section] = @{}  
            $CommentCount = 0  
        }  

        "^(;.*)$" # Comment  
        {  
            if (!($Section))  
            {  
                $Section = $Anonymous  
                $Ini[$Section] = @{}  
            }  
            $Value = $Matches[1]  
            $CommentCount = $CommentCount + 1  
            $Name = "Comment" + $CommentCount  
            $Ini[$Section][$Name] = $Value  
        }   

        "(.+?)\s*=\s*(.*)" # Key  
        {  
            if (!($Section))  
            {  
                $Section = $Anonymous  
                $Ini[$Section] = @{}  
            }  
            $Name,$Value = $Matches[1..2]  
            $Ini[$Section][$Name] = $Value  
        }  
    }  

    return $Ini  
}

# Logs a message to the console and the log file specified by $LogFileName
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
        $IniFile = Get-IniFile "$MySqlConfigPath"

        $ConnectionStringBuilder = New-Object -TypeName MySql.Data.MySqlClient.MySqlConnectionStringBuilder
        $ConnectionStringBuilder.Server = "localhost"
        $ConnectionStringBuilder.UserID = $IniFile.databaseenumeration.user
        $ConnectionStringBuilder.Password = $IniFile.databaseenumeration.password

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


#
# Validate Parameters
#

if (!(Test-Path $MySqlBinPath))
{
    Write-Log "The specified path to the MySQL bin directory '$MySqlBinPath' doesn't exist." -Level Error
}

if (!(Test-Path $MySqlConfigPath))
{
    Write-Log "mysql.cnf doesn't exist at '$MySqlConfigPath'." -Level Error
}

if (!(Test-Path $ProtobufDllPath))
{
    Write-Log "Google.Protobuf.dll doesn't exist at '$ProtobufDllPath'." -Level Error
}

if (!(Test-Path $MySqlDataDllPath))
{
    Write-Log "MySql.Data.dll doesn't exist at '$MySqlDataDllPath'." -Level Error
}
