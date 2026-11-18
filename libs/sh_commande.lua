--[[
	sh_commande.lua — Le droit, la commande `!sanctions` et l'entrée du menu C.

	Les deux côtés lisent le droit : le client pour afficher, le serveur pour décider (sv_net revalide tout).
	La commande et le menu ne font qu'ouvrir un écran (`Ouvrir`, ou le journal) ; ils n'écrivent rien.
--]]

VALDERAAN = VALDERAAN or {}
VALDERAAN.Sanctions = VALDERAAN.Sanctions or {}

local Sanctions = VALDERAAN.Sanctions

-- ⚠️ `ulx.command` n'inscrit pas son accès dans CAMI, qui refuse tout privilège inconnu, superadmin compris.
if (CAMI) then
	CAMI.RegisterPrivilege({Name = "ulx sanctions", MinAccess = "admin", Description = "Dossiers de sanctions des comptes."})
end

--- Le seul lecteur du droit du plugin. `nil` est la console ; tout joueur invalide est refusé.
---@param client Player?
function Sanctions.PeutGerer(client)
	if (client == nil) then return true end
	if (!IsValid(client) or !client:IsPlayer() or !CAMI) then return false end

	return CAMI.PlayerHasAccess(client, "ulx sanctions") == true
end

-- ⚠️ Ni CanProperty ni properties.CanBeTargeted : Helix n'y autorise que IsAdmin() (sh_hooks.lua:442), son plugin
-- propprotect refuse toute entité qu'on ne possède pas, l'ordre des méthodes de plugin n'est pas garanti, et
-- CanBeTargeted exclut les joueurs. Le Filter lit le droit lui-même ; le serveur le rejoue, puis Recevoir revalide.
properties.Add("sanctions", {
	MenuLabel = "Sanctions",
	MenuIcon = "icon16/shield.png",
	Order = 2000,
	Filter = function(self, entity, client)
		return IsValid(entity) and entity:IsPlayer() and Sanctions.PeutGerer(client)
	end,
	Action = function(self, entity)
		self:MsgStart()
			net.WriteEntity(entity)
		self:MsgEnd()
	end,
	Receive = function(self, length, client)
		local entity = net.ReadEntity()

		if (!self:Filter(entity, client)) then return end

		Sanctions.Recevoir(client, "Ouvrir", {steamid64 = entity:SteamID64()})
	end
})

if (SERVER) then
	--- Un compte depuis ce que tape le staff : SteamID ou SteamID64 (connecté ou non), sinon un joueur connecté par
	--- `ULib.getUser` (`^`, `@`, nom partiel).
	---@param texte string
	---@param appelant Player?
	---@return string? steamid64
	---@return string? raison
	function Sanctions.ResoudreCible(texte, appelant)
		texte = string.Trim(texte or "")

		if (texte == "") then return nil end

		if (texte:upper():match("^STEAM_%d:%d:%d+$")) then
			return util.SteamIDTo64(texte:upper())
		elseif (Sanctions.EstSteamID64(texte)) then
			return texte
		end

		local cible, raison = ULib.getUser(texte, true, appelant)

		if (!IsValid(cible)) then
			return nil, raison or "Aucun joueur ne correspond."
		end

		return cible:SteamID64()
	end
end

if (!ulx or !ULib) then return end

if (SERVER) then
	--- Sans argument le journal général, sinon le dossier du compte visé.
	---@param appelant Player
	---@param texte string?
	function Sanctions.Commande(appelant, texte)
		if (string.Trim(texte or "") == "") then
			if (!Sanctions.PeutGerer(appelant)) then
				return ULib.tsayError(appelant, "Vous n'avez pas accès aux sanctions.", true)
			end

			return Sanctions.Repondre(appelant, "ouvrir", {})
		end

		local steamid64, raison = Sanctions.ResoudreCible(texte, appelant)

		if (!steamid64) then
			return ULib.tsayError(appelant, raison or "Aucun joueur ne correspond.", true)
		end

		Sanctions.Recevoir(appelant, "Ouvrir", {steamid64 = steamid64})
	end
end

local commande = ulx.command("Valderaan", "ulx sanctions", function(appelant, texte)
	if (!IsValid(appelant)) then
		return ULib.console(appelant, "Le dossier de sanctions s'ouvre en jeu.")
	end

	Sanctions.Commande(appelant, texte)
end, "!sanctions")

commande:addParam{type = ULib.cmds.StringArg, hint = "joueur ou SteamID", ULib.cmds.optional, ULib.cmds.takeRestOfLine}
commande:defaultAccess(ULib.ACCESS_ADMIN)
commande:help("Sans argument, le journal de tous les dossiers ; avec un joueur ou un SteamID, le dossier de son compte.")
