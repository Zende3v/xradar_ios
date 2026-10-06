# Lecteur système — IPA interne

Build 42. Essai demandé par Arthur, 06/10/2026. Fonctionnement iOS 26 / Video Lite reste à mesurer.

- Source « Lecteur système » dans menu du mini-player. Accessible invité, gratuit et EONA+.
- Commandes réelles : bascule lecture/pause, piste suivante, piste précédente. Cible lecteur actif choisi par iOS.
- Aucun lien AirPods spécifique. Aucun besoin API Video Lite ni présence casque.
- Métadonnées locales facultatives : titre, artiste, pochette, état de lecture. Aucun envoi backend.
- Métadonnées absentes : commandes restent disponibles. État inconnu affiche bouton lecture/pause combiné.
- Envoi accepté ne prouve aucun effet. Aucun état ni titre fabriqué ; refus iOS affiché.
- Refresh toutes deux secondes, mini-player visible uniquement. Fermeture, changement source et arrière-plan arrêtent polling.
- Timeout lecture 1,2 s ; callbacks périmés ignorés. Pochette limitée 8 Mo, miniature 192 px, cache local.

## Activation et distribution

- Codemagic `ios-unsigned-ipa` active `EONA_EXPERIMENTAL_SYSTEM_MEDIA=1` pendant archive.
- Build ordinaire : adaptateur inactif. Menu conserve Apple Music et Spotify.
- Aucun entitlement privé ajouté. Aucun remplacement des handlers ni informations Now Playing des autres apps.
- API privée Apple : incompatible règles App Store. Désactivation exigée avant distribution App Store/TestFlight.
- Source inactive compile sans fonctions, noms de symboles ni chargement du framework privé.

## Mécanisme et preuve

- Chargement facultatif `MediaRemote.framework` via `dlopen`. Symboles absents : erreur lisible, aucun appel nul.
- `MRMediaRemoteSendCommand` : codes 2, 4, 5 ; options `nil`. Retour `Boolean`, valeur non nulle indique envoi seulement.
- Métadonnées : `MRMediaRemoteGetNowPlayingInfo`. État : `MRMediaRemoteGetNowPlayingApplicationIsPlaying`.
- ABI relue depuis [headers Theos](https://github.com/theos/headers/blob/master/MediaRemote/MediaRemote.h).
- Framework conservé chargé ; callbacks livrés sur file principale. Aucun `dlclose` pendant callback.
- [Règle Apple 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements) exige APIs publiques.
- Aucune compilation Mac disponible ici. Aucun succès iOS 26 déduit de mesures macOS.

## Validation Arthur

1. Construire workflow `IPA non signée`, installer build 42.
2. Lancer playlist Video Lite. Revenir dans EONA ; ouvrir Musique, toucher pochette, choisir « Lecteur système ».
3. Vérifier pause puis reprise ; suivant puis précédent avec file de lecture compatible.
4. Observer titres/pochette si accessibles. Relever comportement réel même si commande déclarée envoyée.
5. Fermer mini-player, verrouiller puis reprendre. Vérifier reprise et changement source Apple Music/Spotify.
6. Si refus : fournir texte exact, version iOS, commande concernée. Ne pas conclure support confirmé sans effet observé.
