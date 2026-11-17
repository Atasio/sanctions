# sanctions — plugin Helix de Valderaan

Les avertissements et bannissements du staff, posés sur un **compte Steam** (SteamID64), jamais sur un personnage,
avec le journal de chaque modification. Les pièges Helix transversaux vivent au `CLAUDE.md` du schema ; celui-ci porte
l'archi et l'état. Spec : `docs/dev/specs/2026-11-17-sanctions-design.md` ; reprise du chantier :
`docs/dev/chantiers/2026-11-17-sanctions/etat.md` (dépôt `valderaan`, branche `sanctions`).

## Les règles dures du plugin

- **ULib applique, le dossier fait foi.** Le refus de connexion reste celui d'ULib ; le plugin le pose, le modifie,
  le lève, et rattrape dans un dossier tout `!ban` / `!unban` tapé hors de l'interface.
- **On ne supprime jamais une ligne.** Un dossier s'annule ; toute écriture d'un dossier écrit son entrée de journal,
  par une seule fonction serveur.
- **Un seul droit**, l'accès ULX `ulx sanctions`, lu par `CAMI.PlayerHasAccess`.
- **L'état ne se stocke pas** : `Sanctions.Etat(dossier, maintenant)` le recalcule des deux côtés.

## Structure

| Fichier | Rôle |
|---|---|
| `sh_plugin.lua` | déclaration |
| `libs/sh_types.lua` | le global `VALDERAAN.Sanctions`, types d'infraction (ids persistés), bornes, `Etat`, `Libelle` |
| `libs/sv_base.lua` | tables `val_sanctions` et `val_sanctions_journal`, `Sanctions.Ecrire` (seule écriture, journal compris), `Creer`, `Modifier`, `Annuler`, `Lever`, `Lire`, `Dossier` |
| `banc/etat.lua` | la formule d'état sur des dossiers factices |
| `banc/base.lua` | dossiers et journal sur un faux compte |

## Modèle de données

L'enveloppe `mysql` de Helix met toute valeur entre guillemets : **aucun NULL**. Un champ « absent » s'écrit 0 (ou
`""`), et `versDossier` le rend nil ; côté appelant, `false` demande l'effacement d'un champ (un nil serait sauté par
`pairs`). Le journal ne stocke que le diff (`avant` / `apres` en JSON) ; une création n'en porte pas.

## État

Chantier en cours (tâche 2 sur 10). Toutes les bornes sont des placeholders.
