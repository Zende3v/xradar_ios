# x_radar — iOS

App iOS native de x_radar : SwiftUI, iOS 26, Liquid Glass. Même backend Node/Express, même
contrat API et mêmes fonctionnalités que l'app Android (dépôt `x_radar`).

**État : étapes 1 à 13 livrées** : logique métier (`XRadarCore`), client API et stockage local
(`XRadarData`), GPS, voix, Keychain, design system Liquid Glass, localisation et onboarding, carte
**MapKit** (Plans d'Apple, jour / nuit, sans boussole), écran de conduite porté du
`DriveViewModel` Android : vitesse et limitation (route, radar, sondage du backend), alertes
radars et signalements empilées (votes, balayage), annonces vocales, guidage pas à pas et
recalcul, dock « Options », signaler, nouvelle limitation, présence (compteur backend, sans position), trajets
enregistrés. Recherche plein écran, posée sur le HUD en Liquid Glass (la carte et le HUD se voient au
travers, clair ou sombre selon le thème) : adresses (Base Adresse Nationale), services autour avec
horaires et prix officiels des carburants, maison, travail, trajets favoris, récents, départ
simulé ; carburant : prix du carburant choisi ou « Proche uniquement » (stations ouvertes les plus
proches, sans prix) ; le clavier attend un tap dans le champ. Menu plein écran : identité et note
de confiance, Mon compte (photo, « Changer de pseudo » pour un client actif : vérifié pendant la saisie, 1 fois par semaine, statut, vérification de l'email, suppression définitive du compte
via `DELETE /api/accounts/me`), Statistiques (détail de chaque trajet : temps réel contre
estimation, km, vitesse moyenne et max, arrêts de 10 s ou plus, alertes rencontrées par type ;
temps dans les bouchons à venir), Réglages (« Thème général » Auto / Jour / Nuit
posé sur la fenêtre : l'app, la carte et le HUD ensemble, Auto selon le soleil à la position ;
« Dépassement limitation » Vocal / Bip / Aucun ; « Volume Guidage » et « Volume alertes » indépendants : `AVSpeechUtterance.volume` des consignes / des annonces d'alerte, `AVAudioPlayer.volume` des sons), Confidentialité (« Suggestions de trajets » = les Récents de la recherche, effacés quand on coupe ; « Aide au trafic partagé » = les sondes de ralentissement et la question « Ralentissement du trafic ? », sondes récentes retirées quand on coupe ; « Statistiques de conduite » = trajets et temps de conduite envoyés au compte ; « Présence anonyme » ; lien vers la politique), Signaler un bug (catégorie, ce qui s'est passé, reproduction facultative ; le compte et les détails de l'app partent seuls, `/api/bugs`), À propos (dont la politique de confidentialité), Rapports de bugs (admins : récents, par statut Nouveau / En cours / Résolu), Parrainage et Diagnostic
pour les admins. Icônes du Menu et badge de statut en glow blanc sur tuile sombre. Crédits Plans : une ligne minuscule en bas de la carte (les vues MapKit sont masquées par nom et
remplacées par la nôtre), et Menu > À propos. `PrivacyInfo.xcprivacy` à jour.

Abonnement (Menu ▸ Abonnement) : statut, puis pour un abonné l'échéance, sinon les limites du jour
et les offres (12,99 €/mois, 143,88 €/an soit -7,7 %), sans paiement pour l'instant. Compte bloqué
(essai ou abonnement terminé) : carte seule, offres à chaque retour dans l'app et à chaque action
bloquée. Invité : 5 signalements et 7 trajets par jour (refus `403`/`429` du backend lus en
`AccessDenial`), pas de photo de profil, pas de raccourci musique.

Réseau : une requête échouée garde les données affichées (signalements, conducteurs, panneaux du
trajet, limitation) et redemande ; seul un 401/403 sur `/me` fait perdre la session. Vitesse :
`SpeedFilter` (0 à l'arrêt, pics bornés, lissage léger). Guidage : une manœuvre n'est passée que
12 m après son point ; le côté d'un vrai virage est vérifié sur la géométrie. Voix : la meilleure
voix féminine française installée.

Options du dock : un interrupteur pour Radar fixe et pour chaque catégorie de signalement
(`ReportType.alertOptions` ; les feux rouges suivent Caméra, les bouchons restent sur la carte sans
alerte) ; itinéraire : éviter péages, autoroutes, et « Éviter les bouchons » (désactivé par défaut) :
jamais un détour pour un bouchon seul. En trajet, `/api/traffic/route` (toutes les 2 min, avec la
progression du conducteur) renvoie TomTom plus les bouchons des conducteurs (signalements confirmés,
sondes) et dit s'il faut chercher (`check`) ; `/api/route/faster` compare alors le reste du trajet à
des détours locaux ORS chronométrés par TomTom ; la bascule n'a lieu que pour un gain ≥ 3 min et ≥ 5 %,
ou pour contourner une route fermée, annoncée à la voix (jusqu'au bout) et par un bandeau
« Itinéraire plus rapide · N min gagnées » / « Route fermée devant ». Une vérification toutes les
5 min au plus (choisir à nouveau la même destination ne remet rien à zéro) ; rien pendant 5 min après
une bascule, gain doublé jusqu'à 15 min. « Aide au trafic partagé » (Confidentialité, actif
par défaut) : `SlowdownDetector` repère, sur les positions déjà reçues, 90 s sous la moitié d'une
limitation d'au moins 70 km/h (limite de la route, pas d'un radar ; toujours lent les 20 dernières
secondes ; au moins 150 m parcourus ; GPS précis ; ni début ni fin de trajet), puis 5 min de pause ;
la sonde part anonymement (`/api/traffic/probe`) et, si aucun bouchon n'est connu là (backend, trafic
du trajet, signalement à 1 km), l'app demande « Ralentissement du trafic ? » 10 s : Oui = signalement
Bouchon hors quota invité, Non = sonde retirée et plus de question à 3 km pendant 15 min. La carte des alertes reste en place, repliée jusqu'à « Accident » (flèche pour la
suite) ; ses lignes défilent dedans, en fondu au bord. La carte et tout le HUD posé dessus suivent le thème de
la fenêtre (`AppTheme.isDark`). Hors trajet, la carte montre les signalements à 22 km (comme les radars fixes) ;
en trajet, le couloir de la route. Trafic TomTom sur le trajet suivi (`/api/traffic/route`, la clé reste
sur le serveur) : la ligne de la route prend la couleur des portions ralenties (ambre, orange, rouge,
rouge sombre si fermé), mise à jour toutes les 2 min sur la même ligne, sans clignoter. Bouton
Signaler : verre neutre, triangle gris.

Sons d'alerte (`Resources/Sounds`, synthétisés), façon détecteur de radar et Radarbot : chirps
à l'apparition d'un radar, d'une caméra, d'une zone de contrôle ou d'une voiture radar, carillon
pour un danger, puis bips de plus en plus rapprochés à l'approche (700 → 60 m, à partir de
10 km/h, jamais pendant la voix) et rafale « laser » à 60 m. Dépassement de la limitation (+5 km/h, rappel par minute) : voix,
ou « bi-bip » montant plus grave que les bips d'approche. Bouton son : coupé / son / son +
vibration. Musique baissée pendant la voix et les sons (session audio partagée).

Mini-player musique : iOS ne laisse lire et piloter que le lecteur **Musique** d'Apple
(`MPMusicPlayerController`), pas Spotify ni Deezer comme sur Android.

Icônes : SF Symbols pour le générique ; celles propres à XRadar (signalisation, radars,
signalements, catégories de lieux, flèches de manœuvre) sont reprises de l'app Android dans
`Assets.xcassets`.

## Build (Codemagic, sans Mac)

`codemagic.yaml`, builds lancés à la main :

| Workflow | Fait | Sortie |
|---|---|---|
| `ios-unsigned-ipa` | xcodegen, tests du package, archive Release non signée | `build/XRadar-unsigned.ipa` |
| `ios-tests` | xcodegen, tests package + unitaires + UI sur simulateur (`scripts/ci.sh`) | `build/TestResults.xcresult` |

Une seule fois dans Codemagic : ajouter ce dépôt. Aucune clé à configurer (la carte est MapKit).

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
│  ├─ Sources/XRadarCore/    modèles, géométrie, itinéraire, pertinence, guidage, alertes, soleil
│  └─ Sources/XRadarData/    client API, stockage local (compte, préférences, lieux, trajets)
├─ XRadar/                   cible app
│  ├─ App/                   lancement, services partagés (AppServices), configuration
│  ├─ Platform/              Core Location, voix, sons d'alerte, session audio, Keychain, Musique
│  ├─ Features/              Permission, Onboarding, Drive (carte MapKit), Search, Menu,
│  │                         Profile, Settings, Diagnostic
│  ├─ DesignSystem/          couleurs, typographie, icônes, composants Liquid Glass
│  └─ Resources/             Info.plist, PrivacyInfo.xcprivacy, assets, sons, textes
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
- DNS chiffré (DNS-over-HTTPS Cloudflare) pour toute l'app : certains réseaux ne trouvent pas
  l'adresse `ts.net` du backend. Android ne s'en sert qu'en secours après un échec ; iOS n'offre
  que le mode imposé (`NWParameters.PrivacyContext.default`).
- Carte : `MKMapView` (UIKit) piloté par une boucle 60 i/s pour la flèche et la caméra. Dans un
  fichier qui importe MapKit et SwiftUI, écrire `XRadarData.MapStyle` (MapKit a aussi un
  `MapStyle`).

## Configuration

| Clé Info.plist   | Source xcconfig       | Rôle                         |
|------------------|-----------------------|------------------------------|
| `XRBackendURL`   | `XR_BACKEND_HOST`     | URL du backend (HTTPS)       |

## Confidentialité

- Localisation « Pendant l'utilisation » seulement (jamais « Toujours »). Le suivi démarre avec
  l'app et continue écran verrouillé (pastille bleue), comme le service Android ; il s'arrête
  quand l'app est fermée depuis le sélecteur d'apps.
- Modes arrière-plan `location` (GPS) et `audio` (voix de guidage, sons d'alerte).
- Accès à **Musique** demandé seulement à la première ouverture du mini-player.
- `PrivacyInfo.xcprivacy` : position précise, e-mail, identifiant de compte, identifiant appareil,
  photo de profil, signalements, statistiques de conduite. Tout lié au compte, usage
  « fonctionnalité de l'app », aucun tracking.
