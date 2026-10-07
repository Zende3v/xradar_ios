# Stations proches — build 50

08/10/2026. iOS uniquement ; backend requis pour espèces et rayon.

- Trois contrôles compacts : carburant, classement, Espèces.
- Carburant choisi garde prix, même en tri Proximité.
- Tri Prix conserve sélection des stations proches, adaptée à densité. Aucun prix périmé affiché.
- Espèces exige déclaration positive. Paiement absent ou incompris reste inconnu, jamais refus supposé.
- Rayon initial 10 km. Moins de cinq stations ouvertes : proposer 25 puis 50 km.
- Élargissement explicite conserve carburant, classement et filtre espèces.
- Résultat vide : élargissement disponible ; Tous les paiements retire seulement filtre espèces.
- Zone dense : espèces filtrées côté serveur avant limite de 60 candidats ; application affiche 20 ouverts au maximum.
- Stations fermées restent séparées. Horaires station ne prouvent jamais encaissement espèces disponible maintenant.
- Aucun changement carte, trajet, compte ou offre. Recherche depuis départ choisi, sinon position actuelle.
- Changement carburant ou classement reste local. Espèces/rayon relancent recherche ; réponses annulées ignorées.
- Choix carburant, classement et espèces persistés. Rayon reste propre à écran courant.
- Sources dans action discrète : prix officiels récents, © OpenStreetMap, distances à vol d'oiseau.

## Contrat

- `GET /api/places/near?lat&lon&kind=fuel&pool=1&radius=10000&cash=1`.
- `radius` mètres, maximum 50 000. `cash=1` exige espèces ; absence conserve tous paiements.
- Station ajoute `cashPayment: {accepted:true|false|null,source:"osm"|null}`.
- OSM `payment:cash=yes|only` accepté ; `no` refusé. Aucune déduction depuis enseigne ou automate.
- Prix restent dans `fuel`. Ancien backend sans champ paiement donne état inconnu.
- Ancien backend peut ignorer rayon ; application recoupe distances reçues pour respecter rayon affiché.
- Backend préparé mais activation et enrichissement production exigent accord Arthur.

## Sources vérifiées

- [Flux officiel carburants](https://www.prix-carburants.gouv.fr/rubrique/opendata/) : prix et horaires guichet.
- Flux du 08/10 examiné : 9 796 stations, 27 services distincts ; aucun service paiement espèces.
- [OSM payment:cash](https://wiki.openstreetmap.org/wiki/Key:payment:cash) : acceptation déclarée.
- [Export Osmose publié sur data.gouv](https://www.data.gouv.fr/datasets/stations-service-1) : donnée paiement peu renseignée.
- Mesure export du 08/10 : 12 534 lignes, 173 `yes`, 110 `no`, 1 intervalle ; 12 250 sans indication.
- Couverture export ≈2,3 %, pas garantie couverture de toutes stations. Élargissement ne crée aucune donnée manquante.

## Validation

- Revue ciblée contrat, filtres et annulation réalisée. Boutons de résultat vide indépendants dans `List`.
- Régressions Core : espèces avant limite, fermés filtrés, prix conservé en Proximité, densité selon stations admissibles.
- Régression Data : bool strict, compatibilité ancien backend, paramètres rayon/espèces.
- Compilation Swift indisponible sous Windows. Arthur lance Codemagic ou workflow manuel GitHub, puis validation iPhone.
- Vérifier filtres combinés, vide, réseau coupé/Réessayer, 10/25/50 km, changement rapide de filtre et choix station/étape.
