--[[
	sv_ulib.lua — Le seul fichier qui appelle ULib.addBan / ULib.unban et écoute leurs hooks.

	ULib applique (le refus de connexion reste le sien), le dossier fait foi : un ban ou un unban tapé hors de
	l'interface est rattrapé dans un dossier. Au plus un bannissement actif par compte.
--]]

local Sanctions = VALDERAAN.Sanctions

if (!ULib or !ULib.addBan) then
	print("[Sanctions] ULib absent : aucun bannissement ne sera appliqué ni rattrapé.")

	return
end

-- ⚠️ ULibPlayerBanned / ULibPlayerUnBanned partent en synchrone pour NOS appels aussi (bans.lua:203, :228) :
-- sans la garde, chaque bannissement posé par le plugin se rattraperait en un second dossier.
local garde = false

-- Un dossier né d'un rattrapage a déjà son entrée ULib : la réécrire effacerait le motif et l'auteur d'ULX.
local rattrapes = {}

local function sousGarde(appel, ...)
	garde = true
	local ok, erreur = pcall(appel, ...)
	garde = false

	if (!ok) then
		ErrorNoHalt("[Sanctions] " .. tostring(erreur) .. "\n")

		return "Dossier écrit, mais ULib a échoué : vérifiez le bannissement."
	end
end

local function motif(dossier)
	return Sanctions.Libelle(dossier.type) .. " — dossier #" .. dossier.id
end

--- Lève, en `remplacement`, tout autre bannissement actif du compte : ULib ne tient qu'une entrée par SteamID.
local function remplacer(acteur, dossier, callback)
	Sanctions.DossiersDe(dossier.steamid64, function(dossiers)
		local maintenant = os.time()
		local restants = {}

		for _, ancien in ipairs(dossiers) do
			if (ancien.id != dossier.id and Sanctions.BannitEncore(ancien, maintenant)) then
				restants[#restants + 1] = ancien.id
			end
		end

		local function suivant()
			local id = table.remove(restants)

			if (!id) then return callback() end

			Sanctions.Lever(acteur, id, "remplacement", {remplace_par = dossier.id}, suivant)
		end

		suivant()
	end)
end

--- Met ULib d'accord avec le dossier qu'on vient d'écrire. N'enlève une entrée que si CE dossier la tenait.
---@param acteur SanctionActeur
---@param avant SanctionDossier?
---@param dossier SanctionDossier
---@param callback fun(erreur: string?)
function Sanctions.Appliquer(acteur, avant, dossier, callback)
	local maintenant = os.time()
	local steamid = util.SteamIDFrom64(dossier.steamid64)

	if (Sanctions.BannitEncore(dossier, maintenant)) then
		remplacer(acteur, dossier, function()
			if (rattrapes[dossier.steamid64]) then return callback() end

			local echeance = Sanctions.Echeance(dossier)
			local minutes = echeance and math.max(1, math.ceil((echeance - maintenant) / 60)) or 0

			callback(sousGarde(ULib.addBan, steamid, minutes, motif(dossier), dossier.perso_nom, acteur.nom))
		end)

		return
	end

	if (avant and Sanctions.BannitEncore(avant, maintenant) and ULib.bans[steamid]) then
		return callback(sousGarde(ULib.unban, steamid))
	end

	callback()
end

--- L'auteur d'une entrée ULib : « Nom(STEAM_0:…) » pour un joueur, « (Console) » sinon (bans.lua:151).
local function acteurULib(nom)
	nom = isstring(nom) and nom or "(Console)"

	local steamid = nom:match("%((STEAM_%d:%d:%d+)%)$")

	return {steamid64 = steamid and util.SteamIDTo64(steamid) or "0", nom = nom}
end

local function actif(steamid64, callback)
	Sanctions.DossiersDe(steamid64, function(dossiers)
		local maintenant = os.time()

		for _, dossier in ipairs(dossiers) do
			if (Sanctions.BannitEncore(dossier, maintenant)) then return callback(dossier) end
		end

		callback(nil)
	end)
end

hook.Add(ULib.HOOK_USER_BANNED, "sanctionsRattrapage", function(steamid, entree)
	if (garde or !istable(entree)) then return end

	local texte = isstring(entree.reason) and entree.reason != "" and entree.reason or "(ban ULX sans motif)"

	local longueur = utf8.len(texte)

	if (!longueur) then
		texte = texte:sub(1, Sanctions.TEXTE_MAX)
	elseif (longueur > Sanctions.TEXTE_MAX) then
		texte = texte:sub(1, utf8.offset(texte, Sanctions.TEXTE_MAX + 1) - 1)
	end

	local champs = {type = "autre", texte = texte, sanction = "definitive"}
	local unban = tonumber(entree.unban) or 0

	if (unban > 0) then
		champs.sanction = "temporaire"
		champs.jours = math.Clamp(math.ceil((unban - os.time()) / Sanctions.JOUR), Sanctions.JOURS_MIN, Sanctions.JOURS_MAX)
		-- Les jours sont entiers, pas la durée d'ULX : le début recule pour que l'échéance tombe sur la sienne.
		champs.debut = unban - champs.jours * Sanctions.JOUR
	end

	local steamid64 = util.SteamIDTo64(steamid)

	rattrapes[steamid64] = true
	Sanctions.Creer(acteurULib(entree.modified_admin or entree.admin), steamid64, champs, function()
		rattrapes[steamid64] = nil
	end)
end)

hook.Add(ULib.HOOK_USER_UNBANNED, "sanctionsRattrapage", function(steamid, admin)
	if (garde) then return end

	local steamid64 = util.SteamIDTo64(steamid)

	actif(steamid64, function(dossier)
		if (!dossier) then return end

		local acteur = (IsValid(admin) and admin:IsPlayer()) and Sanctions.Acteur(admin) or acteurULib(admin)

		Sanctions.Lever(acteur, dossier.id, "levee", nil)
	end)
end)
