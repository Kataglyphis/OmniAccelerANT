# Read the installed-file sizes from a trusted MSI without installing it.
param([Parameter(Mandatory)][string]$MsiPath)
$ErrorActionPreference = 'Stop'
$installer = $null; $database = $null; $view = $null; $record = $null
try {
    $installer = New-Object -ComObject WindowsInstaller.Installer
    $database = $installer.OpenDatabase((Resolve-Path -LiteralPath $MsiPath).Path, 0)
    $view = $database.OpenView('SELECT `FileSize` FROM `File`')
    [void]$view.Execute()
    [long]$total = 0
    while ($null -ne ($record = $view.Fetch())) {
        $size = $record.IntegerData(1)
        if ($size -lt 0) { throw 'MSI has a negative file size' }
        $total += $size
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($record)
        $record = $null
    }
    if ($total -le 0 -or $total -gt 4GB) { throw 'MSI expanded size is outside the allowed range' }
    Write-Output $total
} finally {
    if ($null -ne $record) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($record) }
    if ($null -ne $view) { [void]$view.Close(); [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($view) }
    if ($null -ne $database) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($database) }
    if ($null -ne $installer) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($installer) }
}
