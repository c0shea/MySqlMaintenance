#
# This script executes the mainteance scripts sequentially when running
# through Task Scheduler since specifying each script as a separate
# action causes them all to start at the same time.
#

& "$PSScriptRoot\MySql.Backup.ps1"
& "$PSScriptRoot\MySql.Check.ps1"
& "$PSScriptRoot\MySql.Optimize.ps1"
& "$PSScriptRoot\MySql.Analyze.ps1"
