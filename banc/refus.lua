-- Chantier sanctions, tâche 4 : la porte réseau refuse sans droit, hors bornes, trop vite, et ne lit aucune cible pour `Mien`.
return {
	contenu = true,
	delai = 60,
	run = function(Banc)
		local Sanctions = VALDERAAN.Sanctions
		local CIBLE = util.SteamIDTo64("STEAM_0:1:9999980")

		local joueur = Banc.Bot({nom = "Joueur"})
		local modo = Banc.Bot({nom = "Modo"})

		if (!joueur or !modo) then return Banc.Verifier(0, false, "bots non montés") end

		-- ⚠️ Un bot n'a jamais d'accès ULib (garde de sv_banc_bot) : le droit du modérateur se pose ici.
		local peutGerer, repondre = Sanctions.PeutGerer, Sanctions.Repondre
		local recu = {}

		Sanctions.PeutGerer = function(client) return client == modo or peutGerer(client) end
		Sanctions.Repondre = function(client, genre, contenu) recu[client] = {genre = genre, contenu = contenu} end

		Banc.Defaire(function()
			Sanctions.PeutGerer, Sanctions.Repondre = peutGerer, repondre

			Sanctions.DossiersDe(CIBLE, function(dossiers)
				for _, dossier in ipairs(dossiers) do
					local query = mysql:Delete("val_sanctions_journal")
						query:Where("sanction_id", dossier.id)
					query:Execute()
				end

				local query = mysql:Delete("val_sanctions")
					query:Where("steamid64", CIBLE)
				query:Execute()
			end)
		end)

		local function agir(client, action, intention)
			Banc.Attendre(1.1)
			recu[client] = nil
			Sanctions.Recevoir(client, action, intention)
			Banc.AttendreQue(function() return recu[client] != nil end, 3)

			return recu[client] or {}
		end

		local function lignes()
			local n

			Sanctions.DossiersDe(CIBLE, function(dossiers) n = #dossiers end)
			Banc.AttendreQue(function() return n != nil end, 3)

			return n
		end

		local valide = {steamid64 = CIBLE, type = "hrp_vocal", texte = "Bruit au micro", sanction = "aucune", jours = 0}

		local refus = {}

		for _, action in ipairs({"Creer", "Modifier", "Annuler", "Ouvrir"}) do
			local r = agir(joueur, action, table.Merge(table.Copy(valide), {id = 1}))

			refus[#refus + 1] = (r.genre == "refus" and r.contenu:find("accès", 1, true)) and "refus" or tostring(r.genre)
		end

		Banc.Verifier(1, table.concat(refus, ",") == "refus,refus,refus,refus" and lignes() == 0,
			"joueur sans droit : quatre refus, aucune ligne (" .. table.concat(refus, ",") .. ")")

		local fautifs = {
			{type = "inconnu"},
			{texte = string.rep("a", Sanctions.TEXTE_MAX + 1)},
			{texte = "   "},
			{sanction = "temporaire", jours = 0},
			{sanction = "temporaire", jours = Sanctions.JOURS_MAX + 1},
			{steamid64 = CIBLE:sub(2)}
		}
		local raisons = {}

		for _, faute in ipairs(fautifs) do
			local r = agir(modo, "Creer", table.Merge(table.Copy(valide), faute))
			local ok = r.genre == "refus" and !r.contenu:find("Trop rapide", 1, true)

			raisons[#raisons + 1] = ok and "refus" or (tostring(r.genre) .. ":" .. tostring(r.contenu))
		end

		Banc.Verifier(2, table.concat(raisons, ",") == "refus,refus,refus,refus,refus,refus" and lignes() == 0,
			"six intentions hors bornes refusées (" .. table.concat(raisons, ",") .. ")")

		local premier = agir(modo, "Creer", table.Copy(valide))
		recu[modo] = nil
		Sanctions.Recevoir(modo, "Creer", table.Copy(valide))
		local second = recu[modo] or {}

		Banc.Verifier(3, premier.genre == "dossier" and second.genre == "refus" and lignes() == 1,
			"deux créations à moins d'une seconde : la seconde refusée (" .. tostring(second.contenu) .. ", " .. lignes() .. " ligne)")

		local mien = agir(joueur, "Mien", {steamid64 = CIBLE})

		Banc.Verifier(4, mien.genre == "dossier" and mien.contenu.steamid64 == joueur:SteamID64() and #mien.contenu.dossiers == 0,
			"Mien rend le dossier de l'appelant (" .. tostring(mien.contenu and mien.contenu.steamid64) .. ")")

		local dossier = premier.contenu and premier.contenu.dossiers and premier.contenu.dossiers[1]

		Banc.Verifier(5, dossier and dossier.auteur_steamid64 == modo:SteamID64() and dossier.auteur_nom == modo:SteamName(),
			"l'auteur est l'appelant (" .. tostring(dossier and dossier.auteur_nom) .. ")")

		local groupe = ULib.ucl.groups.moderation
		local present = groupe and table.HasValue(groupe.allow, "ulx sanctions")

		Banc.Verifier(7, present, "« ulx sanctions » dans le groupe moderation (" .. tostring(present) .. ")")
	end
}
