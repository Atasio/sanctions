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
- **Un seul droit**, l'accès ULX `ulx sanctions`, lu par `CAMI.PlayerHasAccess` dans `Sanctions.PeutGerer`.
- **Le menu C ne passe pas par `CanProperty`** : Helix n'y laisse que les admins, son plugin `propprotect` y refuse
  toute entité qu'on ne possède pas (un joueur compris), et l'ordre des méthodes de plugin n'est pas garanti.
- **Un dossier né d'un rattrapage ne réécrit pas ULib** : il garde le motif et l'auteur d'ULX, et sa `fin` est l'`unban`
  d'ULib, à la seconde.
- **Un temporaire stocke sa fin, pas une durée** : la seule date reçue du réseau, bornée par `Sanctions.ErreurFin`.
- **L'état ne se stocke pas** : `Sanctions.Etat(dossier, maintenant)` le recalcule des deux côtés.

## Structure

| Fichier | Rôle |
|---|---|
| `sh_plugin.lua` | déclaration |
| `libs/sh_commande.lua` | `Sanctions.PeutGerer` (seul lecteur du droit, des deux côtés), commande `!sanctions`, `ResoudreCible`, entrée `sanctions` du menu C |
| `libs/sh_types.lua` | types d'infraction et sanctions (ids persistés), bornes, `ErreurFin`, `Etat`, `Libelle`, `EstSteamID64`, noms des canaux |
| `libs/sv_base.lua` | tables `val_sanctions` et `val_sanctions_journal`, `Sanctions.Ecrire` (seule écriture, journal compris), `Creer`, `Modifier`, `Annuler`, `Lever`, `Lire`, `Dossier` |
| `libs/sv_ulib.lua` | `Sanctions.Appliquer` (seul appelant de `ULib.addBan` / `unban`, sous garde), rattrapage des ban / unban hors interface, remplacement de l'actif |
| `libs/sv_net.lua` | `Sanctions.Recevoir` (débit, droit, forme, puis `sv_base`), `Repondre` ; canaux dans `Sanctions.NET` |
| `libs/cl_net.lua` | `Sanctions.Agir(action, intention)`, miroir exact de `LIRE` (`sv_net.lua`) ; les réponses partent en hooks `SanctionsDossier` / `SanctionsRefus` (un refus qu'aucun écran ne prend devient une notification) |
| `libs/cl_liste.lua` | `Sanctions.Liste(parent, dossiers, options)`, la liste partagée des deux écrans (dépli sur le journal, actions en callback) ; `DateLongue`, `DateHeure`, `DateHeureCourte`, `Espacer` / `PoserEspace` (interlettrage), `Defilement` |
| `libs/cl_onglet.lua` | l'onglet `sanctions` du menu TAB (lecture seule, `Mien`), `DossiersEssai` et la vue de capture `sanctions_liste` |
| `libs/cl_fenetre.lua` | la fenêtre staff d'un compte (liste, formulaire à fin datée, confirmations), ouverte par tout dossier reçu hors `Mien` ; vue `sanctions_fenetre` |
| `banc/etat.lua` | la formule d'état sur des dossiers factices |
| `banc/base.lua` | dossiers et journal sur un faux compte |
| `banc/ulib.lua` | application, remplacement et rattrapage sur des faux comptes |
| `banc/refus.lua` | refus de la porte réseau : droit, bornes, débit, `Mien` |
| `banc/cible.lua` | résolution de cible de `!sanctions`, filtre du menu C, inscription ULX |

## Le client

Les `cl_` de `libs/` chargent avant les `sh_` : `NET`, `Etat`, `Libelle` s'y lisent au runtime, et les récepteurs
réseau se posent à `InitializedPlugins`. Le journal ne garde que des diffs : `cl_liste` reconstruit l'état d'avant
chaque entrée en remontant du dossier actuel, création comprise.

## Modèle de données

L'enveloppe `mysql` de Helix met toute valeur entre guillemets : **aucun NULL**. Un champ « absent » s'écrit 0 (ou
`""`), et `versDossier` le rend nil ; côté appelant, `false` demande l'effacement d'un champ (un nil serait sauté par
`pairs`). Le journal ne stocke que le diff (`avant` / `apres` en JSON) ; une création n'en porte pas.

Un faux compte de banc se bâtit d'un `STEAM_0:x:y` (`util.SteamIDTo64`) : un SteamID64 sous la base Steam
(`76561197960265728`) ne survit pas à l'aller-retour `SteamIDFrom64` → `SteamIDTo64` que fait le rattrapage. Et un bot
n'a jamais d'accès ULib (garde de `schema/libs/sv_banc_bot.lua`) : un scénario donne le droit en remplaçant
`Sanctions.PeutGerer`, et lit les réponses en remplaçant `Sanctions.Repondre`.

## État

Chantier en cours (tâche 8 sur 10, constats de séance en attente). Toutes les bornes sont des placeholders.
