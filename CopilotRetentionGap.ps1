<#
.SYNOPSIS
    Repère les politiques de rétention Teams « héritées » qui ont pu couvrir Microsoft Copilot jusqu'ici (MC1481313).

.DESCRIPTION
    Outil en LECTURE SEULE : il n'appelle que des cmdlets Get-* et ne modifie aucune politique.

    Contexte : selon l'avis MC1481313 du Centre de messages, à partir de la fin d'octobre 2026, les anciennes
    politiques de rétention Teams cesseront de s'appliquer aux interactions avec Copilot. Seules les politiques
    configurées explicitement pour Copilot (emplacement « Microsoft Copilot experiences ») continueront de le couvrir.

    L'outil se connecte à Security & Compliance PowerShell (Connect-IPPSSession) puis lit :
      1. Get-RetentionCompliancePolicy -TeamsPolicyOnly : les politiques propres à Teams.
      2. Get-AppRetentionCompliancePolicy : les politiques créées avec les applications (Teams, Viva Engage,
         Copilot et autres applications d'IA).
      3. Les règles de chaque politique retenue (durée et action) avec Get-RetentionComplianceRule et
         Get-AppRetentionComplianceRule.

    Classement de chaque politique :
      * COUVERT : un emplacement Copilot est configuré explicitement. Copilot reste couvert après le changement.
      * HERITE A REVOIR : politique Teams activée sans emplacement Copilot. Elle a peut-être couvert Copilot
        jusqu'ici et ne le fera plus.

    Verdict global : TROU si aucune politique active ne couvre Copilot explicitement.

    Limite : la documentation Microsoft Learn ne liste pas les propriétés de sortie des emplacements. L'outil
    lit donc de façon défensive les propriétés TeamsChatLocation, TeamsChannelLocation, Applications et toutes
    celles dont le nom se termine par « Location ». Confirmez toujours le résultat dans Microsoft Purview.

.PARAMETER OutputFolder
    Dossier où écrire le CSV et le rapport HTML. Par défaut : le dossier courant.

.PARAMETER UserPrincipalName
    Compte utilisé pour Connect-IPPSSession (facultatif).

.PARAMETER SkipConnect
    N'ouvre pas de connexion (utile si Connect-IPPSSession est déjà fait).

.EXAMPLE
    .\CopilotRetentionGap.ps1 -OutputFolder .\rapports

.NOTES
    Prérequis : module ExchangeOnlineManagement 3.2.0 ou plus ; un rôle Purview en lecture sur la rétention
    (par exemple Lecteur de rétention ou Gestionnaire de rétention).
    Projet : https://github.com/CharlesTrivium365/CopilotRetentionGap
#>
[CmdletBinding()]
param(
    [ValidateScript({ Test-Path -Path $_ -PathType Container })]
    [string]$OutputFolder = (Get-Location).Path,

    [string]$UserPrincipalName,

    [switch]$SkipConnect
)

#Requires -Modules ExchangeOnlineManagement

function ConvertTo-HtmlText {
    param([string]$Text)
    [System.Net.WebUtility]::HtmlEncode($Text)
}

function Get-LocationSummary {
    # Retourne les emplacements non vides d'une politique sous forme « Propriété=valeurs ».
    param([object]$Policy)
    $parts = foreach ($property in $Policy.PSObject.Properties) {
        $isLocation = $property.Name -in 'TeamsChatLocation', 'TeamsChannelLocation', 'Applications' -or $property.Name -like '*Location'
        $values = @($property.Value | Where-Object { $_ -and "$_".Trim() })
        if ($isLocation -and $values.Count -gt 0) { '{0}={1}' -f $property.Name, ($values -join '|') }
    }
    @($parts)
}

function Get-RuleSummary {
    param([string]$PolicyName, [string]$Kind)
    $rules = if ($Kind -eq 'App') { Get-AppRetentionComplianceRule -Policy $PolicyName -ErrorAction SilentlyContinue }
             else { Get-RetentionComplianceRule -Policy $PolicyName -ErrorAction SilentlyContinue }
    $lines = foreach ($rule in @($rules)) {
        $details = foreach ($name in 'RetentionDuration', 'RetentionComplianceAction', 'ExpirationDateOption') {
            if ($rule.PSObject.Properties[$name] -and $rule.$name) { '{0}={1}' -f $name, $rule.$name }
        }
        if ($details) { $details -join ', ' } else { $rule.Name }
    }
    ($lines -join ' ; ')
}

function ConvertTo-GapRow {
    param([object]$Policy, [string]$Kind)
    $locations = Get-LocationSummary -Policy $Policy
    $text = $locations -join ' '
    $isCopilot = $text -match 'Copilot'
    $isTeams = $text -match 'Teams'
    if (-not ($isCopilot -or $isTeams)) { return }

    $enabled = [bool]$Policy.Enabled
    $status = if ($isCopilot -and $enabled) { 'COUVERT' }
              elseif ($isCopilot) { 'COPILOT MAIS DESACTIVEE' }
              elseif ($enabled) { 'HERITE A REVOIR' }
              else { 'TEAMS DESACTIVEE' }

    [pscustomobject]@{
        Statut       = $status
        Politique    = $Policy.Name
        Cmdlet       = if ($Kind -eq 'App') { 'Get-AppRetentionCompliancePolicy' } else { 'Get-RetentionCompliancePolicy' }
        Activee      = $enabled
        Mode         = $Policy.Mode
        Emplacements = ($locations -join ' ; ')
        Regles       = Get-RuleSummary -PolicyName $Policy.Name -Kind $Kind
    }
}

if (-not $SkipConnect) {
    if ($UserPrincipalName) { Connect-IPPSSession -UserPrincipalName $UserPrincipalName -ShowBanner:$false }
    else { Connect-IPPSSession -ShowBanner:$false }
}

# 1. Politiques propres à Teams (cmdlets des anciens emplacements)
Write-Verbose 'Lecture des politiques propres à Teams'
$teamsPolicies = @(Get-RetentionCompliancePolicy -TeamsPolicyOnly -DistributionDetail)

# 2. Politiques créées avec les applications (Teams, Viva Engage, Copilot, applications d'IA)
Write-Verbose 'Lecture des politiques par application'
$appPolicies = @(Get-AppRetentionCompliancePolicy -DistributionDetail)

$results = @()
foreach ($policy in $teamsPolicies) { $results += ConvertTo-GapRow -Policy $policy -Kind 'Legacy' }
foreach ($policy in $appPolicies) { $results += ConvertTo-GapRow -Policy $policy -Kind 'App' }
$results = @($results | Where-Object { $_ } | Sort-Object Statut, Politique)

# 3. Verdict
$covered = @($results | Where-Object Statut -eq 'COUVERT')
$legacy = @($results | Where-Object Statut -eq 'HERITE A REVOIR')
$verdict = if ($covered.Count -gt 0) { 'OK' } elseif ($legacy.Count -gt 0) { 'TROU' } else { 'AUCUNE POLITIQUE' }
$message = switch ($verdict) {
    'OK' { "$($covered.Count) politique(s) active(s) couvre(nt) Copilot explicitement. $($legacy.Count) politique(s) Teams héritée(s) à revoir." }
    'TROU' { "Aucune politique active ne couvre Copilot explicitement. $($legacy.Count) politique(s) Teams ont peut-être couvert Copilot jusqu'ici : à partir de la fin d'octobre 2026 (MC1481313), elles ne le feront plus." }
    default { 'Aucune politique de rétention Teams ou Copilot repérée : Copilot n''est pas couvert et ne le sera pas non plus après le changement.' }
}
Write-Warning $message

# 4. Sorties
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$csvPath = Join-Path $OutputFolder "CopilotRetentionGap-$stamp.csv"
$htmlPath = Join-Path $OutputFolder "CopilotRetentionGap-$stamp.html"
$results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

$colors = @{ 'COUVERT' = '#2e7d32'; 'HERITE A REVOIR' = '#c62828'; 'COPILOT MAIS DESACTIVEE' = '#ef6c00'; 'TEAMS DESACTIVEE' = '#757575' }
$tableRows = foreach ($r in $results) {
    "<tr><td style='color:$($colors[$r.Statut]);font-weight:600'>$($r.Statut)</td><td>$(ConvertTo-HtmlText $r.Politique)</td><td>$($r.Activee)</td><td>$(ConvertTo-HtmlText $r.Mode)</td><td><code>$(ConvertTo-HtmlText $r.Emplacements)</code></td><td>$(ConvertTo-HtmlText $r.Regles)</td></tr>"
}

@"
<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><title>Rétention : couverture de Copilot</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:2rem;color:#1a1a2e}table{border-collapse:collapse;width:100%}th,td{border:1px solid #ddd;padding:6px 10px;text-align:left;font-size:14px;vertical-align:top}th{background:#1a1446;color:#fff}.diag{background:#fff4e5;border-left:4px solid #ef6c00;padding:10px 14px}</style>
</head><body>
<h1>Rétention : couverture de Copilot après MC1481313</h1>
<p>Généré le $(Get-Date -Format 'yyyy-MM-dd HH:mm')</p>
<p class="diag"><strong>$verdict</strong> : $(ConvertTo-HtmlText $message)</p>
<table><tr><th>Statut</th><th>Politique</th><th>Activée</th><th>Mode</th><th>Emplacements lus</th><th>Règles</th></tr>
$($tableRows -join "`n")
</table>
<p>Confirmez chaque politique dans Microsoft Purview : les propriétés d'emplacement sont lues de façon défensive.</p>
</body></html>
"@ | Set-Content -Path $htmlPath -Encoding UTF8

$results | Format-Table -AutoSize
Write-Information "CSV : $csvPath" -InformationAction Continue
Write-Information "Rapport HTML : $htmlPath" -InformationAction Continue
