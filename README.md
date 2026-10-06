# CopilotRetentionGap

Inventaire en lecture seule pour repérer les **interactions avec Microsoft Copilot qui ne seront plus couvertes par vos politiques de rétention**.

Selon l'avis **MC1481313** du Centre de messages (28 septembre 2026), certaines politiques de rétention Teams couvrent aujourd'hui aussi Copilot. À partir de la **fin d'octobre 2026**, ces politiques « héritées » seront traitées comme des politiques **Teams seulement**. Le déploiement mondial doit se terminer vers la **mi-novembre 2026**. Les messages de Copilot ne seront alors plus retenus ni supprimés par elles, sans message d'erreur.

CopilotRetentionGap répond à une seule question : **ma conformité repose-t-elle sur une politique Teams pour couvrir Copilot ?**

📝 L'article lié (en brouillon au moment d'écrire ces lignes) paraîtra sur [blog.trivium365.com](https://blog.trivium365.com) sous le titre « Rétention : vos anciennes politiques Teams cesseront de couvrir Copilot ».

## Ce que fait l'outil

1. Se connecte à Security & Compliance PowerShell avec `Connect-IPPSSession`.
2. Lit les politiques propres à Teams avec `Get-RetentionCompliancePolicy -TeamsPolicyOnly -DistributionDetail`.
3. Lit les politiques par application avec `Get-AppRetentionCompliancePolicy -DistributionDetail` (Teams, Viva Engage, Copilot et autres applications d'IA).
4. Lit les règles de chaque politique retenue avec `Get-RetentionComplianceRule` et `Get-AppRetentionComplianceRule` (durée et action).
5. Classe chaque politique et rend un verdict global.

| Statut | Signification |
|---|---|
| **COUVERT** | Un emplacement Copilot est configuré explicitement : la couverture reste en place |
| **HERITE A REVOIR** | Politique Teams activée sans emplacement Copilot : elle a peut-être couvert Copilot jusqu'ici |
| **COPILOT MAIS DESACTIVEE** | Emplacement Copilot présent mais politique désactivée |
| **TEAMS DESACTIVEE** | Politique Teams désactivée (aucun impact) |

| Verdict | Signification |
|---|---|
| **OK** | Au moins une politique active couvre Copilot explicitement |
| **TROU** | Aucune politique active ne couvre Copilot explicitement et des politiques Teams héritées existent |
| **AUCUNE POLITIQUE** | Aucune politique Teams ou Copilot : Copilot n'est pas couvert aujourd'hui non plus |

Il produit un tableau à l'écran, un fichier CSV et un rapport HTML.

**L'outil ne modifie rien.** Seules des cmdlets `Get-*` sont appelées.

## Prérequis

- PowerShell 7 ou Windows PowerShell 5.1
- Module `ExchangeOnlineManagement` (version 3.2.0 ou plus)
- Un rôle Microsoft Purview qui permet de lire les politiques de rétention

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser
```

## Utilisation

```powershell
.\CopilotRetentionGap.ps1 -OutputFolder .\rapports
```

Déjà connecté avec `Connect-IPPSSession` ? Ajoutez `-SkipConnect`. Pour choisir le compte : `-UserPrincipalName admin@contoso.com`.

## Exemple de résultat

Exemple fictif :

```
Statut           Politique       Cmdlet                           Activee Emplacements
------           ---------       ------                           ------- ------------
COUVERT          Copilot 3 ans   Get-AppRetentionCompliancePolicy True    Applications=User:M365Copilot|CopilotStudio
HERITE A REVOIR  Teams 1 an      Get-RetentionCompliancePolicy    True    TeamsChatLocation=All
TEAMS DESACTIVEE Teams ancienne  Get-RetentionCompliancePolicy    False   TeamsChatLocation=All
```

## Et ensuite ?

Pour couvrir Copilot, créez une politique explicite dans Microsoft Purview (emplacement « Microsoft Copilot experiences ») ou avec `New-AppRetentionCompliancePolicy -Applications "User:M365Copilot,CopilotForSecurity,CopilotinFabricPowerBI,CopilotStudio,CopilotinBusinessApplicationplatformsSales,SQLCopilot"`. Ce paramètre est en préversion et exige toutes les valeurs ensemble. Créez ensuite une règle avec `New-AppRetentionComplianceRule`. Cet outil ne le fait pas : la durée de rétention est une décision de conformité qui revient à votre organisation.

## Limites connues

- La documentation Microsoft Learn ne liste pas les propriétés de sortie des emplacements. L'outil lit donc de façon défensive `TeamsChatLocation`, `TeamsChannelLocation`, `Applications` et toute propriété dont le nom se termine par `Location`. Une propriété absente ou renommée par Microsoft peut fausser le classement : confirmez chaque politique dans Microsoft Purview.
- Une politique Teams est classée « héritée » dès qu'elle est activée et sans emplacement Copilot. L'outil ne peut pas savoir si elle couvrait réellement Copilot avant le changement.
- Les politiques Exchange ou SharePoint qui touchent les boîtes aux lettres des utilisateurs ne sont pas analysées.
- Les emplacements « Enterprise AI apps » et « Other AI apps » ne sont pas évalués : seuls les emplacements Copilot comptent pour le verdict.
- L'outil n'a pas été exécuté contre un vrai locataire. Il a été validé avec PSScriptAnalyzer (aucun avertissement) et avec des données fictives.
- Les dates viennent de l'avis MC1481313 : « fin octobre 2026 » et « mi-novembre 2026 » restent approximatives.

## Sources

- [MC1481313 : Legacy Teams retention policies that cover Copilot will be treated as Teams-only](https://mc.merill.net/message/MC1481313) (Centre de messages)
- [Learn about retention for Copilot & AI apps](https://learn.microsoft.com/en-us/purview/retention-policies-copilot) (Microsoft Learn)
- [Get-AppRetentionCompliancePolicy](https://learn.microsoft.com/en-us/powershell/module/exchange/get-appretentioncompliancepolicy) (Microsoft Learn)
- [Get-RetentionCompliancePolicy](https://learn.microsoft.com/en-us/powershell/module/exchange/get-retentioncompliancepolicy) (Microsoft Learn)
- [Get-AppRetentionComplianceRule](https://learn.microsoft.com/en-us/powershell/module/exchange/get-appretentioncompliancerule) (Microsoft Learn)
- [New-AppRetentionCompliancePolicy](https://learn.microsoft.com/en-us/powershell/module/exchange/new-appretentioncompliancepolicy) (Microsoft Learn)
- [Connect-IPPSSession](https://learn.microsoft.com/en-us/powershell/module/exchange/connect-ippssession) (Microsoft Learn)

## Licence

MIT. Publié par Charles Jenkins, [blog.trivium365.com](https://blog.trivium365.com).
