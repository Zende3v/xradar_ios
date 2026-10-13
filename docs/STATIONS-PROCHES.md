# Stations proches — build 53

13/10/2026. Schéma Arthur appliqué sur iOS.

- A1 : sélecteur services conservé.
- A3 : trois menus sous A1, carburant, Proximité/Prix, Espèces/Peu importe. Valeurs actuelles uniquement.
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
- Tests Swift et compilation non exécutés Windows. Arthur lance archive 53, puis validation iPhone.
- Contrôler trois menus avec thème unicolore et Opale, petit écran et texte agrandi, prix/proximité, espèces, vide et réseau coupé.
