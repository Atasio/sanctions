-- Chantier sanctions, tâche 3 : ULib appliqué par le plugin, et ses ban / unban directs rattrapés. Faux comptes.
return {
	contenu = true,
	delai = 40,
	run = function(Banc)
		local Sanctions = VALDERAAN.Sanctions
		local acteur = {steamid64 = "76561190000000001", nom = "Banc"}
		local C = {}

		for i = 1, 5 do
			C[i] = util.SteamIDTo64("STEAM_0:1:9999990" .. i)
		end

		local function sid(i) return util.SteamIDFrom64(C[i]) end

		local function attendre(lancer)
			local fini, a, b = false, nil, nil

			lancer(function(x, y) fini, a, b = true, x, y end)
			Banc.AttendreQue(function() return fini end, 5)

			return a, b
		end

		local function dossiers(i)
			return attendre(function(fin) Sanctions.DossiersDe(C[i], fin) end)
		end

		local function journal(id)
			return attendre(function(fin)
				local query = mysql:Select("val_sanctions_journal")
					query:Where("sanction_id", id)
					query:OrderByAsc("id")
					query:Callback(function(rows) fin(istable(rows) and rows or {}) end)
				query:Execute()
			end)
		end

		-- ULib vidé à la main : passer par ULib.unban ferait rattraper le nettoyage par le plugin.
		Banc.Defaire(function()
			for i = 1, #C do
				ULib.bans[sid(i)] = nil
				sql.Query("DELETE FROM ulib_bans WHERE steamid=" .. C[i])

				for _, dossier in ipairs(dossiers(i)) do
					local query = mysql:Delete("val_sanctions_journal")
						query:Where("sanction_id", dossier.id)
					query:Execute()
				end

				local query = mysql:Delete("val_sanctions")
					query:Where("steamid64", C[i])
				query:Execute()
			end
		end)

		local maintenant = os.time()
		local temp = attendre(function(fin)
			Sanctions.Creer(acteur, C[1], {type = "freekill", texte = "Trois jours", sanction = "temporaire", jours = 3}, fin)
		end)
		local entree = ULib.bans[sid(1)]

		Banc.Verifier(1, entree and math.abs(entree.unban - (maintenant + 3 * Sanctions.JOUR)) <= 120 and #dossiers(1) == 1,
			"temporaire 3 j : ULib jusqu'à +3 j, un seul dossier (écart " .. tostring(entree and entree.unban - maintenant - 3 * Sanctions.JOUR) .. " s, " .. #dossiers(1) .. " dossier)")

		attendre(function(fin) Sanctions.Modifier(acteur, temp.id, {jours = 1}, fin) end)
		entree = ULib.bans[sid(1)]
		local lignes = journal(temp.id)

		Banc.Verifier(2, entree and math.abs(entree.unban - (temp.debut + Sanctions.JOUR)) <= 120 and lignes[#lignes].action == "modification",
			"ramené à 1 j : ULib jusqu'à debut + 1 j (écart " .. tostring(entree and entree.unban - temp.debut - Sanctions.JOUR) .. " s)")

		local def = attendre(function(fin)
			Sanctions.Creer(acteur, C[2], {type = "insulte", texte = "Définitif", sanction = "definitive"}, fin)
		end)
		local posee = ULib.bans[sid(2)] != nil

		attendre(function(fin) Sanctions.Annuler(acteur, def.id, fin) end)

		Banc.Verifier(3, posee and ULib.bans[sid(2)] == nil and dossiers(2)[1].annulee,
			"annulé : l'entrée ULib part (posée " .. tostring(posee) .. ", reste " .. tostring(ULib.bans[sid(2)] != nil) .. ")")

		local premier = attendre(function(fin)
			Sanctions.Creer(acteur, C[3], {type = "glitch_exploit", texte = "Premier", sanction = "definitive"}, fin)
		end)
		local second = attendre(function(fin)
			Sanctions.Creer(acteur, C[3], {type = "metagaming", texte = "Second", sanction = "temporaire", jours = 5}, fin)
		end)
		local relu = attendre(function(fin) Sanctions.Lire(premier.id, fin) end)
		lignes = journal(premier.id)
		local remplacement = lignes[#lignes]
		local apres = remplacement and util.JSONToTable(remplacement.apres) or {}
		entree = ULib.bans[sid(3)]

		Banc.Verifier(4, Sanctions.Etat(relu, os.time()) == "leve" and remplacement.action == "remplacement" and tonumber(apres.remplace_par) == second.id
			and entree and entree.reason:find("#" .. second.id, 1, true) != nil,
			"deux bans : le premier remplacé par le second, ULib porte le second (" .. tostring(entree and entree.reason) .. ")")

		ULib.addBan(sid(4), 90, "Motif direct", "Joueur du banc", "Modo(STEAM_0:1:12345)")
		Banc.Attendre(0.5)
		local rattrape = dossiers(4)[1]

		Banc.Verifier(5, rattrape and rattrape.type == "autre" and rattrape.sanction == "temporaire" and rattrape.jours == 1
			and rattrape.texte == "Motif direct" and rattrape.auteur_steamid64 == util.SteamIDTo64("STEAM_0:1:12345"),
			"ban direct de 90 min : dossier autre de 1 j (" .. (rattrape and (rattrape.sanction .. ", " .. tostring(rattrape.jours) .. " j, " .. rattrape.auteur_nom) or "aucun") .. ")")

		ULib.unban(sid(1))
		Banc.Attendre(0.5)
		relu = attendre(function(fin) Sanctions.Lire(temp.id, fin) end)
		lignes = journal(temp.id)

		Banc.Verifier(6, relu.levee_le != nil and lignes[#lignes].action == "levee",
			"unban direct : dossier levé, entrée levee (" .. tostring(lignes[#lignes].action) .. ")")

		local fini = attendre(function(fin)
			Sanctions.Creer(acteur, C[5], {type = "freekill", texte = "Fini", sanction = "temporaire", jours = 3, debut = os.time() - 10 * Sanctions.JOUR}, fin)
		end)

		ULib.unban(sid(5))
		Banc.Attendre(0.5)
		relu = attendre(function(fin) Sanctions.Lire(fini.id, fin) end)

		Banc.Verifier(7, relu.levee_le == nil and #journal(fini.id) == 1 and Sanctions.Etat(relu, os.time()) == "termine",
			"unban sans ban actif : rien ne change (" .. Sanctions.Etat(relu, os.time()) .. ", " .. #journal(fini.id) .. " entrée)")
	end
}
