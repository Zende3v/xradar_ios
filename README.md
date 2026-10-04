# EONA — iOS

App iOS native de EONA : SwiftUI, iOS 26, Liquid Glass. Même backend Node/Express, même
contrat API et mêmes fonctionnalités que l'app Android (dépôt `EONA`).

Bilan session Claude cloud (02/10 → 05/10, builds 24 à 30) : `BILAN-SESSION-CLAUDE-20261005.md` à la racine du dépôt `x_radar`.

**État : étapes 1 à 13 livrées** : logique métier (`EonaCore`), client API et stockage local
(`EonaData`), GPS, voix, Keychain, design system Liquid Glass, localisation et onboarding, carte
**MapKit** (Plans d'Apple, jour / nuit, sans boussole), écran de conduite porté du
`DriveViewModel` Android : vitesse et limitation (route, radar, sondage du backend), alertes
radars et signalements empilées (votes, balayage), annonces vocales, guidage pas à pas et
recalcul, dock « Options », signaler, nouvelle limitation, présence (compteur backend, sans position), trajets
enregistrés. Choix d'itinéraire (02/10) à chaque destination choisie : panneau Liquid Glass au bas
de la carte, Rapide (bouchons évités en route) et Éco (plus court en distance), temps HERE avec trafic,
distance, arrivée ; Rapide (build 29) : temps gagné face à Éco, coût carburant estimé, routes traversées (`roads` du backend : autoroute, péage, ferry ; rien si inconnu) ; Éco : temps en plus, km et euros économisés ; coût = consommation des Réglages (6,5 L/100 km au départ ; curseur 1,0 à 30,0, cran 0,1, build 30) × prix médian du carburant préféré dans les stations proches du départ (`/api/places`, relu toutes les 30 min, sans HERE) ; prix inconnu : aucun euro ; Perso grisé, bientôt ; routes en vue d'ensemble, retenue en accent ; « Démarrer »
lance le trajet, ETA du départ = temps HERE du choix (aucun appel en plus) ; Rapide = moins de temps avec trafic : Éco chronométré plus vite par HERE prend aussi place de Rapide (04/10) ; Éco suivi en recalcul, détour Éco seulement autour d'une route fermée. Multi-arrêts (04/10) :
10 étapes au plus, envoyées au backend (`via`), traversées dans l'ordre. Ajout : « + » en bout de
résultat de recherche quand une destination est choisie, « + Étape » sur le choix d'itinéraire et
sous le guidage. Feuille « Étapes » : glisser-déposer, retrait, arrivée fixe en dernier. Étapes
numérotées sur la carte ; étape atteinte (45 m, plus son retrait de la route, 150 m au plus) :
retirée, dite, montrée 4 s. Route recalculée 0,7 s après le dernier changement. Stationnement
(build 28) : bouton P hors trajet, feuille « Stationnement » ; plusieurs repères (10 au plus, le
plus ancien part), « Garer ici » à la position ; fiche : âge, distance, voiture / moto / vélo /
trottinette, « Y aller à pied » (Plans), « Retirer le repère » ; repère touché sur la carte : sa
fiche. Repères gardés sur le téléphone seulement (repère unique des builds 26-27 repris). Permis probatoire (04/10, Réglages > Conduite) : limites
affichées et seuils d'alerte 130→110, 110→100, 90→80 ; signalements et sondes gardent la limite
officielle. Réglages > Carburant (build 29) : carburant préféré (Gazole par défaut, filtre des stations proches) et consommation. Cartes véhicule : « Esthétique » sauf Scooter 50 et Sans permis. Pseudo : nom touché dans Mon compte & Statistiques (offre EONA + sinon). Scooter 50 et Sans permis (build 28, Réglages > Véhicule) : itinéraire `vehicle=moped`
(45 km/h, sans autoroute ni voie rapide), limites et alertes plafonnées à 45 (après le probatoire),
temps HERE ignoré pour l'ETA, détour trafic seulement autour d'une route fermée. Protection pluie
(build 28, Réglages > Véhicule) : écran verrouillé dès 15 km/h, levé sous 10 km/h ou GPS perdu ;
feuilles fermées, cadenas à la place des boutons de carte. Menu Signaler (04/10) : disques de verre teintés par famille, ni orange ni rouge
(acier contrôles, ambre dangers, orchidée accident / contresens, sauge travaux, lavande bouchon).
Recherche plein écran, posée sur le HUD en Liquid Glass (la carte et le HUD se voient au
travers, clair ou sombre selon le thème) : adresses (Base Adresse Nationale), services autour avec
horaires et prix officiels des carburants, maison, travail, trajets favoris, récents, départ
simulé ; carburant : prix du carburant choisi ou « Proche uniquement » (stations ouvertes les plus
proches, sans prix) ; le clavier attend un tap dans le champ. Menu plein écran (build 28) : identité,
boîte 1 (Réglages, EONA +, Mon compte & Statistiques, Confidentialité, À propos), boîte 2 carte
bordée « Un problème, une suggestion ? — Contactez-nous ! », boîte Admin (Parrainage, Rapports),
déconnexion. Mon compte & Statistiques, de haut en bas : profil (photo, nom au crayon, statut),
comptes liés (Google ; Apple « Bientôt »), statistiques, version et suppression. Détail : Mon compte (photo, « Changer de pseudo » pour un client actif : vérifié pendant la saisie, 1 fois par semaine, statut, vérification de l'email, suppression définitive du compte
via `DELETE /api/accounts/me`), Statistiques (détail de chaque trajet : temps réel contre
estimation, km, vitesse moyenne et max, arrêts de 10 s ou plus, alertes rencontrées par type ;
temps dans les bouchons à venir), Réglages (« Thème général » Auto / Jour / Nuit
posé sur la fenêtre : l'app, la carte et le HUD ensemble, Auto selon le soleil à la position ;
« Véhicule », curseur sur la carte (depuis 02/10, avant dans Mon compte) ;
« Dépassement limitation » Vocal / Bip / Aucun ; « Volume Guidage » et « Volume alertes » indépendants : `AVSpeechUtterance.volume` des consignes / des annonces d'alerte, `AVAudioPlayer.volume` des sons), Confidentialité (« Suggestions de trajets » = les Récents de la recherche, effacés quand on coupe ; « Aide au trafic partagé » = les sondes de ralentissement et la question « Ralentissement du trafic ? », sondes récentes retirées quand on coupe ; « Statistiques de conduite » = trajets et temps de conduite envoyés au compte ; « Présence et position », activée d'office au build 28 (une fois, puis le choix du conducteur reste) ; lien vers la politique), Contactez-nous (Problème ou Suggestion, catégorie `suggestion` côté backend ; problème : catégorie, ce qui s'est passé, reproduction facultative ; le compte et les détails de l'app partent seuls, `/api/bugs` ; catégorie Navigation : moteur, version de la carte et trajet en cours ou dernier depuis le lancement joints en `context`, tracé ≤ 600 points ; formulaire ouvert seulement à l'arrêt, sous 1,5 m/s, sinon « Disponible à l'arrêt »), À propos (dont la politique de confidentialité), Rapports (admins : bugs et suggestions, récents, par statut Nouveau / En cours / Résolu), Parrainage et Diagnostic
pour les admins. Icônes du Menu et badge de statut en glow blanc sur tuile sombre. Crédits Plans : une ligne minuscule en bas de la carte (les vues MapKit sont masquées par nom et
remplacées par la nôtre), et Menu > À propos. `PrivacyInfo.xcprivacy` à jour.

EONA + (Menu ▸ EONA +, ex-Abonnement) : statut, puis pour un abonné l'échéance, sinon les limites du jour
et les offres (12,99 €/mois, 143,88 €/an soit -7,7 %), sans paiement pour l'instant. Compte bloqué
(essai ou abonnement terminé) : carte seule, offres à chaque retour dans l'app et à chaque action
bloquée. Invité : 5 signalements et 7 trajets par jour (refus `403`/`429` du backend lus en
`AccessDenial`), pas de photo de profil, pas de raccourci musique.

Mesures ETA et itinéraires (plan Valhalla, phase 1, `TripMeasure`) : chaque trajet enregistré porte
en plus arrivé ou non, départ réel (route rejointe ; départ simulé : premier point), départ choisi à
la main, distance prévue, pauses et arrêts incertains (arrêt ≥ 5 min : bouchon connu = trafic, route
connue dégagée = pause, sinon incertain), ETA du dock à 0, 25, 50 et 75 % du trajet, recalculs,
bascules plus rapides, moteurs et version de carte (`engine`, `mapVersion` de `/api/route`), version
de l'app, `etaMode: proportional`, sources de trafic vues. Aucune coordonnée.

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

Sons d'alerte (`Resources/Sounds`, synthétisés), façon Radarbot. Carillon à l'apparition d'un
danger. Radars, caméras, zones de contrôle, voitures radar : popup à 300 m, aucun son avant
200 m. Premier bip pile à 200 m : distance extrapolée depuis heure du fix GPS, latence audio
comprise, session audio prête 1,5 s avant (`EnforcementBeeps`). Puis bips plus rapprochés (0,8 s,
0,45 s sous 150 m, dès 10 km/h ; voix retarde seulement bips intermédiaires), rafale « laser »
à 60 m. Popup radar fixe, radar mobile, zone de contrôle : panneau de limitation (VMA officielle,
sinon limitation du trajet ou `/api/signs/limit` au point). Écran jamais en veille app au premier
plan. Dépassement de la limitation (+5 km/h, rappel par minute) : voix,
ou « bi-bip » montant plus grave que les bips d'approche. Bouton son : coupé / son / son +
vibration. Musique baissée pendant la voix et les sons (session audio partagée).

Mini-player musique : iOS ne laisse lire et piloter que le lecteur **Musique** d'Apple
(`MPMusicPlayerController`), pas Spotify ni Deezer comme sur Android.

Icônes : SF Symbols pour le générique ; celles propres à EONA (signalisation, radars,
signalements, catégories de lieux, flèches de manœuvre) sont reprises de l'app Android dans
`Assets.xcassets`.

## Build (Codemagic, sans Mac)

`codemagic.yaml`, builds lancés à la main :

| Workflow | Fait | Sortie |
|---|---|---|
| `ios-unsigned-ipa` | xcodegen, tests du package, archive Release non signée | `build/EONA-unsigned.ipa` |
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
open EONA.xcodeproj
bash scripts/ci.sh        # package + unitaires + UI  (bash scripts/ci.sh unit : sans UI)
```

- `project.yml` est la seule source du projet. `EONA.xcodeproj` est généré et ignoré par git.
- Tests rapides du package seul : `swift test --package-path Packages/EonaKit`.

## Architecture

```
eona_ios/
├─ codemagic.yaml            builds Codemagic
├─ project.yml               spec XcodeGen
├─ Config/                   xcconfig : Base, Debug, Release, Secrets (non versionné)
├─ Packages/EonaKit/       package Swift pur (Foundation seulement)
│  ├─ Sources/EonaCore/    modèles, géométrie, itinéraire, pertinence, guidage, alertes, soleil
│  └─ Sources/EonaData/    client API, stockage local (compte, préférences, lieux, trajets)
├─ EONA/                   cible app
│  ├─ App/                   lancement, services partagés (AppServices), configuration
│  ├─ Platform/              Core Location, voix, sons d'alerte, session audio, Keychain, Musique
│  ├─ Features/              Permission, Onboarding, Drive (carte MapKit), Search, Menu,
│  │                         Profile, Settings, Diagnostic
│  ├─ DesignSystem/          couleurs, typographie, icônes, composants Liquid Glass
│  └─ Resources/             Info.plist, PrivacyInfo.xcprivacy, assets, sons, textes
├─ EONATests/              tests unitaires de la cible app (Swift Testing)
├─ EONAUITests/            tests UI (XCTest)
└─ scripts/ci.sh             xcodegen + xcodebuild test
```

Règles :

- Parité avec l'app Android : mêmes écrans, parcours, règles métier et appels API. Toute
  différence imposée par iOS est validée avant d'être codée.
- `EonaCore` et `EonaData` n'importent jamais UIKit, SwiftUI ni CoreLocation.
- Cible app : isolation `MainActor` par défaut (réglage Xcode 26). Le travail de fond sort
  explicitement du main actor.
- Les coordonnées d'itinéraire du backend sont `[longitude, latitude]`. Ne jamais les inverser.
- Aucun changement du contrat backend : l'app envoie `platform: "ios"` et un `deviceId` UUID
  gardé dans le Keychain (il survit à une réinstallation). Jeton de session dans le Keychain,
  le reste en JSON dans UserDefaults.
- Backend : `https://api.lrda-mercuriale.uk` (Cloudflare Tunnel vers le VPS), DNS normal : l'ancien
  contournement DNS-over-HTTPS de l'adresse `ts.net` n'existe plus.
- Carte : `MKMapView` (UIKit) piloté par une boucle 60 i/s pour la flèche et la caméra. Dans un
  fichier qui importe MapKit et SwiftUI, écrire `EonaData.MapStyle` (MapKit a aussi un
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
