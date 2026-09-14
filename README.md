# x_radar — iOS

App iOS native de x_radar : SwiftUI, iOS 26, Liquid Glass. Même backend Node/Express, même
contrat API et mêmes fonctionnalités que l'app Android (dépôt `x_radar`).

**État : étape 1/13 — squelette** (projet, configuration, confidentialité, build Codemagic).

## Build (Codemagic, sans Mac)

`codemagic.yaml`, builds lancés à la main :

| Workflow | Fait | Sortie |
|---|---|---|
| `ios-unsigned-ipa` | xcodegen, tests du package, archive Release non signée | `build/XRadar-unsigned.ipa` |
| `ios-tests` | xcodegen, tests package + unitaires + UI sur simulateur (`scripts/ci.sh`) | `build/TestResults.xcresult` |

Une seule fois dans Codemagic : ajouter ce dépôt, créer le groupe de variables **`xradar`** avec
`STADIA_API_KEY` (sécurisée, même clé Stadia que l'Android).

**Installer sur iPhone** : télécharger l'IPA de l'artefact, la signer et l'installer avec
Sideloadly (ou AltStore) et un Apple ID gratuit. Signature valable 7 jours : réinstaller ensuite.
Compte gratuit : pas de notifications push ni de capacités payantes.

## Sur un Mac (optionnel)

```bash
brew install xcodegen
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # puis remplir
xcodegen generate
open XRadar.xcodeproj
bash scripts/ci.sh        # package + unitaires + UI  (bash scripts/ci.sh unit : sans UI)
```

- `project.yml` est la seule source du projet. `XRadar.xcodeproj` est généré et ignoré par git.
- Tests rapides du package seul : `swift test --package-path Packages/XRadarKit`.

## Architecture

```
xradar_ios/
├─ codemagic.yaml            builds Codemagic
├─ project.yml               spec XcodeGen
├─ Config/                   xcconfig : Base, Debug, Release, Secrets (non versionné)
├─ Packages/XRadarKit/       package Swift pur (Foundation seulement)
│  ├─ Sources/XRadarCore/    modèles, géométrie, itinéraire, pertinence, guidage, soleil
│  └─ Sources/XRadarData/    client API unique, DTO, repositories, fixtures
├─ XRadar/                   cible app
│  ├─ App/                   lancement, dépendances, configuration
│  ├─ Platform/              Core Location, voix, Keychain, photos, stockage local   (à venir)
│  ├─ Features/              Onboarding, Drive, Search, Menu, Profile, Stats,
│  │                         Settings, Referral                                      (à venir)
│  ├─ DesignSystem/          tokens, typographie, icônes, composants Liquid Glass    (à venir)
│  └─ Resources/             Info.plist, PrivacyInfo.xcprivacy, assets, textes
├─ XRadarTests/              tests unitaires de la cible app (Swift Testing)
├─ XRadarUITests/            tests UI (XCTest)
└─ scripts/ci.sh             xcodegen + xcodebuild test
```

Règles :

- Parité avec l'app Android : mêmes écrans, parcours, règles métier et appels API. Toute
  différence imposée par iOS est validée avant d'être codée.
- `XRadarCore` et `XRadarData` n'importent jamais UIKit, SwiftUI ni CoreLocation.
- Cible app : isolation `MainActor` par défaut (réglage Xcode 26). Le travail de fond sort
  explicitement du main actor.
- Les coordonnées d'itinéraire du backend sont `[longitude, latitude]`. Ne jamais les inverser.
- Aucun changement du contrat backend : l'app envoie `platform: "ios"` et
  `identifierForVendor` comme `deviceId`.

## Configuration

| Clé Info.plist   | Source xcconfig       | Rôle                         |
|------------------|-----------------------|------------------------------|
| `XRBackendURL`   | `XR_BACKEND_HOST`     | URL du backend (HTTPS)       |
| `XRStadiaAPIKey` | `XR_STADIA_API_KEY`   | styles de carte Stadia       |

## Confidentialité

- Localisation « Quand l'app est active » demandée au démarrage. « Toujours » demandée
  seulement quand une conduite démarre.
- Modes arrière-plan `location` et `audio` : utilisés seulement pendant une conduite active
  (GPS, partage live, voix). Tout s'arrête à la fin du trajet.
- `PrivacyInfo.xcprivacy` : position précise, e-mail, identifiant de compte, identifiant appareil,
  photo de profil, signalements, statistiques de conduite. Tout lié au compte, usage
  « fonctionnalité de l'app », aucun tracking.
