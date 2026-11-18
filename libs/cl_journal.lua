--[[
	cl_journal.lua — Le journal général de `!sanctions` (maquette `ui_maquette/sanctions_journal.html`) : tous les
	dossiers, du plus récent au plus ancien, quatre filtres, en lecture seule ; vue de capture `sanctions_journal`.

	Il n'envoie que des intentions de lecture. Une réponse n'est prise que si son curseur est celui de la dernière
	requête, et un changement de filtre repart de zéro.
--]]

VALDERAAN = VALDERAAN or {}
VALDERAAN.Sanctions = VALDERAAN.Sanctions or {}

local Sanctions = VALDERAAN.Sanctions

---@class UIKit
local K = VALDERAAN.UI

local WIDTH, HEIGHT, CORNER = 900, 678, 38
local FIELD_TOP, FIELD_WIDTH, FIELD_HEIGHT = 124, 190, 38
local FIELD_X = {40, 250, 460, 670}
local LIST_TOP, FOOT = 160, 104
local OPTION_HEIGHT, OPTION_PAD = 34, 10

local SANCTIONS_FILTRE = {
	{id = "", libelle = "Toutes"}, {id = "avertissement", libelle = "Avertissement"}, {id = "bannissement", libelle = "Bannissement"}
}

local function theme()
	return VALDERAAN.MenuTheme
end

local function S(n)
	return K.Scale(n)
end

local function filtresVides()
	return {sanction = "", type = "", moderateur = "", compte = ""}
end

-- `sh_types` charge après ce fichier : la liste des infractions ne se lit qu'au runtime.
local function typesFiltre()
	local options = {{id = "", libelle = "Toutes"}}

	for _, infraction in ipairs(Sanctions.TYPES) do
		options[#options + 1] = infraction
	end

	return options
end

local function libelleDe(options, id)
	for _, option in ipairs(options) do
		if (option.id == id) then return option.libelle end
	end

	return ""
end

local function fermerSurEchap(entry, fenetre)
	local base = entry.OnKeyCodeTyped

	entry.OnKeyCodeTyped = function(self, key)
		if (key == KEY_ESCAPE) then
			fenetre:Remove()

			return true
		end

		return base(self, key)
	end
end

---@class valSanctionsJournal : EditablePanel
---@field dossiers SanctionDossier[] les pages reçues, de la plus récente à la plus ancienne
---@field suite boolean? vrai tant qu'une page plus ancienne existe
local PANEL = {}

--- `apercu` ne sert qu'à la vue de capture : rien n'est envoyé, la souris en est écartée.
---@param apercu table?
function PANEL:Setup(apercu)
	self.apercu = apercu or {}
	self.policeNom = K.Font("Cinzel", S(24), 600)
	self.filtres = table.Copy(self.apercu.filtres or filtresVides())
	self.appliques = table.Copy(self.filtres)
	self.dossiers = self.apercu.dossiers or {}
	self.suite = self.apercu.suite
	self.charge = self.apercu.fige
	self.refus = self.apercu.refus

	self:SetSize(S(WIDTH), S(HEIGHT))

	if (!self.apercu.fige) then
		self:Center()
	end

	self:BuildClose()
	self:BuildFiltres()
	self.popup = self:Choix()
	self.plusAncien = self:Verbe("Plus ancien", true)
	self:Reconstruire()
	self:Actualiser()
	self:Charger(0)
end

function PANEL:BuildClose()
	self.close = self:Add("Panel")
	self.close:SetPos(S(WIDTH - 40 - 22), S(39))
	self.close:SetSize(S(22), S(22))
	self.close:SetCursor("hand")
	self.close.Paint = function(button, width, height)
		K.Cross(width / 2, height / 2, K.EvenBox(width), button:IsHovered() and theme().col.text1 or theme().col.text2)
	end
	self.close.OnMousePressed = function()
		self:Remove()
	end
end

function PANEL:BuildFiltres()
	self:Deroulante(FIELD_X[1], "Sanction", SANCTIONS_FILTRE, "sanction")
	self:Deroulante(FIELD_X[2], "Infraction", typesFiltre(), "type")
	self:Saisie(FIELD_X[3], "Modérateur", "moderateur")
	self:Saisie(FIELD_X[4], "Compte ou SteamID", "compte")
end

function PANEL:Deroulante(x, defaut, options, cle)
	local field = self:Add("Panel")

	field:SetPos(S(x), S(FIELD_TOP))
	field:SetSize(S(FIELD_WIDTH), S(FIELD_HEIGHT))
	field:SetCursor("hand")
	field.options, field.cle = options, cle
	field.Paint = function(_, width, height)
		local col = theme().col
		local bOuvert = self.ouverte == field
		local valeur = self.filtres[cle]
		local bActif = valeur != ""
		local encre = (bActif or bOuvert) and col.accent or col.text2

		surface.SetDrawColor((bActif or bOuvert) and col.accent or col.lineSoft)
		surface.DrawOutlinedRect(0, 0, width, height)
		draw.SimpleText(bActif and libelleDe(options, valeur) or defaut, K.Role("text"), S(12), height / 2,
			bActif and col.accent or col.textNotes, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		-- ⚠️ ValderaanIcons n'a pas de chevron : le triangle d'EB Garamond en tient lieu (Cinzel n'en a pas).
		draw.SimpleText("▼", K.Role("small"), width - S(12), height / 2, encre, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
	field.OnMousePressed = function()
		self:Ouvrir(self.ouverte != field and field or nil)
	end

	self.deroulantes = self.deroulantes or {}
	self.deroulantes[cle] = field
end

--- Un champ texte : le filtre ne part que sur Entrée, pour ne pas dépenser le débit de lecture à chaque lettre.
function PANEL:Saisie(x, defaut, cle)
	local cadre = self:Add("Panel")

	cadre:SetPos(S(x), S(FIELD_TOP))
	cadre:SetSize(S(FIELD_WIDTH), S(FIELD_HEIGHT))

	local entry = K.TextEntry(cadre, self.filtres[cle], S(FIELD_HEIGHT))
	local peindre = entry.Paint

	entry:GetParent():Dock(FILL)
	entry:SetUpdateOnType(true)
	fermerSurEchap(entry, self)

	entry.Paint = function(champ, width, height)
		peindre(champ, width, height)

		if (champ:GetText() == "") then
			draw.SimpleText(defaut, K.Role("textIt"), 3, height / 2, theme().col.text3, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
	entry.OnValueChange = function(champ, texte)
		self.filtres[cle] = string.Trim(texte)
	end
	entry.OnEnter = function()
		self:Filtrer()
	end
end

-- La liste ouverte d'une déroulante : la boîte flottante d'EDGE, posée par-dessus la liste.
function PANEL:Choix()
	local popup = self:Add("Panel")

	popup:SetVisible(false)
	popup.Paint = function(panel, width, height)
		local col = theme().col
		local skin = VALDERAAN.MenuSkin
		local field = self.ouverte
		local clipping = DisableClipping(true)

		skin.OmbreBoite(0, 0, width, height)
		DisableClipping(clipping)
		skin.PetiteBoite(panel, width, height)

		if (!field) then return end

		local _, mouseY = panel:CursorPos()

		for rang, option in ipairs(field.options) do
			local top = S(OPTION_PAD) + (rang - 1) * S(OPTION_HEIGHT)
			local bSurvol = panel:IsHovered() and mouseY >= top and mouseY < top + S(OPTION_HEIGHT)
			local ink = col.text1

			if (bSurvol) then
				skin.Selection(S(2), top, width - S(4), S(OPTION_HEIGHT), 0.6, false)
				ink = col.textTitle
			elseif (option.id == self.filtres[field.cle]) then
				ink = col.accent
			end

			draw.SimpleText(option.libelle, K.Role("text"), S(20), top + S(OPTION_HEIGHT) / 2, ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
	popup.OnMousePressed = function(panel)
		local field = self.ouverte
		local _, mouseY = panel:CursorPos()
		local option = field and field.options[math.floor((mouseY - S(OPTION_PAD)) / S(OPTION_HEIGHT)) + 1]

		self:Ouvrir(nil)

		if (option) then
			self.filtres[field.cle] = option.id
			self:Filtrer()
		end
	end

	return popup
end

---@param field Panel?
function PANEL:Ouvrir(field)
	self.ouverte = field
	self.popup:SetVisible(field != nil)

	if (!field) then return end

	local x, y = field:GetPos()

	self.popup:SetPos(x, y + field:GetTall() - 1)
	self.popup:SetSize(field:GetWide(), S(OPTION_PAD) * 2 + #field.options * S(OPTION_HEIGHT))
	self.popup:MoveToFront()
end

--- Les dossiers sous les filtres. Une page ajoutée garde la position de lecture.
---@param bGarder boolean? garder la position de lecture (une page ajoutée) ; sinon on repart du haut
function PANEL:Reconstruire(bGarder)
	local defilement = (bGarder and IsValid(self.scroll)) and self.scroll:GetVBar():GetScroll() or 0

	if (IsValid(self.zone)) then
		self.zone:Remove()
	end

	self.zone = self:Add("Panel")
	self.zone:SetPos(S(40), S(LIST_TOP))
	self.zone:SetSize(S(820), S(HEIGHT - FOOT - LIST_TOP))
	K.Rule(self.zone, "Du plus récent au plus ancien")

	self.scroll = self.zone:Add("DScrollPanel")
	self.scroll:Dock(FILL)
	self.scroll:DockMargin(0, S(14), 0, 0)
	Sanctions.Defilement(self.scroll)

	Sanctions.Liste(self.scroll, self.dossiers, {
		compte = true,
		survol = self.apercu.survol,
		clic = function(dossier)
			-- Une seule requête en vol : le refus qui revient doit être celui de l'écran qui l'attend.
			if (self.apercu.fige or self.enCours) then return end

			Sanctions.depuisJournal = {journal = self, steamid64 = dossier.steamid64, jusqu = CurTime() + 10}
			Sanctions.Agir("Ouvrir", {steamid64 = dossier.steamid64})
		end
	})

	if (defilement > 0 and !self.apercu.fige) then
		timer.Simple(0, function()
			if (IsValid(self.scroll)) then
				self.scroll:GetVBar():SetScroll(defilement)
			end
		end)
	end

	if (IsValid(self.popup)) then
		self.popup:MoveToFront()
	end
end

--- Les filtres ont-ils bougé depuis la dernière réponse ? Si oui, on repart de la première page.
function PANEL:Filtrer()
	for cle, valeur in pairs(self.filtres) do
		if (valeur != self.appliques[cle]) then
			return self:Charger(0)
		end
	end
end

--- `avant` est l'id du plus ancien dossier déjà reçu, ou 0 pour une première page.
---@param avant integer
function PANEL:Charger(avant)
	if (self.apercu.fige) then return end

	if (self.enCours) then
		self.relance = avant == 0 or nil

		return
	end

	self.avant, self.enCours, self.refus = avant, true, nil
	self.envoyes = table.Copy(self.filtres)

	Sanctions.Agir("Journal", {
		sanction = self.filtres.sanction, type = self.filtres.type, moderateur = self.filtres.moderateur,
		compte = self.filtres.compte, avant = avant
	})
	self:Actualiser()

	-- Ni réponse ni refus sur un échec MySQL ou un serveur qui hiberne : la lecture ne reste pas bloquée.
	timer.Create("sanctionsJournalGarde", 10, 1, function()
		if (IsValid(self) and self.enCours) then
			self.refus, self.enCours = "Le serveur ne répond pas.", nil
			self:Actualiser()
			self:Relancer()
		end
	end)
end

---@param recu SanctionsJournalRecu
function PANEL:Recevoir(recu)
	if (!self.enCours or recu.avant != self.avant) then return end

	self.enCours, self.charge, self.appliques = nil, true, self.envoyes

	local vus = {}

	if (self.avant == 0) then
		self.dossiers = {}
	end

	for _, dossier in ipairs(self.dossiers) do
		vus[dossier.id] = true
	end

	for _, dossier in ipairs(recu.dossiers or {}) do
		if (!vus[dossier.id]) then
			self.dossiers[#self.dossiers + 1] = dossier
		end
	end

	self.suite = recu.suite
	self:Reconstruire(self.avant > 0)
	self:Actualiser()
	self:Relancer()
end

--- Un filtre changé pendant une lecture attend sa réponse : deux requêtes de même curseur ne se distinguent pas.
function PANEL:Relancer()
	timer.Remove("sanctionsJournalGarde")

	if (self.relance) then
		self.relance = nil
		self:Filtrer()
	end
end

function PANEL:Actualiser()
	local n = #self.dossiers
	local texte = "Tous les comptes · " .. n .. (self.suite and " dossiers affichés" or (n > 1 and " dossiers" or " dossier"))

	self.sousTitre = Sanctions.Espacer(theme().upper(texte), K.Role("micro"), 2)
	self.titre = K.Fit("Journal des sanctions", self.policeNom, S(WIDTH - 200))

	if (self.refus) then
		self.raison = self.refus
	elseif (self.enCours) then
		self.raison = "Chargement…"
	else
		self.raison = self.suite and "Cliquer une ligne ouvre le dossier du compte." or "Fin du journal."
	end

	if (self.enCours) then
		self.plusAncien.reason = "Chargement…"
	else
		self.plusAncien.reason = !self.suite and "Fin du journal." or nil
	end

	self:PlaceVerbs()
end

--- Un verbe du pied : du texte nu, doré, grisé quand `reason` est posée.
function PANEL:Verbe(label, bAccent)
	local button = K.ActionButton(self, label, "ghost", function()
		self:Charger(self.dossiers[#self.dossiers].id)
	end)

	button:SetTall(S(40))
	button.Paint = function(verbe, width, height)
		local col = theme().col
		local ink = bAccent and col.accent or col.text2

		if (verbe.reason) then
			ink = col.text3
		elseif (verbe:IsHovered()) then
			ink = col.textTitle
		end

		draw.SimpleText(verbe.text, verbe.font, width / 2, height / 2, ink, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	return button
end

function PANEL:PlaceVerbs()
	self.plusAncien:SetPos(S(WIDTH - 40) - self.plusAncien:GetWide(), self:GetTall() - S(28 + 40))
end

function PANEL:Think()
	-- Un clic hors de la liste ouverte la referme, comme une liste du système.
	local bClic = input.IsMouseDown(MOUSE_LEFT)

	if (bClic and !self.bClic and self.ouverte and !self.popup:IsHovered() and !self.ouverte:IsHovered()) then
		self:Ouvrir(nil)
	end

	self.bClic = bClic
end

function PANEL:OnKeyCodePressed(key)
	if (key == KEY_ESCAPE) then
		self:Remove()
	end
end

function PANEL:Paint(width, height)
	local col = theme().col
	local skin = VALDERAAN.MenuSkin
	local inset = S(2)

	if (!skin.BoiteFond(inset, inset, width - inset * 2, height - inset * 2)) then
		ix.util.DrawBlur(self, 10)
		surface.SetDrawColor(col.surfaceGlass)
		surface.DrawRect(inset, inset, width - inset * 2, height - inset * 2)
	end

	skin.Boite(0, 0, width, height, S(CORNER))

	draw.SimpleText(self.titre, self.policeNom, S(40), S(47), col.textTitle, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	Sanctions.PoserEspace(self.sousTitre, K.Role("micro"), S(40), S(78), col.text3)
	skin.TraitBoite(S(40), S(106), width - S(80), true)
	skin.TraitBoite(S(40), height - S(80), width - S(80), true)

	if (self.charge and #self.dossiers == 0) then
		draw.SimpleText("Aucun dossier ne correspond.", K.Role("textIt"), width / 2, S(255), col.text3, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

	draw.SimpleText(self.raison, K.Role("textIt"), S(40), height - S(48), self.refus and col.danger or col.textNotes,
		TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
end

vgui.Register("valSanctionsJournal", PANEL, "EditablePanel")

--- Une fenêtre à la fois : un second `!sanctions` repart d'une page neuve.
function Sanctions.OuvrirJournal()
	local staff = Sanctions.fenetre

	-- Un journal caché appartient à la fenêtre staff ouverte : elle part avec lui (`OnRemove`).
	if (IsValid(staff) and staff.journal == Sanctions.journal) then
		staff:Remove()
	elseif (IsValid(Sanctions.journal)) then
		Sanctions.journal:Remove()
	end

	local fenetre = vgui.Create("valSanctionsJournal") --[[@as valSanctionsJournal]]

	fenetre:SetKeyboardInputEnabled(true)
	fenetre:MakePopup()
	fenetre:Setup()
	Sanctions.journal = fenetre
end

hook.Add("SanctionsJournal", "sanctionsJournal", function(recu)
	if (IsValid(Sanctions.journal)) then
		Sanctions.journal:Recevoir(recu)
	end
end)

-- Le refus de la lecture en cours reste dans le pied : une liste déjà chargée n'est pas vidée pour autant.
hook.Add("SanctionsRefus", "sanctionsJournal", function(raison)
	local fenetre = Sanctions.journal

	if (!IsValid(fenetre) or !fenetre.enCours) then return end

	fenetre.refus, fenetre.enCours = raison, nil
	fenetre:Actualiser()
	fenetre:Relancer()

	return true
end)

local function quand(jour, mois, heure, minute)
	return os.time({year = 2026, month = mois, day = jour, hour = heure or 20, min = minute or 0})
end

--- Les cinq dossiers de la maquette, tous comptes confondus.
local function dossiersEssai()
	return {
		{id = 5, steamid64 = "76561198056689597", perso_nom = "Aldric Verne", type = "freekill", sanction = "temporaire",
			fin = quand(20, 11, 21, 4), debut = quand(17, 11, 21, 4), cree_le = quand(17, 11, 21, 4), auteur_nom = "Elrond", annulee = false,
			texte = "A abattu trois villageois à la sortie de la taverne, sans la moindre scène."},
		{id = 4, steamid64 = "76561198040000001", perso_nom = "Sélène Arvel", type = "hrp_vocal", sanction = "aucune",
			debut = quand(17, 11, 19), cree_le = quand(17, 11, 19), auteur_nom = "Galadh", annulee = false,
			texte = "Parlait de son match de foot en vocal de proximité pendant une audience."},
		{id = 3, steamid64 = "76561198011223344", type = "glitch_exploit", sanction = "definitive",
			debut = quand(16, 11, 22), cree_le = quand(16, 11, 22), auteur_nom = "Elrond", annulee = false,
			texte = "Duplication d'objets par la fenêtre d'échange, signalée par trois témoins."},
		{id = 2, steamid64 = "76561198056689597", perso_nom = "Gorm le Rouge", type = "metagaming", sanction = "temporaire",
			fin = quand(14, 11, 21, 4), debut = quand(12, 11, 21, 4), cree_le = quand(12, 11, 21, 4), auteur_nom = "Elrond", annulee = false,
			texte = "A utilisé le nom d'un assassin appris sur Discord pour le dénoncer en jeu."},
		{id = 1, steamid64 = "76561198040000002", perso_nom = "Mira Tal", type = "insulte", sanction = "aucune",
			debut = quand(9, 11), cree_le = quand(9, 11), auteur_nom = "Mirwen", annulee = true,
			texte = "Insulte en message privé, retirée : le joueur visé jouait la scène."}
	}
end

K.Vue("sanctions_journal", {WIDTH, HEIGHT}, function(parent, data)
	local fenetre = parent:Add("valSanctionsJournal") --[[@as valSanctionsJournal]]

	data.fige = true
	fenetre:Setup(data)
end, {
	vide = function()
		return {dossiers = {}, filtres = {sanction = "", type = "freekill", moderateur = "Mirwen", compte = ""}}
	end,
	page = function() return {dossiers = dossiersEssai(), suite = true, survol = 2} end,
	filtre = function()
		local dossiers = dossiersEssai()

		return {dossiers = {dossiers[4]}, filtres = {sanction = "bannissement", type = "", moderateur = "", compte = "gorm"}}
	end
})
