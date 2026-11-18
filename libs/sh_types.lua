--[[
	sh_types.lua — Les types d'infraction, les bornes et la formule d'état d'un dossier, partagés.

	Rien de ce qui se déduit n'est stocké : l'état se recalcule des deux côtés avec `Etat`, à l'instant voulu.
	Helix inclut libs/ AVANT sh_plugin.lua, par ordre alphabétique : chaque fichier qui lit le global au
	chargement le crée s'il manque.
--]]

VALDERAAN = VALDERAAN or {}
VALDERAAN.Sanctions = VALDERAAN.Sanctions or {}

local Sanctions = VALDERAAN.Sanctions

-- ⚠️ Un id est persisté en base : il ne se renomme plus. Le libellé se retouche librement. NON-CANON.
Sanctions.TYPES = {
	{id = "hrp_vocal", libelle = "HRP vocal"},
	{id = "metagaming", libelle = "Metagaming"},
	{id = "insulte", libelle = "Insulte ou offense personnelle"},
	{id = "glitch_exploit", libelle = "Glitch / exploit"},
	{id = "freekill", libelle = "Freekill"},
	{id = "autre", libelle = "Autre"}
}

local LIBELLES = {}

for _, infraction in ipairs(Sanctions.TYPES) do
	LIBELLES[infraction.id] = infraction.libelle
end

---@alias SanctionKind "aucune"|"temporaire"|"definitive"
Sanctions.SANCTIONS = {
	{id = "aucune", libelle = "Avertissement seul"},
	{id = "temporaire", libelle = "Bannissement temporaire"},
	{id = "definitive", libelle = "Bannissement définitif"}
}
Sanctions.SANCTION = {}

for _, sanction in ipairs(Sanctions.SANCTIONS) do
	Sanctions.SANCTION[sanction.id] = true
end

Sanctions.JOUR = 86400

-- PLACEHOLDERS.
Sanctions.TEXTE_MAX = 1000
Sanctions.FIN_MAX = 3650 * Sanctions.JOUR

Sanctions.NET = {agir = "sanctionsAgir", dossier = "sanctionsDossier", refus = "sanctionsRefus"}

-- Les champs que `Modifier` envoie, dans l'ordre du message ; chacun précédé d'un booléen « présent ».
Sanctions.CHAMPS_MODIFIABLES = {"type", "texte", "sanction", "fin"}

---@class SanctionDossier
---@field id integer
---@field steamid64 string
---@field type string
---@field texte string
---@field sanction SanctionKind
---@field fin integer? échéance d'un temporaire
---@field debut integer
---@field levee_le integer?
---@field auteur_steamid64 string
---@field auteur_nom string
---@field perso_id integer?
---@field perso_nom string?
---@field cree_le integer
---@field annulee boolean

---@alias SanctionEtat "annule"|"avertissement"|"leve"|"banni"|"banni_jusqu"|"termine"

--- Un compte Steam individuel : l'aller-retour par le SteamID écarte tout nombre hors de la plage des comptes.
function Sanctions.EstSteamID64(valeur)
	return isstring(valeur) and #valeur == 17 and valeur:match("^7656119%d+$") != nil
		and util.SteamIDTo64(util.SteamIDFrom64(valeur)) == valeur
end

function Sanctions.EstType(id)
	return LIBELLES[id] != nil
end

--- Un type retiré du code laisse des dossiers en base : ils s'affichent « Autre ».
function Sanctions.Libelle(id)
	return LIBELLES[id] or LIBELLES.autre
end

---@param dossier SanctionDossier
---@return integer?
function Sanctions.Echeance(dossier)
	if (dossier.sanction != "temporaire") then return end

	return dossier.fin
end

--- La borne d'une fin de bannissement, des deux côtés : le serveur refuse avec, l'écran éteint son verbe avec.
---@param fin any
---@param maintenant integer
---@return string? raison
function Sanctions.ErreurFin(fin, maintenant)
	if (!isnumber(fin) or fin != math.floor(fin)) then
		return "Date de fin invalide."
	elseif (fin <= maintenant) then
		return "La fin est déjà passée."
	elseif (fin > maintenant + Sanctions.FIN_MAX) then
		return "La fin dépasse " .. Sanctions.FIN_MAX / Sanctions.JOUR .. " jours."
	end
end

---@param dossier SanctionDossier
---@param maintenant integer
---@return SanctionEtat etat
---@return integer? echeance pour `banni_jusqu`
function Sanctions.Etat(dossier, maintenant)
	if (dossier.annulee) then
		return "annule"
	elseif (dossier.sanction == "aucune") then
		return "avertissement"
	elseif (dossier.levee_le) then
		return "leve"
	elseif (dossier.sanction == "definitive") then
		return "banni"
	end

	local echeance = Sanctions.Echeance(dossier)

	if (!echeance) then
		return "termine"
	elseif (echeance > maintenant) then
		return "banni_jusqu", echeance
	end

	return "termine"
end

--- Vrai tant que le dossier tient un bannissement en vigueur : c'est lui que pilote ULib.
---@param dossier SanctionDossier
---@param maintenant integer
function Sanctions.BannitEncore(dossier, maintenant)
	local etat = Sanctions.Etat(dossier, maintenant)

	return etat == "banni" or etat == "banni_jusqu"
end
