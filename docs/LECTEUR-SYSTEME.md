# Lecteur système — IPA interne

Build 45. Dernier essai demandé par Arthur, 06/10/2026.

Archive build 43 bloquée : transfert objet Objective-C non `Sendable` vers acteur interface.
Build 44 convertit relevé en valeurs Swift immuables avant transfert. Aucun `@unchecked Sendable` ajouté.

Build 44 compile selon Arthur. Lecture/pause agit ; icône reste figée.
Nouvelle mesure Arthur : Skip/Back fonctionnent avec playlist Video Lite. Navigation 44 conservée.
Pochette/titre restent facultatifs ; aucune disponibilité Video Lite affirmée sans observation.

- Source « Lecteur système » dans menu du mini-player. Accessible invité, gratuit et EONA+.
- Cible lecteur actif choisi par iOS. Navigation garde transport confirmé ; lecture utilise commandes explicites 0/1.
- Pause explicite par défaut lorsque état inconnu. Appui prolongé bouton offre Lecture et Pause séparées.
- Un envoi par clic. Demande acceptée actualise icône ; « Lecture demandée » / « Pause demandée » reste affiché sans confirmation.
- Demande distincte de l'état observé. Événement direct ou relevé fiable concordant enlève mention de demande.
- Navigation adaptative, séparée par direction : piste suivante/précédente prioritaire si lecteur annonce commande activée.
- Sans commande piste : déplacement temporel seulement si lecteur annonce commande et intervalle positif fini.
- Bouton temporel affiche secondes exactes annoncées ; aucun saut temporel présenté comme changement piste.
- Capacité inaccessible : conserver essai piste réel. Capacité connue désactivée : bouton visible grisé.
- Aucun lien AirPods spécifique. Aucun besoin API Video Lite ni présence casque.
- Métadonnées locales facultatives : titre, artiste, pochette, état de lecture. Aucun envoi backend.
- Métadonnées absentes : titre générique sobre, aucun avertissement orange.
- Notifications : lire état 0/1, PID positif, titre/artiste/pochette si présents ; ne plus jeter `userInfo`.
- Exclure événements et relevés identifiés EONA. PID absent laisse identité application inconnue ; état concerne lecteur global.
- Notification directe reste prioritaire sur getters. Révision empêche relevé antérieur de remplacer événement récent.
- Changement application/source/fermeture efface observation et demande. Refus commande efface demande concernée, conserve observation réelle.
- État relevé utilise vitesse lecture ou lecteur identifié. Bool getter faible ne confirme aucune commande.
- Repli public `AVAudioSession.isOtherAudioPlaying` suit activité audio autre app après première observation positive.
- Repli audio peut refléter buffering, interruption ou autre app ; aucun succès commande déduit de cette observation.
- Envoi accepté ne prouve aucun effet. État demandé signalé ; aucun titre ni état observé fabriqué, refus affiché.
- Notifications inscrites uniquement mini-player visible. Polling secours chaque seconde ; fermeture/source/arrière-plan arrêtent observation.
- Après clic : relevés à 250, 600 et 1 300 ms. Demandes pendant lecture restent en attente.
- Aucun second envoi automatique, même après timeout. Métadonnées conservées pendant commande ; relevés antérieurs au clic ignorés.
- Timeout lecture 1,2 s ; callbacks périmés ignorés. Pochette limitée 8 Mo, miniature 192 px, cache local.

## Activation et distribution

- Codemagic `ios-unsigned-ipa` active `EONA_EXPERIMENTAL_SYSTEM_MEDIA=1` pendant archive.
- Build ordinaire : adaptateur inactif. Menu conserve Apple Music et Spotify.
- Aucun entitlement privé ajouté. Aucun remplacement des handlers ni informations Now Playing des autres apps.
- API privée Apple : incompatible règles App Store. Désactivation exigée avant distribution App Store/TestFlight.
- Source inactive compile sans fonctions, noms de symboles ni chargement du framework privé.

## Mécanisme et preuve

- Chargement facultatif `MediaRemote.framework` via `dlopen`. Symboles absents : erreur lisible, aucun appel nul.
- `MRMediaRemoteSendCommand` : Play 0 / Pause 1 via même transport legacy ; code Toggle 2 conservé dans adaptateur.
- Commandes navigation conservées : 4/5 pour pistes, 17/18 pour intervalle déclaré.
- Navigation utilise `MRMediaRemoteSendCommandToApp` avec accusé si disponible. Accusé réussi ne prouve aucun changement piste.
- Capacités : `MRMediaRemoteGetSupportedCommandsForOrigin`, `MRCommandInfo.command/isEnabled/options`.
- Option `kMRMediaRemoteOptionSkipInterval` : tableau annoncé, nombre scalaire envoyé. Aucun intervalle 15 s imposé.
- Métadonnées : `MRMediaRemoteGetNowPlayingInfo` ; repli facultatif `MRNowPlayingRequest.localNowPlayingItem.nowPlayingInfo`.
- Identité facultative : `MRMediaRemoteGetNowPlayingApplicationPID` ; aucune attribution Video Lite inventée si PID inaccessible.
- Signal direct : `kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey`, dans notification de changement lecture.
- Getters synchrones du repli restent hors interface ; une opération maximum même après timeout.
- Sélecteurs absents : repli ignoré. Aucune identité application modifiée, aucun entitlement ajouté.
- ABI relue depuis [headers Theos](https://github.com/theos/headers/blob/master/MediaRemote/MediaRemote.h).
- Capacités et commandes relues dans [tests Apple WebKit](https://github.com/WebKit/WebKit/blob/main/Tools/TestWebKitAPI/Tests/WebKit/WKWebView/MediaSession.mm).
- Repli classe relu dans [dump iOS 17.0.3](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/MediaRemote.framework/MRNowPlayingRequest.h).
- Signal audio documenté par [Apple](https://developer.apple.com/documentation/avfaudio/avaudiosession/isotheraudioplaying).
- Framework conservé chargé ; callbacks livrés sur file principale. Aucun `dlclose` pendant callback.
- [Règle Apple 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements) exige APIs publiques.
- Aucune compilation Mac disponible ici. Aucun succès iOS 26 déduit de mesures macOS.
- Trois régressions navigation, quatre régressions état. Événement prioritaire, demande distincte, reset, refus conservant observation.
- Tests app ajoutés ; non exécutés sous Windows. Aucun émulateur ni campagne supplémentaire lancé.

## Validation Arthur

1. Construire workflow `IPA non signée`, installer build 45.
2. Lancer playlist Video Lite. Revenir dans EONA ; ouvrir Musique, toucher pochette, choisir « Lecteur système ».
3. Vérifier pause puis reprise et icône après clic. Mention « demandée » signifie absence de confirmation observée.
4. Vérifier commandes casque/Centre de contrôle puis retour EONA. Appui prolongé offre commandes explicites sans dépendre icône.
5. Avec playlist Video Lite, revérifier Skip/Back confirmés sur 44. Avec lecteur temporel, vérifier intervalle annoncé.
6. Vérifier absence avertissement métadonnées, titres/pochette si accessibles. Relever comportement réel malgré accusé accepté.
7. Fermer mini-player, verrouiller puis reprendre. Vérifier reprise et changement source Apple Music/Spotify.
8. Si refus : fournir texte exact, version iOS, commande concernée. Ne pas conclure support confirmé sans effet observé.
