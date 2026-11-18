--[[
	cl_onglet.lua — L'onglet « Sanctions » du menu TAB : le dossier du joueur, en lecture seule, et sa vue de capture.

	L'onglet ne demande que `Mien` : le serveur prend le SteamID de l'appelant et n'en lit aucun. Il redemande à chaque
	ouverture, rien n'est poussé.
--]]

VALDERAAN = VALDERAAN or {}
VALDERAAN.Sanctions = VALDERAAN.Sanctions or {}

local Sanctions = VALDERAAN.Sanctions

---@class UIKit
local K = VALDERAAN.UI

local function theme()
	return VALDERAAN.MenuTheme
end

local function styleScroll(scroll)
	local bar = scroll:GetVBar()

	bar:SetWide(K.Scale(6))
	bar:SetHideButtons(true)

	function bar:Paint() end

	function bar.btnGrip:Paint(width, height)
		surface.SetDrawColor(theme().col.lineSoft)
		surface.DrawRect(0, 0, width, height)
	end
end

local function ligneTexte(parent, texte, role, hauteur, marge)
	local panel = parent:Add("Panel")

	panel:Dock(TOP)
	panel:SetTall(K.Scale(hauteur))
	panel:DockMargin(0, K.Scale(marge), 0, 0)

	function panel:Paint(width, height)
		draw.SimpleText(texte, K.Role(role), 0, height / 2, theme().col.text3, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end
end

local function construire(container)
	local page = container:Add("Panel")

	page:Dock(FILL)
	K.Rule(page, "Votre dossier")

	page.corps = page:Add("DScrollPanel")
	page.corps:Dock(FILL)
	page.corps:DockMargin(0, K.Scale(14), 0, 0)
	styleScroll(page.corps)

	return page
end

---@param options SanctionsListeOptions?
local function remplir(page, dossiers, options)
	page.corps:Clear()

	if (#dossiers == 0) then
		return ligneTexte(page.corps, "Aucune sanction", "value", 32, 0)
	end

	Sanctions.Liste(page.corps, dossiers, options)
	ligneTexte(page.corps, "Une sanction se conteste auprès du staff, sur Discord.", "small", 28, 24)
end

VALDERAAN.Menu.Register({
	id = "sanctions", label = "Sanctions", short = "Sanct.", icon = "sanctions", order = 890, section = "systeme",
	Build = function(container)
		local page = construire(container)

		page.attente = true
		ligneTexte(page.corps, "Lecture du dossier…", "small", 28, 0)

		hook.Add("SanctionsDossier", page, function(self, recu)
			if (recu.steamid64 == LocalPlayer():SteamID64()) then
				self.attente = false
				remplir(self, recu.dossiers or {})
			end
		end)

		-- Un refus de `Mien` (débit, dossier trop lourd) prend la place du dossier : l'onglet ne reste jamais vide.
		hook.Add("SanctionsRefus", page, function(self, raison)
			if (!self.attente) then return end

			self.attente = false
			self.corps:Clear()
			ligneTexte(self.corps, raison, "small", 28, 0)

			return true
		end)

		Sanctions.Agir("Mien")
	end
})

-- Les données de la maquette validée (tâche 6), dates comprises : la capture compare l'écran, pas des données.
local function quand(jour, mois, heure, minute)
	return os.time({year = 2026, month = mois, day = jour, hour = heure or 20, min = minute or 0})
end

local function creation(nom, t)
	return {action = "creation", quand = t, auteur_nom = nom}
end

local function dossiersEssai()
	return {
		{id = 4, type = "freekill", sanction = "temporaire", jours = 3, debut = quand(17, 11, 21, 4), cree_le = quand(17, 11, 21, 4),
			auteur_nom = "Elrond", annulee = false, journal = {creation("Elrond", quand(17, 11, 21, 4))},
			texte = "A abattu trois villageois à la sortie de la taverne, sans la moindre scène."},
		{id = 3, type = "hrp_vocal", sanction = "aucune", debut = quand(12, 11), cree_le = quand(12, 11),
			auteur_nom = "Galadh", annulee = false, journal = {creation("Galadh", quand(12, 11))},
			texte = "Parlait de son match de foot en vocal de proximité pendant une audience."},
		{id = 2, type = "metagaming", sanction = "temporaire", jours = 2, debut = quand(2, 11, 21, 4), cree_le = quand(2, 11, 21, 4),
			auteur_nom = "Elrond", annulee = false,
			texte = "A utilisé le nom d'un assassin appris sur Discord pour le dénoncer en jeu, avant toute enquête de son personnage.",
			journal = {
				creation("Elrond", quand(2, 11, 21, 4)),
				{action = "modification", quand = quand(3, 11, 18, 30), auteur_nom = "Galadh", avant = {jours = 5}, apres = {jours = 2}}
			}},
		{id = 1, type = "insulte", sanction = "aucune", debut = quand(28, 10), cree_le = quand(28, 10),
			auteur_nom = "Mirwen", annulee = true,
			journal = {creation("Mirwen", quand(28, 10)), {action = "annulation", quand = quand(29, 10), auteur_nom = "Mirwen"}},
			texte = "Insulte en message privé, retirée : le joueur visé jouait la scène."}
	}
end

K.Vue("sanctions_liste", {782, 760}, function(parent, data)
	remplir(construire(parent), data.dossiers, data.options)
end, {
	vide = function() return {dossiers = {}} end,
	quatre = function() return {dossiers = dossiersEssai(), options = {survol = 2}} end,
	deplie = function() return {dossiers = dossiersEssai(), options = {survol = 2, deplie = 2}} end
})
