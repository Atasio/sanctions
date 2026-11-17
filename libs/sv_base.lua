--[[
	sv_base.lua — Les tables des dossiers et du journal, et la SEULE fonction qui les écrit.

	Toute écriture d'un dossier écrit son entrée de journal dans `Ecrire` ; rien ne supprime une ligne.
	Ces fonctions ne vérifient aucun droit : `sv_net` filtre avant de les appeler.
--]]

local PLUGIN = PLUGIN
local Sanctions = VALDERAAN.Sanctions

local MODIFIABLES = {type = true, texte = true, sanction = true, jours = true}

-- ⚠️ L'enveloppe `mysql` de Helix met toute valeur entre guillemets (`sv_mysql.lua:158`) : pas de NULL possible.
-- « Aucun » s'écrit donc 0 ou "" en base, et redevient nil à la lecture.
local function enBase(valeur)
	if (valeur == nil or valeur == false) then
		return 0
	elseif (isbool(valeur)) then
		return valeur and 1 or 0
	end

	return valeur
end

local function nonNul(valeur)
	local nombre = tonumber(valeur)

	return (nombre and nombre != 0) and nombre or nil
end

---@return SanctionDossier
local function versDossier(row)
	return {
		id = tonumber(row.id),
		steamid64 = row.steamid64,
		type = row.type,
		texte = row.texte,
		sanction = row.sanction,
		jours = nonNul(row.jours),
		debut = tonumber(row.debut),
		levee_le = nonNul(row.levee_le),
		auteur_steamid64 = row.auteur_steamid64,
		auteur_nom = row.auteur_nom,
		perso_id = nonNul(row.perso_id),
		perso_nom = (row.perso_nom != "") and row.perso_nom or nil,
		cree_le = tonumber(row.cree_le),
		annulee = tonumber(row.annulee) == 1
	}
end

local function createTables()
	local query = mysql:Create("val_sanctions")
		query:Create("id", "INT(11) UNSIGNED NOT NULL AUTO_INCREMENT")
		query:Create("steamid64", "VARCHAR(20) NOT NULL")
		query:Create("type", "VARCHAR(32) NOT NULL")
		query:Create("texte", "TEXT NOT NULL")
		query:Create("sanction", "VARCHAR(16) NOT NULL")
		query:Create("jours", "INT(11) NOT NULL DEFAULT 0")
		query:Create("debut", "INT(11) NOT NULL")
		query:Create("levee_le", "INT(11) NOT NULL DEFAULT 0")
		query:Create("auteur_steamid64", "VARCHAR(20) NOT NULL")
		query:Create("auteur_nom", "VARCHAR(128) NOT NULL")
		query:Create("perso_id", "INT(11) NOT NULL DEFAULT 0")
		query:Create("perso_nom", "VARCHAR(128) NOT NULL DEFAULT ''")
		query:Create("cree_le", "INT(11) NOT NULL")
		query:Create("annulee", "TINYINT(1) NOT NULL DEFAULT 0")
		query:PrimaryKey("id")
	query:Execute()

	query = mysql:Create("val_sanctions_journal")
		query:Create("id", "INT(11) UNSIGNED NOT NULL AUTO_INCREMENT")
		query:Create("sanction_id", "INT(11) NOT NULL")
		query:Create("quand", "INT(11) NOT NULL")
		query:Create("auteur_steamid64", "VARCHAR(20) NOT NULL")
		query:Create("auteur_nom", "VARCHAR(128) NOT NULL")
		query:Create("action", "VARCHAR(16) NOT NULL")
		query:Create("avant", "TEXT NOT NULL")
		query:Create("apres", "TEXT NOT NULL")
		query:PrimaryKey("id")
	query:Execute()
end

-- Une seule DatabaseConnected par plugin ; elle ne lit que ses tables (sur base vierge, Helix crée les siennes après).
function PLUGIN:DatabaseConnected()
	createTables()
end

---@class SanctionActeur
---@field steamid64 string
---@field nom string

--- L'auteur d'une écriture, toujours lu côté serveur. La console signe « (Console) ».
---@param client Player?
---@return SanctionActeur
function Sanctions.Acteur(client)
	if (!IsValid(client)) then
		return {steamid64 = "0", nom = "(Console)"}
	end

	return {steamid64 = client:SteamID64(), nom = client:SteamName()}
end

local function journaliser(acteur, action, sanctionID, avant, apres, callback)
	local query = mysql:Insert("val_sanctions_journal")
		query:Insert("sanction_id", sanctionID)
		query:Insert("quand", os.time())
		query:Insert("auteur_steamid64", acteur.steamid64)
		query:Insert("auteur_nom", acteur.nom)
		query:Insert("action", action)
		query:Insert("avant", avant and util.TableToJSON(avant) or "")
		query:Insert("apres", apres and util.TableToJSON(apres) or "")
		query:Callback(callback)
	query:Execute()
end

--- La seule écriture des deux tables. `avant` nil : création, `champs` est la ligne entière.
--- Sinon `champs` ne porte que ce qui change ; `note` s'ajoute à l'`apres` du journal (ex. `remplace_par`).
---@param acteur SanctionActeur
---@param action "creation"|"modification"|"annulation"|"levee"|"remplacement"
---@param avant SanctionDossier?
---@param champs table
---@param callback fun(dossier: SanctionDossier?, raison: string?)?
---@param note table?
function Sanctions.Ecrire(acteur, action, avant, champs, callback, note)
	callback = callback or function() end

	if (!avant) then
		local query = mysql:Insert("val_sanctions")

		for cle, valeur in pairs(champs) do
			query:Insert(cle, enBase(valeur))
		end

		query:Callback(function(_, _, id)
			local dossier = table.Copy(champs)
			dossier.id = id

			journaliser(acteur, action, id, nil, nil, function()
				callback(dossier)
			end)
		end)
		query:Execute()

		return
	end

	local diffAvant, diffApres = {}, {}

	for cle, valeur in pairs(champs) do
		if (enBase(avant[cle]) != enBase(valeur)) then
			diffAvant[cle] = enBase(avant[cle])
			diffApres[cle] = enBase(valeur)
		end
	end

	if (next(diffApres) == nil) then
		return callback(nil, "Rien à modifier.")
	end

	local query = mysql:Update("val_sanctions")

	for cle, valeur in pairs(diffApres) do
		query:Update(cle, valeur)
	end

	query:Where("id", avant.id)
	query:Callback(function()
		local dossier = table.Merge(table.Copy(avant), champs)

		-- `false` marque un champ remis à « aucun » : `pairs` aurait sauté un nil.
		if (dossier.jours == false) then dossier.jours = nil end

		journaliser(acteur, action, avant.id, diffAvant, table.Merge(diffApres, note or {}), function()
			callback(dossier)
		end)
	end)
	query:Execute()
end

---@param id integer
---@param callback fun(dossier: SanctionDossier?)
function Sanctions.Lire(id, callback)
	local query = mysql:Select("val_sanctions")
		query:Where("id", id)
		query:Limit(1)
		query:Callback(function(rows)
			callback(istable(rows) and rows[1] and versDossier(rows[1]) or nil)
		end)
	query:Execute()
end

--- Les dossiers d'un compte, du plus récent au plus ancien.
---@param steamid64 string
---@param callback fun(dossiers: SanctionDossier[])
function Sanctions.DossiersDe(steamid64, callback)
	local query = mysql:Select("val_sanctions")
		query:Where("steamid64", steamid64)
		query:OrderByDesc("id")
		query:Callback(function(rows)
			local dossiers = {}

			for _, row in ipairs(istable(rows) and rows or {}) do
				dossiers[#dossiers + 1] = versDossier(row)
			end

			callback(dossiers)
		end)
	query:Execute()
end

---@param cible64 string
---@param champs {type: string, texte: string, sanction: SanctionKind, jours: integer?}
---@param callback fun(dossier: SanctionDossier?, raison: string?)?
function Sanctions.Creer(acteur, cible64, champs, callback)
	local maintenant = os.time()
	local ligne = {
		steamid64 = cible64,
		type = champs.type,
		texte = champs.texte,
		sanction = champs.sanction,
		jours = champs.sanction == "temporaire" and champs.jours or nil,
		debut = champs.debut or maintenant,
		auteur_steamid64 = acteur.steamid64,
		auteur_nom = acteur.nom,
		cree_le = maintenant,
		annulee = false
	}

	local joueur = player.GetBySteamID64(cible64)
	local personnage = IsValid(joueur) and joueur:GetCharacter()

	if (personnage) then
		ligne.perso_id = personnage:GetID()
		ligne.perso_nom = personnage:GetName()
	end

	Sanctions.Ecrire(acteur, "creation", nil, ligne, callback)
end

--- Type et texte se corrigent toujours ; la sanction d'un dossier levé ou terminé, jamais (rebannir = un nouveau
--- dossier). Un avertissement qui devient un bannissement commence maintenant.
---@param champs {type: string?, texte: string?, sanction: SanctionKind?, jours: integer?}
function Sanctions.Modifier(acteur, id, champs, callback)
	callback = callback or function() end

	Sanctions.Lire(id, function(avant)
		if (!avant) then return callback(nil, "Dossier introuvable.") end
		if (avant.annulee) then return callback(nil, "Ce dossier est annulé.") end

		local voulu = {}

		for cle, valeur in pairs(champs) do
			if (MODIFIABLES[cle]) then
				voulu[cle] = valeur
			end
		end

		local sanction = voulu.sanction or avant.sanction

		if (voulu.sanction or voulu.jours) then
			local etat = Sanctions.Etat(avant, os.time())

			if (etat == "leve" or etat == "termine") then
				return callback(nil, "Ce bannissement est fini : posez un nouveau dossier.")
			end

			voulu.jours = (sanction == "temporaire") and (voulu.jours or avant.jours) or false

			if (avant.sanction == "aucune" and sanction != "aucune") then
				voulu.debut = os.time()
			end
		end

		Sanctions.Ecrire(acteur, "modification", avant, voulu, callback)
	end)
end

function Sanctions.Annuler(acteur, id, callback)
	callback = callback or function() end

	Sanctions.Lire(id, function(avant)
		if (!avant) then return callback(nil, "Dossier introuvable.") end
		if (avant.annulee) then return callback(nil, "Ce dossier est déjà annulé.") end

		Sanctions.Ecrire(acteur, "annulation", avant, {annulee = true}, callback)
	end)
end

--- Fin anticipée d'un bannissement : `levee` (unban) ou `remplacement` (un autre bannissement prend sa place).
---@param action "levee"|"remplacement"
function Sanctions.Lever(acteur, id, action, note, callback)
	callback = callback or function() end

	Sanctions.Lire(id, function(avant)
		if (!avant) then return callback(nil, "Dossier introuvable.") end

		Sanctions.Ecrire(acteur, action, avant, {levee_le = os.time()}, callback, note)
	end)
end

--- Le dossier complet d'un compte : ses lignes, le journal de chacune, les personnages du compte.
---@param steamid64 string
---@param callback fun(dossier: {dossiers: SanctionDossier[], journal: table<integer, table[]>, personnages: {id: integer, nom: string}[]})
function Sanctions.Dossier(steamid64, callback)
	Sanctions.DossiersDe(steamid64, function(dossiers)
		local resultat = {dossiers = dossiers, journal = {}, personnages = {}}

		local function personnages()
			local query = mysql:Select("ix_characters")
				query:Select("id")
				query:Select("name")
				query:Where("steamid", steamid64)
				query:Where("schema", Schema.folder)
				query:Callback(function(rows)
					for _, row in ipairs(istable(rows) and rows or {}) do
						resultat.personnages[#resultat.personnages + 1] = {id = tonumber(row.id), nom = row.name}
					end

					callback(resultat)
				end)
			query:Execute()
		end

		if (#dossiers == 0) then return personnages() end

		local ids = {}

		for _, dossier in ipairs(dossiers) do
			ids[#ids + 1] = dossier.id
			resultat.journal[dossier.id] = {}
		end

		local query = mysql:Select("val_sanctions_journal")
			query:WhereIn("sanction_id", ids)
			query:OrderByAsc("id")
			query:Callback(function(rows)
				for _, row in ipairs(istable(rows) and rows or {}) do
					local entrees = resultat.journal[tonumber(row.sanction_id)]

					if (entrees) then
						entrees[#entrees + 1] = {
							quand = tonumber(row.quand), action = row.action,
							auteur_steamid64 = row.auteur_steamid64, auteur_nom = row.auteur_nom,
							avant = util.JSONToTable(row.avant or "") or {}, apres = util.JSONToTable(row.apres or "") or {}
						}
					end
				end

				personnages()
			end)
		query:Execute()
	end)
end
