# Stations proches — build 54

13/10/2026. Schéma Arthur appliqué sur iOS.

- A1 : sélecteur services conservé.
- A3 : rangée unique sous A1, trois boutons compacts de largeur égale et gabarit commun.
- Deux menus : carburant et Plus proche/Prix. Espèces bascule directement, cercle vide ou coché ; désactivé accepte tous paiements.
- Plus proche devient défaut après mise à jour. Nouveau choix Prix reste ensuite mémorisé, clé locale `fuelSortOrder`.
- Boutons reprennent surface primaire de Démarrer : verre, thème unicolore ou palette. Aucune couleur locale.
- A2 : lignes communes Bornes/Tabac ; prix à droite, distance, horaires et paiement déclaré dans détails existants.
- Aucun compteur stations, choix rayon, bouton Élargir ni paragraphe explicatif. Attribution sources courte conservée.
- Chargement sans phrase ; erreur avec Réessayer ; vide indique Aucune station. Trois réglages restent accessibles.
- Carburant et tri restent locaux. Paiement modifié relance recherche ; choix persistés.

## Recherche automatique

- Départ choisi, sinon position actuelle. Rayon initial 10 km.
- Zéro station admissible : 25 puis 50 km automatiquement. Aucun élargissement si résultat existe, même fermé ou sans prix.
- Erreur ou annulation arrête séquence. Aucun retrait automatique du filtre espèces.
- Distance connue entre zéro et rayon courant ; Espèces exige déclaration positive. Recoupe locale protège ancien backend.
- Prix récents conservés en Proximité. Tri Prix garde adaptation à densité ; stations fermées restent séparées.
- Jusqu'à trois requêtes `/api/places/near`, contrat backend inchangé. Aucun déploiement nécessaire.

## Données

- `cashPayment.accepted` : vrai, faux ou inconnu. OSM `payment:cash=yes|only` accepté ; `no` refusé.
- Aucun rapprochement par enseigne, guichet ou automate. Horaires station ne prouvent pas disponibilité encaissement.
- [Prix officiels](https://www.prix-carburants.gouv.fr/rubrique/opendata/) ; [déclaration espèces OSM](https://wiki.openstreetmap.org/wiki/Key:payment:cash).
- Mesure production du 08/10 : 160 déclarations positives, 105 négatives, 11 579 inconnues. Couverture limitée.

## Validation

- Surface partagée relue : boutons existants conservent rendu. A1 vérifié inchangé par diff.
- Six tests ciblés couvrent recherche automatique, arrêt au résultat/erreur/annulation et recoupe des critères.
- Un test migration couvre ancien défaut Prix, clé invalide et persistance des nouveaux choix de tri.
- Tests Swift et compilation non exécutés Windows. Arthur lance archive 54, puis validation iPhone.
- Contrôler rangée fixe avec thème unicolore et Opale, petit écran et texte agrandi, deux menus, bascule espèces et tri.
