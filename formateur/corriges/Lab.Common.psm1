#Requires -Version 5.1
Set-StrictMode -Version Latest
function Test-LabCsv {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path -PathType Leaf)) {throw 'CSV introuvable.'}
    $rows=@(Import-Csv $Path -Delimiter ';' -Encoding UTF8)
    if ($rows.Count -eq 0) {throw 'CSV vide.'}
    $expected=@('SamAccountName','GivenName','Surname','Department')
    $headers=@($rows[0].PSObject.Properties.Name)
    if (@(Compare-Object $expected $headers).Count -gt 0) {throw 'En-tetes CSV incorrects.'}
    $seen=@{};$errors=New-Object 'System.Collections.Generic.List[string]'
    for ($i=0;$i -lt $rows.Count;$i++) {
        $r=$rows[$i];$line=$i+2
        if ($r.SamAccountName -notmatch '^[a-z][a-z0-9.]{2,19}$') {$errors.Add("Ligne ${line}: identifiant invalide.")}
        if ($seen.ContainsKey($r.SamAccountName)) {$errors.Add("Ligne ${line}: doublon.")} else {$seen[$r.SamAccountName]=$true}
        if ([string]::IsNullOrWhiteSpace($r.GivenName) -or [string]::IsNullOrWhiteSpace($r.Surname)) {$errors.Add("Ligne ${line}: nom manquant.")}
        if ($r.Department -notin @('IT','RH','Direction')) {$errors.Add("Ligne ${line}: service inconnu.")}
    }
    if ($errors.Count -gt 0) {throw ($errors -join [Environment]::NewLine)}
    return $rows
}
Export-ModuleMember -Function Test-LabCsv
