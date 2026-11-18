--[[
	sv_net.lua — La seule porte d'entrée du réseau : débit, droit, forme, puis sv_base.

	Le client n'envoie qu'une intention. L'auteur est toujours l'appelant, lu ici ; aucun nom, aucune date, aucun
	auteur ne vient du réseau. `Mien` ne lit aucune cible.
--]]

local Sanctions = VALDERAAN.Sanctions
local NET = Sanctions.NET

for _, nom in pairs(NET) do
	util.AddNetworkString(nom)
end

local ECRITURES = {Creer = true, Modifier = true, Annuler = true}

-- PLACEHOLDERS : une écriture par seconde, deux lectures par seconde.
local INTERVALLE_ECRITURE = 1
local INTERVALLE_LECTURE = 0.5

local derniers = {}

local function debit(client, ecriture)
	local maintenant = SysTime()
	local cle = ecriture and "ecriture" or "lecture"
	local etat = derniers[client] or {}

	derniers[client] = etat

	if (etat[cle] and maintenant - etat[cle] < (ecriture and INTERVALLE_ECRITURE or INTERVALLE_LECTURE)) then
		return false
	end

	etat[cle] = maintenant

	return true
end

hook.Add("PlayerDisconnected", "sanctionsDebit", function(client)
	derniers[client] = nil
end)

local function erreurTexte(texte)
	if (!isstring(texte)) then return "Texte manquant." end

	local longueur = utf8.len(string.Trim(texte))

	if (!longueur or longueur < 1) then return "Le texte est vide." end
	if (longueur > Sanctions.TEXTE_MAX) then return "Le texte dépasse " .. Sanctions.TEXTE_MAX .. " caractères." end
end

local function erreurJours(jours)
	if (!isnumber(jours) or jours != math.floor(jours) or jours < Sanctions.JOURS_MIN or jours > Sanctions.JOURS_MAX) then
		return "La durée va de " .. Sanctions.JOURS_MIN .. " à " .. Sanctions.JOURS_MAX .. " jours."
	end
end

--- Valide les champs présents ; `complet` les exige tous (création). Rend les champs nettoyés, ou nil et la raison.
local function valider(champs, complet)
	local propre = {}

	if (champs.type != nil or complet) then
		if (!Sanctions.EstType(champs.type)) then return nil, "Type d'infraction inconnu." end
		propre.type = champs.type
	end

	if (champs.texte != nil or complet) then
		local erreur = erreurTexte(champs.texte)

		if (erreur) then return nil, erreur end
		propre.texte = string.Trim(champs.texte)
	end

	if (champs.sanction != nil or complet) then
		if (!Sanctions.SANCTION[champs.sanction]) then return nil, "Sanction inconnue." end
		propre.sanction = champs.sanction
	end

	-- Un passage en temporaire porte sa durée : l'ancien dossier n'en a peut-être pas. À la création, la durée d'une
	-- autre sanction arrive à 0 du réseau et s'ignore.
	if (propre.sanction == "temporaire" or (!complet and champs.jours != nil)) then
		local erreur = erreurJours(champs.jours)

		if (erreur) then return nil, erreur end
		propre.jours = champs.jours
	end

	return propre
end

local function envoyer(client, nom, ecrire)
	if (!IsValid(client) or client:IsBot()) then return end

	net.Start(nom)
		ecrire()
	net.Send(client)
end

--- Les réponses passent par ici ; le banc la remplace pour lire ce qu'un client aurait reçu.
---@param client Player
---@param genre "dossier"|"refus"
---@param contenu table|string
function Sanctions.Repondre(client, genre, contenu)
	if (genre == "refus") then
		return envoyer(client, NET.refus, function() net.WriteString(contenu) end)
	end

	local compresse = util.Compress(util.TableToJSON(contenu))

	-- PLACEHOLDER, sous la limite de 64 Ko d'un message.
	if (#compresse > 60000) then
		return Sanctions.Repondre(client, "refus", "Dossier trop volumineux pour être envoyé.")
	end

	envoyer(client, NET.dossier, function()
		net.WriteUInt(#compresse, 32)
		net.WriteData(compresse, #compresse)
	end)
end

local function refuser(client, raison)
	Sanctions.Repondre(client, "refus", raison or "Action refusée.")
end

--- Le journal voyage dans chaque ligne : JSON perdrait les clés numériques d'une table indexée par id. `mien` dit à
--- l'écran que c'est la réponse à `Mien` : un staff a `peutGerer` aussi sur son propre onglet.
local function envoyerDossier(client, steamid64, mien)
	Sanctions.Dossier(steamid64, function(complet)
		if (!IsValid(client)) then return end

		local peutGerer = Sanctions.PeutGerer(client)

		-- Le joueur lit le nom du modérateur, jamais son SteamID.
		for _, dossier in ipairs(complet.dossiers) do
			dossier.journal = complet.journal[dossier.id] or {}

			if (!peutGerer) then
				dossier.auteur_steamid64 = nil

				for _, entree in ipairs(dossier.journal) do
					entree.auteur_steamid64 = nil
				end
			end
		end

		local joueur = player.GetBySteamID64(steamid64)

		Sanctions.Repondre(client, "dossier", {
			steamid64 = steamid64,
			nomSteam = IsValid(joueur) and joueur:SteamName() or nil,
			dossiers = complet.dossiers,
			personnages = complet.personnages,
			peutGerer = peutGerer,
			mien = mien or nil
		})
	end)
end

local function apresEcriture(client, dossier, raison)
	if (raison) then refuser(client, raison) end
	if (!dossier) then return end

	envoyerDossier(client, dossier.steamid64)
end

---@alias SanctionAction "Ouvrir"|"Mien"|"Creer"|"Modifier"|"Annuler"

--- Une intention déjà lue du réseau (ou fabriquée par le banc). Rien n'y est cru : tout est revalidé ici.
---@param client Player
---@param action SanctionAction
---@param intention {steamid64: string?, id: integer?, type: string?, texte: string?, sanction: string?, jours: integer?}
function Sanctions.Recevoir(client, action, intention)
	if (!IsValid(client)) then return end

	if (!debit(client, ECRITURES[action])) then
		return refuser(client, "Trop rapide : réessayez dans un instant.")
	end

	if (action == "Mien") then
		return envoyerDossier(client, client:SteamID64(), true)
	end

	if (!Sanctions.PeutGerer(client)) then
		return refuser(client, "Vous n'avez pas accès aux sanctions.")
	end

	local acteur = Sanctions.Acteur(client)

	if (action == "Ouvrir") then
		if (!Sanctions.EstSteamID64(intention.steamid64)) then return refuser(client, "Compte invalide.") end

		envoyerDossier(client, intention.steamid64)
	elseif (action == "Creer") then
		if (!Sanctions.EstSteamID64(intention.steamid64)) then return refuser(client, "Compte invalide.") end

		local champs, raison = valider(intention, true)

		if (!champs) then return refuser(client, raison) end

		Sanctions.Creer(acteur, intention.steamid64, champs, function(dossier, erreur)
			local vise = dossier and player.GetBySteamID64(dossier.steamid64)

			if (IsValid(vise)) then
				vise:Notify("Une sanction a été posée sur votre compte : consultez l'onglet Sanctions du menu.")
			end

			apresEcriture(client, dossier, erreur)
		end)
	elseif (action == "Modifier") then
		if (!isnumber(intention.id)) then return refuser(client, "Dossier invalide.") end

		local champs, raison = valider(intention, false)

		if (!champs) then return refuser(client, raison) end
		if (next(champs) == nil) then return refuser(client, "Rien à modifier.") end

		Sanctions.Modifier(acteur, intention.id, champs, function(dossier, erreur) apresEcriture(client, dossier, erreur) end)
	elseif (action == "Annuler") then
		if (!isnumber(intention.id)) then return refuser(client, "Dossier invalide.") end

		Sanctions.Annuler(acteur, intention.id, function(dossier, erreur) apresEcriture(client, dossier, erreur) end)
	end
end

local LIRE = {
	Ouvrir = function() return {steamid64 = net.ReadString()} end,
	Mien = function() return {} end,
	Creer = function()
		return {
			steamid64 = net.ReadString(), type = net.ReadString(), texte = net.ReadString(),
			sanction = net.ReadString(), jours = net.ReadUInt(16)
		}
	end,
	Modifier = function()
		local intention = {id = net.ReadUInt(32)}

		for _, cle in ipairs(Sanctions.CHAMPS_MODIFIABLES) do
			if (net.ReadBool()) then
				intention[cle] = (cle == "jours") and net.ReadUInt(16) or net.ReadString()
			end
		end

		return intention
	end,
	Annuler = function() return {id = net.ReadUInt(32)} end
}

net.Receive(NET.agir, function(_, client)
	local action = net.ReadString()
	local lire = LIRE[action]

	if (!lire) then return end

	Sanctions.Recevoir(client, action, lire())
end)
