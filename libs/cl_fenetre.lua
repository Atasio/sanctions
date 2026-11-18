--[[
	cl_fenetre.lua — La fenêtre staff d'un compte (maquette `ui_maquette/sanctions_staff.html`) : le dossier avec ses
	actions, puis le formulaire d'une sanction neuve ou modifiée, et sa vue de capture `sanctions_fenetre`.

	Elle n'envoie que des intentions et attend le dossier que le serveur renvoie après chaque écriture. Une seule à la fois.
--]]

VALDERAAN = VALDERAAN or {}
VALDERAAN.Sanctions = VALDERAAN.Sanctions or {}

local Sanctions = VALDERAAN.Sanctions

---@class UIKit
local K = VALDERAAN.UI

local WIDTH, CORNER, LIST_HEIGHT = 900, 38, 560
local FIELD_TOP, FIELD_WIDTH, FIELD_HEIGHT = 130, 400, 38
local OPTION_HEIGHT, OPTION_PAD = 34, 10
local TEXT_HEIGHT = 120

local function theme()
	return VALDERAAN.MenuTheme
end

local function S(n)
	return K.Scale(n)
end

-- `cl_liste` charge après ce fichier : ses helpers ne se lisent qu'au runtime.
local function espacer(texte, police, espace)
	return Sanctions.Espacer(theme().upper(texte), police, espace)
end

local function poserEspace(...)
	Sanctions.PoserEspace(...)
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

---@class valSanctionsFenetre : EditablePanel
---@field recu SanctionsDossierRecu
---@field dossier SanctionDossier? le dossier modifié ; nil pour une sanction neuve
local PANEL = {}

--- `apercu` ne sert qu'à la vue de capture : la souris en est écartée, ses survols sont donc posés à la main.
---@param recu SanctionsDossierRecu
---@param apercu table?
function PANEL:Setup(recu, apercu)
	self.apercu = apercu or {}
	self.policeNom = K.Font("Cinzel", S(24), 600)
	self:SetWide(S(WIDTH))
	self:Remplir(recu)
end

function PANEL:Remplir(recu)
	local noms = {}

	for _, perso in ipairs(recu.personnages or {}) do
		noms[#noms + 1] = perso.nom
	end

	local bEcriture = self.enCours

	self.recu, self.enCours = recu, nil
	self.nom = K.Fit(recu.nomSteam or util.SteamIDFrom64(recu.steamid64), self.policeNom, S(380))
	self.sid = espacer(util.SteamIDFrom64(recu.steamid64) .. " · " .. recu.steamid64, K.Role("micro"), 2)
	self.persosTitre = espacer("Personnages", K.Role("micro"), 3)
	self.persos = #noms > 0 and K.Fit(table.concat(noms, " · "), K.Role("small"), S(400)) or "Aucun personnage"

	-- Un dossier qui ne répond pas à une écriture d'ici (un second `!sanctions`) ne jette pas la saisie en cours.
	if (bEcriture or !IsValid(self.envoi)) then
		self:MontrerListe()
	end
end

--- Le corps couvre la fenêtre ; il est refait à chaque changement de vue, la croix reste au-dessus.
function PANEL:NouveauCorps(hauteur)
	if (IsValid(self.corps)) then
		self.corps:Remove()
	end

	self.ouverte, self.envoi, self.dureeCadre = nil, nil, nil
	self:SetTall(S(hauteur))
	self.corps = self:Add("Panel")
	self.corps:SetSize(self:GetWide(), self:GetTall())
	self:BuildClose()

	if (!self.apercu.fige) then
		self:Center()
	end

	return self.corps
end

function PANEL:BuildClose()
	if (IsValid(self.close)) then
		self.close:MoveToFront()

		return
	end

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

function PANEL:MontrerListe()
	local dossiers = self.recu.dossiers or {}
	local corps = self:NouveauCorps(LIST_HEIGHT)
	local zone = corps:Add("Panel")

	self.dossier = nil
	self.titreDroite = nil
	self.refus = nil
	zone:SetPos(S(40), S(108))
	zone:SetSize(S(820), S(LIST_HEIGHT - 108 - 88))

	K.Rule(zone, #dossiers == 0 and "Dossier vierge" or ("Dossier · " .. #dossiers .. (#dossiers > 1 and " sanctions" or " sanction")))

	local scroll = zone:Add("DScrollPanel")

	scroll:Dock(FILL)
	scroll:DockMargin(0, S(14), 0, 0)
	Sanctions.Defilement(scroll)

	Sanctions.Liste(scroll, dossiers, {
		actions = true,
		survol = self.apercu.survol,
		OnModifier = function(dossier) self:MontrerFormulaire(dossier) end,
		OnAnnuler = function(dossier) self:ConfirmerAnnulation(dossier) end
	})

	local nouvelle = self:Verbe("Nouvelle sanction", true)

	nouvelle.DoClick = function()
		self:MontrerFormulaire()
	end

	self.verbes = {nouvelle}
	self:PlaceVerbs()
end

--- Le formulaire, vide ou prérempli d'un dossier. Sa hauteur suit la ligne de durée, qui n'existe qu'en temporaire.
---@param dossier SanctionDossier?
function PANEL:MontrerFormulaire(dossier)
	local apercu = self.apercu.saisie or {}
	local corps = self:NouveauCorps(LIST_HEIGHT)

	self.dossier = dossier
	self.refus = nil
	self.titreDroite = espacer(dossier and "Modifier la sanction" or "Nouvelle sanction", K.Role("caption"), 3)
	self.saisie = {
		type = apercu.type or (dossier and dossier.type) or Sanctions.TYPES[1].id,
		sanction = apercu.sanction or (dossier and dossier.sanction) or "aucune"
	}

	-- Le serveur refuse de toucher la sanction d'un dossier levé ou terminé : seuls le type et le texte bougent.
	local etat = dossier and Sanctions.Etat(dossier, os.time())

	self.bSanctionFigee = etat == "leve" or etat == "termine"

	self:Deroulante(corps, 40, "Infraction", Sanctions.TYPES, "type")
	self:Deroulante(corps, 460, "Sanction", Sanctions.SANCTIONS, "sanction")

	self.dureeCadre = corps:Add("Panel")
	self.dureeCadre:SetSize(S(96), S(FIELD_HEIGHT))
	self.jours = K.TextEntry(self.dureeCadre, tostring(apercu.jours or (dossier and dossier.jours) or 1), S(FIELD_HEIGHT))
	self.jours:SetNumeric(true)
	self.jours:SetEditable(!self.bSanctionFigee)
	self.jours:GetParent():Dock(FILL)
	fermerSurEchap(self.jours, self)

	self.regle = corps:Add("Panel")
	self.regle:SetSize(S(820), S(40))
	K.Rule(self.regle, "Description")

	self.texteCadre = corps:Add("Panel")
	self.texteCadre:SetSize(S(820), S(TEXT_HEIGHT))
	self.texte = K.TextArea(self.texteCadre, apercu.texte or (dossier and dossier.texte) or "", S(TEXT_HEIGHT), Sanctions.TEXTE_MAX)
	self.texte:GetParent():Dock(FILL)
	fermerSurEchap(self.texte, self)

	local peindreTexte = self.texte.Paint

	self.texte.Paint = function(entry, width, height)
		peindreTexte(entry, width, height)

		if (self.texteVide) then
			draw.SimpleText("Ce qui s'est passé, ce qui a été vu ou entendu.", K.Role("textIt"), 3, 2, theme().col.text3)
		end
	end

	local retour = self:Verbe("Retour", false)

	retour.DoClick = function()
		self:MontrerListe()
	end

	self.envoi = self:Verbe("", true)
	self.envoi.DoClick = function(button)
		if (!button.reason) then
			self:Envoyer()
		end
	end

	self.verbes = {retour, self.envoi}
	self.popup = self:Choix(corps)
	self:Actualiser()

	-- ⚠️ Pendant une capture `valderaan_ui`, `ScrH()` vaut la hauteur de la cible de rendu : un `Actualiser` relancé par
	-- `Think` y poserait tout à l'échelle 0,9. Il ne repart donc que d'un vrai changement.
	self.dernierTexte, self.derniersJours = self.texte:GetText(), self.jours:GetText()

	if (apercu.ouverte) then
		self:Ouvrir(self.deroulantes[apercu.ouverte])
	end
end

function PANEL:Deroulante(corps, x, libelle, options, cle)
	local field = corps:Add("Panel")

	field:SetPos(S(x), S(FIELD_TOP))
	field:SetSize(S(FIELD_WIDTH), S(FIELD_HEIGHT))
	field.bFige = cle == "sanction" and self.bSanctionFigee
	field:SetCursor(field.bFige and "arrow" or "hand")
	field.options, field.cle = options, cle
	field.trace = espacer(libelle, K.Role("micro"), 3)
	field.Paint = function(_, width, height)
		local col = theme().col
		local bOuvert = self.ouverte == field

		surface.SetDrawColor(bOuvert and col.accent or col.lineSoft)
		surface.DrawOutlinedRect(0, 0, width, height)
		poserEspace(field.trace, K.Role("micro"), S(12), height / 2, col.text2)
		draw.SimpleText(libelleDe(options, self.saisie[cle]), K.Role("text"), S(148), height / 2,
			field.bFige and col.text3 or col.textTitle, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		if (field.bFige) then return end

		-- ⚠️ ValderaanIcons n'a pas de chevron : le triangle d'EB Garamond en tient lieu (Cinzel n'en a pas).
		draw.SimpleText("▼", K.Role("small"), width - S(12), height / 2, bOuvert and col.accent or col.text2,
			TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end
	field.OnMousePressed = function()
		if (field.bFige) then return end

		self:Ouvrir(self.ouverte != field and field or nil)
	end

	self.deroulantes = self.deroulantes or {}
	self.deroulantes[cle] = field
end

-- La liste ouverte d'une déroulante : la boîte flottante d'EDGE, posée par-dessus la description.
function PANEL:Choix(corps)
	local popup = corps:Add("Panel")

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
			local bSurvol = self.apercu.survolOption == option.id
				or (panel:IsHovered() and mouseY >= top and mouseY < top + S(OPTION_HEIGHT))
			local ink = col.text1

			if (bSurvol) then
				skin.Selection(S(2), top, width - S(4), S(OPTION_HEIGHT), 0.6, false)
				ink = col.textTitle
			elseif (option.id == self.saisie[field.cle]) then
				ink = col.accent
			end

			draw.SimpleText(option.libelle, K.Role("text"), S(20), top + S(OPTION_HEIGHT) / 2, ink, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		end
	end
	popup.OnMousePressed = function(panel)
		local field = self.ouverte
		local _, mouseY = panel:CursorPos()
		local option = field and field.options[math.floor((mouseY - S(OPTION_PAD)) / S(OPTION_HEIGHT)) + 1]

		if (option) then
			self.saisie[field.cle] = option.id
			self:Actualiser()
		end

		self:Ouvrir(nil)
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

--- Ce que le formulaire enverrait, ou la raison qui éteint le verbe. Le serveur revalide tout.
---@return table? intention
---@return string? raison
function PANEL:LireSaisie()
	local saisie = self.saisie
	local texte = string.Trim(self.texte:GetText())
	local jours = tonumber(self.jours:GetText())

	if (texte == "") then
		return nil, "Décrivez le cas."
	end

	if (saisie.sanction == "temporaire"
		and (!jours or jours != math.floor(jours) or jours < Sanctions.JOURS_MIN or jours > Sanctions.JOURS_MAX)) then
		return nil, "Une durée de " .. Sanctions.JOURS_MIN .. " à " .. Sanctions.JOURS_MAX .. " jours."
	end

	local voulu = {type = saisie.type, texte = texte, sanction = saisie.sanction, jours = saisie.sanction == "temporaire" and jours or nil}

	if (!self.dossier) then
		voulu.steamid64 = self.recu.steamid64

		return voulu
	end

	-- Une modification n'envoie que ce qui a bougé : le journal du dossier n'en garde que le diff.
	local diff, bChange = {id = self.dossier.id}, false

	for _, cle in ipairs(Sanctions.CHAMPS_MODIFIABLES) do
		local actuel = self.dossier[cle]

		if (cle == "texte") then
			actuel = string.Trim(actuel or "")
		end

		if (voulu[cle] != nil and voulu[cle] != actuel) then
			diff[cle], bChange = voulu[cle], true
		end
	end

	if (!bChange) then
		return nil, "Rien n'a changé."
	end

	return diff
end

-- L'échéance qu'aurait le bannissement : un dossier qui bannissait déjà garde son début, sinon il part d'aujourd'hui.
function PANEL:Echeance(jours)
	local debut = self.apercu.maintenant or os.time()

	if (self.dossier and self.dossier.sanction != "aucune") then
		debut = self.dossier.debut
	end

	return debut + jours * Sanctions.JOUR
end

function PANEL:LibelleEnvoi()
	if (self.dossier) then
		return "Enregistrer"
	elseif (self.saisie.sanction == "aucune") then
		return "Poser l'avertissement"
	elseif (self.saisie.sanction == "definitive") then
		return "Bannir définitivement"
	end

	local jours = tonumber(self.jours:GetText())

	return (jours and jours >= 1) and ("Bannir " .. Sanctions.Jours(jours)) or "Bannir"
end

--- Recalcule ce qui dépend de la saisie : la place de la durée, la hauteur, le verbe et sa raison.
function PANEL:Actualiser()
	local bDuree = self.saisie.sanction == "temporaire"
	local haut = bDuree and 238 or 184	local hauteur = haut + 40 + TEXT_HEIGHT + 24 + 80

	self.dureeCadre:SetVisible(bDuree)
	self.dureeCadre:SetPos(S(40), S(184))
	self.regle:SetPos(S(40), S(haut - 10))
	self.texteCadre:SetPos(S(40), S(haut + 40))

	if (self:GetTall() != S(hauteur)) then
		self:SetTall(S(hauteur))
		self.corps:SetTall(self:GetTall())

		if (!self.apercu.fige) then
			self:Center()
		end
	end

	local _, raison = self:LireSaisie()
	local jours = tonumber(self.jours:GetText())
	local libelle = theme().upper(self:LibelleEnvoi())

	self.texteVide = self.texte:GetText() == ""
	self.echeance = (bDuree and jours and jours >= Sanctions.JOURS_MIN and jours <= Sanctions.JOURS_MAX)
		and ("jusqu'au " .. Sanctions.DateHeure(self:Echeance(jours))) or nil

	if (self.enCours) then
		raison = "Envoi en cours…"
	end

	self.envoi.reason = raison

	if (self.envoi.text != libelle) then
		self.envoi.text = libelle
		surface.SetFont(self.envoi.font)
		self.envoi:SetWide(surface.GetTextSize(libelle) + S(12))
	end

	self:PlaceVerbs()
end

function PANEL:Envoyer()
	local intention = self:LireSaisie()

	if (!intention) then return end

	local action = self.dossier and "Modifier" or "Creer"
	local sanction = intention.sanction or self.dossier.sanction
	local bBannit = sanction != "aucune" and (action == "Creer" or intention.sanction != nil or intention.jours != nil)
	local bLeve = self.dossier and sanction == "aucune" and Sanctions.BannitEncore(self.dossier, os.time())

	local function envoyer()
		if (!IsValid(self) or self.enCours) then return end

		self.refus, self.enCours = nil, true
		Sanctions.Agir(action, intention)

		if (IsValid(self.envoi)) then
			self:Actualiser()
		end
	end

	if (bLeve) then
		return VALDERAAN.Confirm({
			title = "Lever le bannissement ?",
			text = self.nom .. " pourra de nouveau se connecter. Le dossier reste, en avertissement.",
			confirm = "Lever",
			OnConfirm = envoyer
		})
	elseif (!bBannit) then
		return envoyer()
	end

	local jours = intention.jours or (self.dossier and self.dossier.jours)

	VALDERAAN.Confirm({
		title = sanction == "definitive" and "Bannir définitivement ?" or ("Bannir " .. Sanctions.Jours(jours) .. " ?"),
		text = sanction == "definitive"
			and (self.nom .. " ne pourra plus se connecter. Le bannissement se lève depuis ce dossier, en l'annulant.")
			or (self.nom .. " ne pourra plus se connecter jusqu'au " .. Sanctions.DateHeure(self:Echeance(jours)) .. "."),
		confirm = "Bannir",
		OnConfirm = envoyer
	})
end

---@param dossier SanctionDossier
function PANEL:ConfirmerAnnulation(dossier)
	local bBannit = Sanctions.BannitEncore(dossier, os.time())

	VALDERAAN.Confirm({
		title = "Annuler ce dossier ?",
		text = "Il reste au dossier, barré." .. (bBannit and " Le bannissement en cours est levé." or ""),
		confirm = "Annuler le dossier",
		cancel = "Garder",
		OnConfirm = function()
			if (!IsValid(self) or self.enCours) then return end

			self.refus, self.enCours = nil, true
			Sanctions.Agir("Annuler", {id = dossier.id})
		end
	})
end

--- Un verbe du pied : du texte nu, doré pour l'action principale, grisé quand `reason` est posée.
function PANEL:Verbe(label, bAccent)
	local button = K.ActionButton(self.corps, label, "ghost", function() end)

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

--- Aligne les verbes à droite du pied, le dernier contre le bord.
function PANEL:PlaceVerbs()
	local x = S(WIDTH - 40)
	local y = self:GetTall() - S(28 + 40)

	for rang = #self.verbes, 1, -1 do
		x = x - self.verbes[rang]:GetWide()
		self.verbes[rang]:SetPos(x, y)
		x = x - S(28)
	end
end

function PANEL:Think()
	if (!IsValid(self.envoi)) then return end

	local texte, jours = self.texte:GetText(), self.jours:GetText()

	if (texte != self.dernierTexte or jours != self.derniersJours) then
		self.dernierTexte, self.derniersJours = texte, jours
		self:Actualiser()
	end

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

	draw.SimpleText(self.nom, self.policeNom, S(40), S(47), col.textTitle, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	poserEspace(self.sid, K.Role("micro"), S(40), S(78), col.text3)

	if (self.titreDroite) then
		poserEspace(self.titreDroite, K.Role("caption"), S(WIDTH - 96), S(47), col.textNotes, true)
	else
		poserEspace(self.persosTitre, K.Role("micro"), S(WIDTH - 96), S(41), col.text2, true)
		draw.SimpleText(self.persos, K.Role("small"), S(WIDTH - 96), S(65), col.textNotes, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	skin.TraitBoite(S(40), S(106), width - S(80), true)
	skin.TraitBoite(S(40), height - S(80), width - S(80), true)

	local raison, bFaute = self.refus, self.refus != nil

	if (!raison and IsValid(self.envoi)) then
		raison = self.envoi.reason
	end

	if (raison) then
		draw.SimpleText(raison, K.Role("textIt"), S(40), height - S(48), bFaute and col.danger or col.textNotes,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	-- La durée n'a pas de libellé à elle : le mot « jours » et l'échéance qu'elle donnerait.
	if (IsValid(self.dureeCadre) and self.dureeCadre:IsVisible()) then
		local x, y = self.dureeCadre:GetPos()
		local cy = y + self.dureeCadre:GetTall() / 2

		x = x + self.dureeCadre:GetWide() + S(12)

		local largeur = draw.SimpleText("jours", K.Role("text"), x, cy, self.bSanctionFigee and col.text3 or col.text1,
			TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

		if (self.echeance) then
			draw.SimpleText(self.echeance, K.Role("textIt"), x + largeur + S(24), cy, col.textNotes, TEXT_ALIGN_LEFT,
				TEXT_ALIGN_CENTER)
		end
	end
end

vgui.Register("valSanctionsFenetre", PANEL, "EditablePanel")

--- Une fenêtre à la fois : un dossier reçu pour le compte qu'elle montre la remplit (retour à la liste après une
--- écriture), un autre la remplace.
---@param recu SanctionsDossierRecu
local function ouvrir(recu)
	local fenetre = Sanctions.fenetre

	if (IsValid(fenetre) and fenetre.recu.steamid64 == recu.steamid64) then
		return fenetre:Remplir(recu)
	end

	if (IsValid(fenetre)) then
		fenetre:Remove()
	end

	fenetre = vgui.Create("valSanctionsFenetre") --[[@as valSanctionsFenetre]]
	fenetre:SetKeyboardInputEnabled(true)
	fenetre:MakePopup()
	fenetre:Setup(recu)
	Sanctions.fenetre = fenetre
end

hook.Add("SanctionsDossier", "sanctionsFenetre", function(recu)
	if (recu.peutGerer and !recu.mien) then
		ouvrir(recu)
	end
end)

-- La fenêtre ne prend que le refus de sa propre écriture : celui d'un `Mien` revient à l'onglet.
hook.Add("SanctionsRefus", "sanctionsFenetre", function(raison)
	local fenetre = Sanctions.fenetre

	if (!IsValid(fenetre) or !fenetre.enCours) then return end

	fenetre.refus, fenetre.enCours = raison, nil

	if (IsValid(fenetre.envoi)) then
		fenetre:Actualiser()
	end

	return true
end)

local function recuEssai()
	return {
		steamid64 = "76561198056689597", nomSteam = "Gorm_42", peutGerer = true, dossiers = Sanctions.DossiersEssai(),
		personnages = {{id = 1, nom = "Aldric Verne"}, {id = 2, nom = "Mira Tal"}, {id = 3, nom = "Gorm le Rouge"}}
	}
end

local MAINTENANT = os.time({year = 2026, month = 11, day = 17, hour = 21, min = 4})

-- La vue a la hauteur de la liste : un formulaire, plus court, laisse le fond de capture sous lui.
K.Vue("sanctions_fenetre", {WIDTH, LIST_HEIGHT}, function(parent, data)
	local fenetre = parent:Add("valSanctionsFenetre") --[[@as valSanctionsFenetre]]

	fenetre:Setup(recuEssai(), {fige = true, survol = data.survol, saisie = data.saisie, maintenant = MAINTENANT,
		survolOption = data.survolOption})

	if (data.saisie) then
		fenetre:MontrerFormulaire()
	end

	fenetre.refus = data.refus
end, {
	liste = function() return {survol = 2, refus = "Vous n'avez plus accès aux sanctions."} end,
	avertissement = function()
		return {saisie = {type = "hrp_vocal", sanction = "aucune", texte = "", ouverte = "type"}, survolOption = "metagaming"}
	end,
	temporaire = function()
		return {saisie = {type = "freekill", sanction = "temporaire", jours = 3,
			texte = "A abattu trois villageois à la sortie de la taverne, sans la moindre scène."}}
	end,
	definitif = function()
		return {saisie = {type = "insulte", sanction = "definitive",
			texte = "Insultes répétées en vocal envers un joueur, après deux rappels à l'ordre."}}
	end
})
