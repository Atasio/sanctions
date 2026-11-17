-- Chantier sanctions, tâche 2 : dossiers et journal, sur un faux compte (aucun joueur, aucun bannissement).
return {
	contenu = true,
	delai = 40,
	run = function(Banc)
		local Sanctions = VALDERAAN.Sanctions
		local CIBLE = "76561190000000042"
		local acteur = {steamid64 = "76561190000000001", nom = "Banc"}

		local function attendre(lancer)
			local fini, a, b = false, nil, nil

			lancer(function(x, y) fini, a, b = true, x, y end)
			Banc.AttendreQue(function() return fini end, 5)

			return a, b
		end

		local function compter(table, cle, valeur)
			return attendre(function(fin)
				local query = mysql:Select(table)
					query:Where(cle, valeur)
					query:Callback(function(rows) fin(istable(rows) and #rows or 0) end)
				query:Execute()
			end)
		end

		Banc.Defaire(function()
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

		local perso = mysql:Insert("ix_characters")
			perso:Insert("id", 999000042)
			perso:Insert("name", "Aldric du banc")
			perso:Insert("steamid", CIBLE)
			perso:Insert("schema", Schema.folder)
		perso:Execute()

		Banc.Defaire(function()
			local query = mysql:Delete("ix_characters")
				query:Where("id", 999000042)
			query:Execute()
		end)

		local cree = attendre(function(fin)
			Sanctions.Creer(acteur, CIBLE, {type = "metagaming", texte = "Premier texte", sanction = "aucune"}, fin)
		end)

		Banc.Verifier(1, cree and cree.id and compter("val_sanctions", "steamid64", CIBLE) == 1 and compter("val_sanctions_journal", "sanction_id", cree.id) == 1,
			"un avertissement : une ligne, une entrée de journal (id " .. tostring(cree and cree.id) .. ")")

		if (!cree or !cree.id) then return end

		attendre(function(fin) Sanctions.Modifier(acteur, cree.id, {texte = "Texte corrigé"}, fin) end)

		local complet = attendre(function(fin) Sanctions.Dossier(CIBLE, fin) end)
		local journal = complet.journal[cree.id] or {}
		local modif = journal[2]

		Banc.Verifier(2, complet.dossiers[1].texte == "Texte corrigé" and modif and modif.action == "modification"
			and modif.avant.texte == "Premier texte" and modif.apres.texte == "Texte corrigé" and table.Count(modif.apres) == 1,
			"modification : avant/après du seul texte (" .. util.TableToJSON(modif and modif.apres or {}) .. ")")

		attendre(function(fin) Sanctions.Annuler(acteur, cree.id, fin) end)

		local refuse, raison = attendre(function(fin) Sanctions.Modifier(acteur, cree.id, {texte = "Après annulation"}, fin) end)
		local relu = attendre(function(fin) Sanctions.Lire(cree.id, fin) end)

		Banc.Verifier(3, relu.annulee and !refuse and relu.texte == "Texte corrigé",
			"annulé, puis modification refusée (" .. tostring(raison) .. ")")

		Banc.Verifier(4, compter("val_sanctions", "steamid64", CIBLE) == 1 and compter("val_sanctions_journal", "sanction_id", cree.id) == 3,
			"toujours une ligne, trois entrées de journal")

		complet = attendre(function(fin) Sanctions.Dossier(CIBLE, fin) end)

		Banc.Verifier(5, #complet.dossiers == 1 and #(complet.journal[cree.id] or {}) == 3 and complet.personnages[1] and complet.personnages[1].nom == "Aldric du banc",
			"Dossier : la ligne, ses trois entrées et le personnage du compte (" .. #complet.personnages .. " perso)")

		local ancien = attendre(function(fin)
			Sanctions.Creer(acteur, CIBLE, {type = "freekill", texte = "Ancien", sanction = "temporaire", jours = 3, debut = os.time() - 10 * Sanctions.JOUR}, fin)
		end)

		local refusDuree = attendre(function(fin) Sanctions.Modifier(acteur, ancien.id, {jours = 30}, fin) end)
		local okTexte = attendre(function(fin) Sanctions.Modifier(acteur, ancien.id, {texte = "Ancien, corrigé", type = "autre"}, fin) end)
		relu = attendre(function(fin) Sanctions.Lire(ancien.id, fin) end)

		Banc.Verifier(6, !refusDuree and okTexte and relu.jours == 3 and relu.type == "autre",
			"terminé : durée refusée, type et texte corrigés (jours " .. tostring(relu and relu.jours) .. ")")
	end
}
