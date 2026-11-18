--[[
	cl_net.lua — Le côté client du réseau : `Sanctions.Agir` écrit une intention, les réponses partent en hooks.

	Le client n'envoie qu'une intention, dans l'ordre exact de la table `LIRE` de sv_net.lua. Un écran ne reçoit que
	par `SanctionsDossier` / `SanctionsRefus`, et vérifie lui-même que le dossier reçu est celui qu'il montre.
--]]

VALDERAAN = VALDERAAN or {}
VALDERAAN.Sanctions = VALDERAAN.Sanctions or {}

local Sanctions = VALDERAAN.Sanctions

-- Lu au runtime : sh_types, qui pose NET et CHAMPS_MODIFIABLES, charge après ce fichier.
local ECRIRE = {
	Ouvrir = function(intention) net.WriteString(intention.steamid64) end,
	Mien = function() end,
	Creer = function(intention)
		net.WriteString(intention.steamid64)
		net.WriteString(intention.type)
		net.WriteString(intention.texte)
		net.WriteString(intention.sanction)
		net.WriteUInt(intention.fin or 0, 32)
	end,
	Modifier = function(intention)
		net.WriteUInt(intention.id, 32)

		for _, cle in ipairs(Sanctions.CHAMPS_MODIFIABLES) do
			local valeur = intention[cle]

			net.WriteBool(valeur != nil)

			if (valeur != nil) then
				if (cle == "fin") then
					net.WriteUInt(valeur, 32)
				else
					net.WriteString(valeur)
				end
			end
		end
	end,
	Annuler = function(intention) net.WriteUInt(intention.id, 32) end
}

---@param action "Ouvrir"|"Mien"|"Creer"|"Modifier"|"Annuler"
---@param intention table?
function Sanctions.Agir(action, intention)
	-- Une erreur d'écriture laisserait le message ouvert : le suivant serait refusé par le moteur.
	if (!ECRIRE[action]) then
		return ErrorNoHalt("[Sanctions] action inconnue : " .. tostring(action) .. "\n")
	end

	net.Start(Sanctions.NET.agir)
		net.WriteString(action)
		ECRIRE[action](intention or {})
	net.SendToServer()
end

---@class SanctionsDossierRecu
---@field steamid64 string
---@field nomSteam string?
---@field dossiers SanctionDossier[] chacun porte `.journal`
---@field personnages {id: integer, nom: string}[]
---@field peutGerer boolean
---@field mien boolean? réponse à `Mien`, que la fenêtre staff ignore

hook.Add("InitializedPlugins", "sanctionsNet", function()
	net.Receive(Sanctions.NET.dossier, function()
		local taille = net.ReadUInt(32)
		local recu = util.JSONToTable(util.Decompress(net.ReadData(taille)) or "")

		if (istable(recu)) then
			hook.Run("SanctionsDossier", recu)
		end
	end)

	-- Un refus qu'aucun écran ouvert ne prend s'affiche en notification : il ne se perd jamais en silence.
	net.Receive(Sanctions.NET.refus, function()
		local raison = net.ReadString()

		if (!hook.Run("SanctionsRefus", raison)) then
			LocalPlayer():Notify(raison)
		end
	end)
end)
