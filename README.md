# x_radar — iOS

App iOS native de x_radar : SwiftUI, iOS 26, Liquid Glass. Même backend Node/Express, même
contrat API et mêmes fonctionnalités que l'app Android (dépôt `x_radar`).

**État : étape 12/13 — menu** : logique métier (`XRadarCore`), client API et stockage local
(`XRadarData`), GPS, voix, Keychain, design system Liquid Glass, localisation et onboarding, carte
MapLibre 6.31 (style Plans jour / nuit repris d'Android), écran de conduite porté du
`DriveViewModel` Android : vitesse et limitation (route, radar, sondage du backend), alertes
radars et signalements empilées (votes, balayage), annonces vocales, guidage pas à pas et
recalcul, dock « Options », signaler, nouvelle limitation, conducteurs en direct, trajets
enregistrés. Recherche plein écran : adresses (Base Adresse Nationale), services autour avec
horaires et prix officiels des carburants, maison, travail, trajets favoris, récents, départ
simulé. Menu plein écran : identité et note de confiance, Mon compte (photo, statut, vérification
de l'email), Statistiques, Réglages (thème, fond de carte, position partagée, crédits de la
carte), Parrainage et Diagnostic pour les admins. Reste l'étape 13 : tests UI et checklist iPhone.

Mini-player musique : iOS ne laisse lire et piloter que le lecteur **Musique** d'Apple
(`MPMusicPlayerController`), pas Spotify ni Deezer comme sur Android.

Icônes : SF Symbols pour le générique ; celles propres à XRadar (signalisation, radars,
signalements, catégories de lieux) sont reprises de l'app Android dans `Assets.xcassets`.

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
│  └─ Sources/XRadarData/    client API, stockage local (compte, préférences, lieux, trajets)
├─ XRadar/                   cible app
│  ├─ App/                   lancement, services partagés (AppServices), configuration
│  ├─ Platform/              Core Location, voix, Keychain, lecteur Musique (photos à venir)
│  ├─ Features/              Onboarding, Drive, Search, Menu, Profile, Stats,
│  │                         Settings, Referral                                      (à venir)
│  ├─ DesignSystem/          couleurs, typographie, icônes, composants Liquid Glass, galerie
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
- Aucun changement du contrat backend : l'app envoie `platform: "ios"` et un `deviceId` UUID
  gardé dans le Keychain (il survit à une réinstallation). Jeton de session dans le Keychain,
  le reste en JSON dans UserDefaults.
- Pas de secours DNS-over-HTTPS (contrairement à Android) tant qu'aucun souci n'apparaît.

## Configuration

| Clé Info.plist   | Source xcconfig       | Rôle                         |
|------------------|-----------------------|------------------------------|
| `XRBackendURL`   | `XR_BACKEND_HOST`     | URL du backend (HTTPS)       |
| `XRStadiaAPIKey` | `XR_STADIA_API_KEY`   | tuiles et polices de carte   |

## Confidentialité

- Localisation « Pendant l'utilisation » seulement (jamais « Toujours »). Le suivi démarre avec
  l'app et continue écran verrouillé (pastille bleue), comme le service Android ; il s'arrête
  quand l'app est fermée depuis le sélecteur d'apps.
- Modes arrière-plan `location` (GPS) et `audio` (voix de guidage et d'alertes).
- Accès à **Musique** demandé seulement à la première ouverture du mini-player.
- `PrivacyInfo.xcprivacy` : position précise, e-mail, identifiant de compte, identifiant appareil,
  photo de profil, signalements, statistiques de conduite. Tout lié au compte, usage
  « fonctionnalité de l'app », aucun tracking.
