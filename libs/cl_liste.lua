--[[
	cl_liste.lua — La liste des dossiers d'un compte, partagée par l'onglet du joueur et la fenêtre du staff.

	Elle n'envoie rien : « Modifier » et « Annuler » remontent un callback. L'état d'une ligne se recalcule au Paint par
	`Sanctions.Etat`, jamais stocké ; les couleurs aussi (`col.x` relu à chaque Paint : bascule de thème).
--]]

VALDERAAN = VALDERAAN or {}
VALDERAAN.Sanctions = VALDERAAN.Sanctions or {}

local Sanctions = VALDERAAN.Sanctions

---@class UIKit
local K = VALDERAAN.UI

local MOIS = {"janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."}

local function theme()
	return VALDERAAN.MenuTheme
end

local function dateCourte(quand)
	local d = os.date("*t", quand)

	return d.day .. " " .. MOIS[d.month]
end

function Sanctions.DateLongue(quand)
	return dateCourte(quand) .. " " .. os.date("%Y", quand)
end

local function heure(quand)
	return tonumber(os.date("%H", quand)) .. " h " .. os.date("%M", quand)
end

function Sanctions.DateHeure(quand)
	return Sanctions.DateLongue(quand) .. ", " .. heure(quand)
end

--- Sans l'année : une fin de bannissement tombe presque toujours dans l'année qui court.
function Sanctions.DateHeureCourte(quand)
	return dateCourte(quand) .. ", " .. heure(quand)
end

-- Ce que l'état écrit à droite, sa couleur, et le liseré de gauche des états qui pèsent encore.
local STYLE = {
	banni = {encre = "danger", barre = "danger"},
	banni_jusqu = {encre = "danger", barre = "danger"},
	avertissement = {encre = "accent", barre = "accent"},
	termine = {encre = "text3", eteint = true},
	leve = {encre = "text3", eteint = true},
	annule = {encre = "text3", eteint = true, barre_texte = true}
}

local function libelleEtat(dossier, etat, echeance)
	if (etat == "banni") then
		return "Banni définitivement"
	elseif (etat == "banni_jusqu") then
		return "Banni jusqu'au " .. dateCourte(echeance)
	elseif (etat == "avertissement") then
		return "Avertissement"
	elseif (etat == "termine") then
		return "Terminé le " .. dateCourte(dossier.fin or dossier.debut or 0)
	elseif (etat == "leve") then
		return "Levé"
	end

	return "Annulé"
end

local function decrireSanction(etat)
	if (etat.sanction == "aucune") then
		return "avertissement"
	elseif (etat.sanction == "definitive") then
		return "bannissement définitif"
	end

	return "bannissement jusqu'au " .. Sanctions.DateHeureCourte(tonumber(etat.fin) or 0)
end

local function decrireModification(avant, apres)
	local changes = {}

	if (avant.type != apres.type) then
		changes[#changes + 1] = "infraction " .. Sanctions.Libelle(avant.type) .. " → " .. Sanctions.Libelle(apres.type)
	end

	if (avant.sanction != apres.sanction) then
		changes[#changes + 1] = decrireSanction(avant) .. " → " .. decrireSanction(apres)
	elseif (apres.sanction == "temporaire" and avant.fin != apres.fin) then
		changes[#changes + 1] = "fin " .. Sanctions.DateHeureCourte(tonumber(avant.fin) or 0) .. " → "
			.. Sanctions.DateHeureCourte(tonumber(apres.fin) or 0)
	end

	if (avant.texte != apres.texte) then
		changes[#changes + 1] = "description corrigée"
	end

	return table.concat(changes, ", ")
end

-- Une levée et un remplacement disent tous deux « Levé ».
local VERBES = {creation = "Posé par ", modification = "Modifié par ", annulation = "Annulé par "}

--- Le journal ne garde que des diffs : on remonte du dossier actuel en défaisant chaque modification, ce qui rend
--- l'état d'avant et d'après de chaque entrée, création comprise.
local function entreesJournal(dossier)
	local apres = {type = dossier.type, texte = dossier.texte, sanction = dossier.sanction, fin = dossier.fin}
	local journal = dossier.journal or {}
	local entrees = {}

	for index = #journal, 1, -1 do
		local entree = journal[index]
		local avant = table.Copy(apres)
		local detail

		if (entree.action == "modification") then
			for cle, valeur in pairs(entree.avant or {}) do
				avant[cle] = valeur
			end

			detail = decrireModification(avant, apres)
		elseif (entree.action == "creation") then
			detail = decrireSanction(apres)
		elseif (entree.action == "remplacement" and entree.apres and entree.apres.remplace_par) then
			detail = "remplacé par le dossier #" .. entree.apres.remplace_par
		end

		table.insert(entrees, 1, {
			quand = theme().upper(Sanctions.DateHeure(entree.quand or 0)),
			prefixe = VERBES[entree.action] or "Levé par ", nom = entree.auteur_nom or "?", suite = (detail and detail != "") and (" : " .. detail) or ""
		})
		apres = avant
	end

	return entrees
end

local function couper(texte, police, largeur)
	surface.SetFont(police)

	local lignes = {}

	for paragraphe in string.gmatch(texte .. "\n", "(.-)\n") do
		local courante = ""

		for mot in string.gmatch(paragraphe, "%S+") do
			local essai = (courante == "") and mot or (courante .. " " .. mot)

			if (courante != "" and surface.GetTextSize(essai) > largeur) then
				lignes[#lignes + 1] = courante
				courante = mot
			else
				courante = essai
			end
		end

		lignes[#lignes + 1] = courante
	end

	return lignes
end

-- Un moteur de police n'a pas d'interlettrage : `SelectKit` (schema) pose les lettres une à une.
function Sanctions.Espacer(texte, police, espace)
	return VALDERAAN.SelectKit.Track(texte, police, K.Scale(espace))
end

function Sanctions.PoserEspace(trace, police, x, cy, couleur, aDroite)
	VALDERAAN.SelectKit.DrawTracked(trace, police, aDroite and x - trace.width or x, math.Round(cy - trace.height / 2), couleur)
end

local function barrer(x, cy, largeur, couleur)
	surface.SetDrawColor(couleur)
	surface.DrawRect(x, cy, largeur, 1)
end

local function paintLigne(row, width, height)
	local col = theme().col
	local dossier = row.dossier
	local etat, echeance = Sanctions.Etat(dossier, os.time())
	local style = STYLE[etat]
	local S = K.Scale
	local gauche, droite = S(20), width - row.marge

	if (row.etat != etat) then
		row.etat = etat
		row.libelleEtat = Sanctions.Espacer(theme().upper(libelleEtat(dossier, etat, echeance)), K.Role("micro"), 3)
	end

	if (row.deplie) then
		VALDERAAN.MenuSkin.Selection(0, 0, width, height, 1, true)
	elseif (row.survolForce or row:IsHovered() or row:IsChildHovered()) then
		VALDERAAN.MenuSkin.Selection(0, 0, width, height, 0.5, false)
	end

	if (style.barre) then
		surface.SetDrawColor(col[style.barre])
		surface.DrawRect(0, S(12), S(3), height - 2 * S(12))
	end

	local titre = style.eteint and col.text3 or col.textTitle
	local texte = style.barre_texte and col.text3 or col.textNotes

	Sanctions.PoserEspace(row.titreEspace, K.Role("heading"), gauche, S(24), titre)

	if (row.compteCourt) then
		draw.SimpleText(row.compteCourt, K.Role("small"), gauche + row.largeurTitre + S(14), S(24),
			style.eteint and col.text3 or col.text1, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	draw.SimpleText(row.texteCourt or "", K.Role("smallIt"), gauche, S(50), texte, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	Sanctions.PoserEspace(row.libelleEtat, K.Role("micro"), droite, S(23), col[style.encre], true)
	draw.SimpleText(row.date, K.Role("small"), droite, S(50), texte, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

	if (style.barre_texte) then
		barrer(gauche, S(24), row.largeurTitre, col.text3)
		barrer(gauche, S(50), row.largeurTexte, col.text3)
	end
end

local function layoutLigne(row, width)
	local largeur = math.min(K.Scale(row.actions and 380 or (row.compte and 540 or 520)), width - row.marge - K.Scale(200))

	row.texteCourt = K.Fit(string.gsub(row.dossier.texte or "", "%s+", " "), K.Role("smallIt"), largeur)
	surface.SetFont(K.Role("smallIt"))
	row.largeurTexte = surface.GetTextSize(row.texteCourt)
	row.titreEspace = Sanctions.Espacer(row.titre, K.Role("heading"), 1)
	row.largeurTitre = row.titreEspace.width

	if (row.compte) then
		local dossier = row.dossier
		local nom = (dossier.perso_nom and dossier.perso_nom != "") and dossier.perso_nom or dossier.steamid64

		row.compteCourt = K.Fit(nom, K.Role("small"), math.max(K.Scale(40), width - row.marge - K.Scale(240) - row.largeurTitre))
	end
end

local function paintDepli(depli, width, height)
	local col = theme().col
	local S = K.Scale
	local y = S(4)

	for _, ligne in ipairs(depli.lignes or {}) do
		draw.SimpleText(ligne, K.Role("text"), S(20), y + S(15), col.text1, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		y = y + S(30)
	end

	y = y + S(14)

	for _, entree in ipairs(depli.entrees) do
		local cy = y + S(14)
		local x = S(200)

		Sanctions.PoserEspace(entree.quandEspace, K.Role("micro"), S(20), cy, col.text2)
		x = x + draw.SimpleText(entree.prefixe, K.Role("small"), x, cy, col.textNotes, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		x = x + draw.SimpleText(entree.nom, K.Role("small"), x, cy, col.text1, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(entree.suiteCourte or "", K.Role("small"), x, cy, col.textNotes, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		y = y + S(28)
	end
end

local function layoutDepli(depli, width)
	if (depli.largeurCalculee == width) then return end

	local S = K.Scale

	depli.largeurCalculee = width
	surface.SetFont(K.Role("small"))

	for _, entree in ipairs(depli.entrees) do
		entree.quandEspace = Sanctions.Espacer(entree.quand, K.Role("micro"), 2)

		local debut = S(200) + surface.GetTextSize(entree.prefixe .. entree.nom)

		entree.suiteCourte = K.Fit(entree.suite, K.Role("small"), width - debut - S(16))
	end

	depli.lignes = couper(depli.texte, K.Role("text"), width - S(36))
	depli:SetTall(S(4) + #depli.lignes * S(30) + S(14) + #depli.entrees * S(28) + S(16))
end

local function ajouterActions(row, options)
	local dossier = row.dossier
	local boutons = row:Add("Panel")
	local refus = dossier.annulee and "Dossier annulé." or nil

	boutons:Dock(RIGHT)
	boutons:DockMargin(0, K.Scale(20), K.Scale(8), K.Scale(20))

	local annuler = K.ActionButton(boutons, "Annuler", "danger", function() options.OnAnnuler(dossier) end, refus)
	local modifier = K.ActionButton(boutons, "Modifier", "ghost", function() options.OnModifier(dossier) end, refus)

	annuler:Dock(RIGHT)
	modifier:Dock(RIGHT)
	modifier:DockMargin(0, 0, K.Scale(4), 0)
	boutons:SetWide(annuler:GetWide() + modifier:GetWide() + K.Scale(4))
	row.marge = boutons:GetWide() + K.Scale(24)
end

--- La barre de défilement des deux écrans : un filet, sans boutons.
---@param scroll DScrollPanel
function Sanctions.Defilement(scroll)
	local bar = scroll:GetVBar()

	bar:SetWide(K.Scale(6))
	bar:SetHideButtons(true)

	function bar:Paint() end

	function bar.btnGrip:Paint(width, height)
		surface.SetDrawColor(theme().col.lineSoft)
		surface.DrawRect(0, 0, width, height)
	end
end

---@class SanctionsListeOptions
---@field actions boolean?               « Modifier » / « Annuler » par ligne (staff)
---@field OnModifier fun(dossier: SanctionDossier)?
---@field OnAnnuler fun(dossier: SanctionDossier)?
---@field compte boolean?                le compte visé après le type d'infraction (journal général)
---@field clic fun(dossier: SanctionDossier)?  remplace le dépli : un clic remonte le dossier
---@field deplie integer?                id du dossier ouvert d'emblée
---@field survol integer?                rang d'une ligne peinte survolée (vue de capture : la souris en est écartée)

--- Un panneau docké en haut, haut comme ses lignes. Un clic sur une ligne la déplie sur son texte et son journal.
---@param parent Panel
---@param dossiers SanctionDossier[]
---@param options SanctionsListeOptions?
---@return Panel
function Sanctions.Liste(parent, dossiers, options)
	options = options or {}

	local liste = parent:Add("Panel")

	liste:Dock(TOP)

	-- Les déplis prennent leur hauteur ICI, avant la mesure : un passage de mise en page suffit. Un panneau peint à la main
	-- (capture `valderaan_ui`) n'exécute pas les InvalidateLayout différés.
	function liste:PerformLayout(width)
		local avant = self:GetTall()

		for _, enfant in ipairs(self:GetChildren()) do
			if (enfant.entrees) then
				layoutDepli(enfant, width)
			end
		end

		self:SizeToChildren(false, true)

		-- Dans un DScrollPanel, le parent est le canevas : c'est le panneau de défilement qui le redimensionne.
		if (self:GetTall() != avant) then
			self:GetParent():InvalidateLayout()
			self:GetParent():GetParent():InvalidateLayout()
		end
	end

	for rang, dossier in ipairs(dossiers) do
		local row = liste:Add("DButton")
		local depli = !options.clic and liste:Add("Panel")

		row:SetText("")
		row:Dock(TOP)
		row:SetTall(K.Scale(72))
		row.dossier = dossier
		row.titre = theme().upper(Sanctions.Libelle(dossier.type))
		row.date = Sanctions.DateLongue(dossier.cree_le or dossier.debut or 0) .. " · " .. (dossier.auteur_nom or "?")
		row.marge = K.Scale(16)
		row.actions = options.actions
		row.compte = options.compte
		row.survolForce = options.survol == rang
		row.deplie = options.deplie == dossier.id
		row.Paint = paintLigne
		row.PerformLayout = layoutLigne

		if (options.actions) then
			ajouterActions(row, options)
		end

		if (depli) then
			depli:Dock(TOP)
			depli.texte = dossier.texte or ""
			depli.entrees = entreesJournal(dossier)
			depli.Paint = paintDepli
			depli.PerformLayout = layoutDepli
			depli:SetVisible(row.deplie)
		end

		function row:DoClick()
			if (!depli) then
				return options.clic(dossier)
			end

			self.deplie = !self.deplie
			depli:SetVisible(self.deplie)
			liste:InvalidateLayout()
		end
	end

	return liste
end
