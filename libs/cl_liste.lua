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

function Sanctions.DateHeure(quand)
	return Sanctions.DateLongue(quand) .. ", " .. tonumber(os.date("%H", quand)) .. " h " .. os.date("%M", quand)
end

local function jours(n)
	return n .. (n > 1 and " jours" or " jour")
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
		return "Terminé · " .. jours(dossier.jours or 0)
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

	return "bannissement de " .. jours(etat.jours or 0)
end

local function decrireModification(avant, apres)
	local changes = {}

	if (avant.type != apres.type) then
		changes[#changes + 1] = "infraction " .. Sanctions.Libelle(avant.type) .. " → " .. Sanctions.Libelle(apres.type)
	end

	if (avant.sanction != apres.sanction) then
		changes[#changes + 1] = decrireSanction(avant) .. " → " .. decrireSanction(apres)
	elseif (apres.sanction == "temporaire" and avant.jours != apres.jours) then
		changes[#changes + 1] = "durée " .. (avant.jours or 0) .. " → " .. jours(apres.jours or 0)
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
	local apres = {type = dossier.type, texte = dossier.texte, sanction = dossier.sanction, jours = dossier.jours}
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
		row.libelleEtat = theme().upper(libelleEtat(dossier, etat, echeance))
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

	draw.SimpleText(row.titre, K.Role("heading"), gauche, S(24), titre, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(row.texteCourt or "", K.Role("smallIt"), gauche, S(50), texte, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	draw.SimpleText(row.libelleEtat, K.Role("micro"), droite, S(23), col[style.encre], TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	draw.SimpleText(row.date, K.Role("small"), droite, S(50), texte, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)

	if (style.barre_texte) then
		barrer(gauche, S(24), row.largeurTitre, col.text3)
		barrer(gauche, S(50), row.largeurTexte, col.text3)
	end
end

local function layoutLigne(row, width)
	local largeur = math.min(K.Scale(row.actions and 380 or 520), width - row.marge - K.Scale(200))

	row.texteCourt = K.Fit(string.gsub(row.dossier.texte or "", "%s+", " "), K.Role("smallIt"), largeur)
	surface.SetFont(K.Role("smallIt"))
	row.largeurTexte = surface.GetTextSize(row.texteCourt)
	surface.SetFont(K.Role("heading"))
	row.largeurTitre = surface.GetTextSize(row.titre)
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

		draw.SimpleText(entree.quand, K.Role("micro"), S(20), cy, col.text2, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
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

---@class SanctionsListeOptions
---@field actions boolean?               « Modifier » / « Annuler » par ligne (staff)
---@field OnModifier fun(dossier: SanctionDossier)?
---@field OnAnnuler fun(dossier: SanctionDossier)?
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
		local depli = liste:Add("Panel")

		row:SetText("")
		row:Dock(TOP)
		row:SetTall(K.Scale(72))
		row.dossier = dossier
		row.titre = theme().upper(Sanctions.Libelle(dossier.type))
		row.date = Sanctions.DateLongue(dossier.cree_le or dossier.debut or 0) .. " · " .. (dossier.auteur_nom or "?")
		row.marge = K.Scale(16)
		row.actions = options.actions
		row.survolForce = options.survol == rang
		row.deplie = options.deplie == dossier.id
		row.Paint = paintLigne
		row.PerformLayout = layoutLigne

		if (options.actions) then
			ajouterActions(row, options)
		end

		depli:Dock(TOP)
		depli.texte = dossier.texte or ""
		depli.entrees = entreesJournal(dossier)
		depli.Paint = paintDepli
		depli.PerformLayout = layoutDepli
		depli:SetVisible(row.deplie)

		function row:DoClick()
			self.deplie = !self.deplie
			depli:SetVisible(self.deplie)
			liste:InvalidateLayout()
		end
	end

	return liste
end
