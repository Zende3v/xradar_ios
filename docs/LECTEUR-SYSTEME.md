# Lecteur système — IPA interne

Build 44. Essai demandé par Arthur, 06/10/2026.

Archive build 43 bloquée : transfert objet Objective-C non `Sendable` vers acteur interface.
Build 44 convertit relevé en valeurs Swift immuables avant transfert. Aucun `@unchecked Sendable` ajouté.

Build 42 testé par Arthur : lecture/pause Video Lite fonctionne. Icône figée, métadonnées absentes, suivant/précédent sans effet.
Centre de contrôle Video Lite propose déplacement temporel. Changement piste via EONA reste non démontré.

- Source « Lecteur système » dans menu du mini-player. Accessible invité, gratuit et EONA+.
- Cible lecteur actif choisi par iOS. Bascule lecture/pause conserve mécanisme confirmé sur téléphone.
- Navigation adaptative, séparée par direction : piste suivante/précédente prioritaire si lecteur annonce commande activée.
- Sans commande piste : déplacement temporel seulement si lecteur annonce commande et intervalle positif fini.
- Bouton temporel affiche secondes exactes annoncées ; aucun saut temporel présenté comme changement piste.
- Capacité inaccessible : conserver essai piste réel. Capacité connue désactivée : bouton visible grisé.
- Aucun lien AirPods spécifique. Aucun besoin API Video Lite ni présence casque.
- Métadonnées locales facultatives : titre, artiste, pochette, état de lecture. Aucun envoi backend.
- Métadonnées absentes : titre générique sobre, aucun avertissement orange. État inconnu affiche bouton lecture/pause combiné.
- État privilégie vitesse lecture relevée, puis état identifié du lecteur. `false` sans identité reste inconnu.
- Repli public `AVAudioSession.isOtherAudioPlaying` suit activité audio autre app après première observation positive.
- Repli audio peut refléter buffering, interruption ou autre app ; aucun succès commande déduit de cette observation.
- Envoi accepté ne prouve aucun effet. Aucun état ni titre fabriqué ; refus iOS affiché.
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
- `MRMediaRemoteSendCommand` conserve code 2 confirmé. Commandes navigation : 4/5 pour pistes, 17/18 pour intervalle déclaré.
- Navigation utilise `MRMediaRemoteSendCommandToApp` avec accusé si disponible. Accusé réussi ne prouve aucun changement piste.
- Capacités : `MRMediaRemoteGetSupportedCommandsForOrigin`, `MRCommandInfo.command/isEnabled/options`.
- Option `kMRMediaRemoteOptionSkipInterval` : tableau annoncé, nombre scalaire envoyé. Aucun intervalle 15 s imposé.
- Métadonnées : `MRMediaRemoteGetNowPlayingInfo` ; repli facultatif `MRNowPlayingRequest.localNowPlayingItem.nowPlayingInfo`.
- Getters synchrones du repli restent hors interface ; une opération maximum même après timeout.
- Sélecteurs absents : repli ignoré. Aucune identité application modifiée, aucun entitlement ajouté.
- ABI relue depuis [headers Theos](https://github.com/theos/headers/blob/master/MediaRemote/MediaRemote.h).
- Capacités et commandes relues dans [tests Apple WebKit](https://github.com/WebKit/WebKit/blob/main/Tools/TestWebKitAPI/Tests/WebKit/WKWebView/MediaSession.mm).
- Repli classe relu dans [dump iOS 17.0.3](https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/MediaRemote.framework/MRNowPlayingRequest.h).
- Signal audio documenté par [Apple](https://developer.apple.com/documentation/avfaudio/avaudiosession/isotheraudioplaying).
- Framework conservé chargé ; callbacks livrés sur file principale. Aucun `dlclose` pendant callback.
- [Règle Apple 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements) exige APIs publiques.
- Aucune compilation Mac disponible ici. Aucun succès iOS 26 déduit de mesures macOS.
- Trois régressions ciblées ajoutées dans `EONATests/SystemMediaNavigationTests.swift` ; non exécutées sous Windows.

## Validation Arthur

1. Construire workflow `IPA non signée`, installer build 44.
2. Lancer playlist Video Lite. Revenir dans EONA ; ouvrir Musique, toucher pochette, choisir « Lecteur système ».
3. Vérifier icône pause puis lecture après clic. Vérifier commandes depuis Centre de contrôle puis retour EONA.
4. Avec playlist exposant commandes piste, vérifier suivant/précédent. Avec lecteur temporel, vérifier boutons et intervalle annoncés.
5. Vérifier absence avertissement métadonnées, titres/pochette si accessibles. Relever comportement réel malgré accusé accepté.
6. Fermer mini-player, verrouiller puis reprendre. Vérifier reprise et changement source Apple Music/Spotify.
7. Si refus : fournir texte exact, version iOS, commande concernée. Ne pas conclure support confirmé sans effet observé.
