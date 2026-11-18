-- Chantier sanctions, tâche 12 : le journal général — ordre, filtres, pagination par curseur, refus, lecture seule, taille, injection.
return {
	contenu = true,
	delai = 120,
	run = function(Banc)
		local Sanctions = VALDERAAN.Sanctions
		local A = {steamid64 = util.SteamIDTo64("STEAM_0:1:9999101"), nom = "BancJA"}
		local B = {steamid64 = util.SteamIDTo64("STEAM_0:1:9999103"), nom = "BancJB"}
		local P = {steamid64 = util.SteamIDTo64("STEAM_0:1:9999105"), nom = "BancJP"}
		local Q = {steamid64 = util.SteamIDTo64("STEAM_0:1:9999107"), nom = "BancJQ"}
		local C1, C2, C3 = util.SteamIDTo64("STEAM_0:1:9999111"), util.SteamIDTo64("STEAM_0:1:9999113"), util.SteamIDTo64("STEAM_0:1:9999115")
		local PERSO = "Aldric-banc-j"

		local function attendre(lancer)
			local fini, a, b = false, nil, nil

			lancer(function(x, y) fini, a, b = true, x, y end)

			return Banc.AttendreQue(function() return fini end, 5) and a, b
		end

		local function compter(table)
			return attendre(function(fin)
				local query = mysql:Select(table)
					query:Callback(function(rows) fin(istable(rows) and #rows or 0) end)
				query:Execute()
			end)
		end

		Banc.Defaire(function()
			for _, acteur in ipairs({A, B, P, Q}) do
				for _, table in ipairs({"val_sanctions", "val_sanctions_journal"}) do
					local query = mysql:Delete(table)
						query:Where("auteur_steamid64", acteur.steamid64)
					query:Execute()
				end
			end
		end)

		local function creer(acteur, compte, type, sanction, texte)
			local fin = sanction == "temporaire" and os.time() + Sanctions.JOUR or nil

			return attendre(function(rendre)
				Sanctions.Creer(acteur, compte, {type = type, texte = texte or "Texte du banc", sanction = sanction, fin = fin}, rendre)
			end)
		end

		local function journal(filtres)
			local pleins = {sanction = "", type = "", moderateur = "", compte = "", avant = 0}
			local dossiers, suite = attendre(function(rendre)
				Sanctions.Journal(table.Merge(pleins, filtres or {}), rendre)
			end)

			return dossiers, suite
		end

		local function ids(dossiers)
			local liste = {}

			for _, dossier in ipairs(dossiers or {}) do liste[#liste + 1] = dossier.id end

			return liste
		end

		local function contient(dossiers, id)
			return table.HasValue(ids(dossiers), id)
		end

		local d1 = creer(A, C1, "metagaming", "aucune")
		local d2 = creer(A, C2, "freekill", "temporaire")
		local d3 = creer(B, C3, "freekill", "definitive")

		if (!d1 or !d2 or !d3) then return Banc.Verifier(0, false, "dossiers de départ non posés") end

		local persoQuery = mysql:Update("val_sanctions")
			persoQuery:Update("perso_nom", PERSO)
			persoQuery:Where("id", d1.id)
		persoQuery:Execute()

		local tous = journal({moderateur = A.steamid64})
		local trois = journal()

		Banc.Verifier(1, ids(tous)[1] == d2.id and ids(tous)[2] == d1.id and contient(trois, d3.id) and ids(trois)[1] == d3.id
			and ids(trois)[2] == d2.id and ids(trois)[3] == d1.id,
			"le plus récent d'abord, les trois présents (" .. table.concat(ids(trois), ",") .. " / A : " .. table.concat(ids(tous), ",") .. ", d2 " .. d2.id .. ")")

		local function seuls(dossiers, presents, absents, controle)
			for _, dossier in ipairs(presents) do
				if (!contient(dossiers, dossier.id)) then return false end
			end

			for _, dossier in ipairs(absents) do
				if (contient(dossiers, dossier.id)) then return false end
			end

			for _, ligne in ipairs(dossiers or {}) do
				if (!controle(ligne)) then return false end
			end

			return true
		end

		local resultats = {
			seuls(journal({sanction = "avertissement"}), {d1}, {d2, d3}, function(l) return l.sanction == "aucune" end),
			seuls(journal({sanction = "bannissement"}), {d2, d3}, {d1}, function(l) return l.sanction != "aucune" end),
			seuls(journal({type = "freekill"}), {d2, d3}, {d1}, function(l) return l.type == "freekill" end),
			seuls(journal({moderateur = A.steamid64}), {d1, d2}, {d3}, function(l) return l.auteur_steamid64 == A.steamid64 end),
			seuls(journal({moderateur = "BancJB"}), {d3}, {d1, d2}, function(l) return l.auteur_nom:find("BancJB", 1, true) end),
			seuls(journal({compte = C1}), {d1}, {d2, d3}, function(l) return l.steamid64 == C1 end),
			seuls(journal({compte = util.SteamIDFrom64(C2)}), {d2}, {d1, d3}, function(l) return l.steamid64 == C2 end),
			seuls(journal({compte = "aldric-banc"}), {d1}, {d2, d3}, function(l) return l.perso_nom == PERSO end),
			seuls(journal({sanction = "bannissement", moderateur = A.steamid64}), {d2}, {d1, d3}, function(l) return l.id == d2.id end)
		}

		Banc.Verifier(2, !table.HasValue(resultats, false),
			"neuf filtres, seuls puis cumulés (" .. util.TableToJSON(resultats) .. ")")

		local dernier

		for i = 1, 51 do
			dernier = creer(P, C1, "autre", "aucune", "Page " .. i)
		end

		local page1, suite1 = journal({moderateur = P.steamid64})
		local page2, suite2 = journal({moderateur = P.steamid64, avant = page1[#page1].id})
		local vus, doublon = {}, false

		for _, liste in ipairs({page1, page2}) do
			for _, dossier in ipairs(liste) do
				doublon = doublon or vus[dossier.id]
				vus[dossier.id] = true
			end
		end

		Banc.Verifier(3, #page1 == 50 and suite1 == true and #page2 == 1 and suite2 == false and !doublon and table.Count(vus) == 51
			and page2[1].texte == "Page 1" and dernier,
			"51 dossiers : " .. #page1 .. " + suite " .. tostring(suite1) .. ", puis " .. #page2 .. " + suite " .. tostring(suite2))

		-- ⚠️ Un bot n'a jamais d'accès ULib : le droit du modérateur se pose ici, et la réponse se lit au lieu de partir.
		local joueur = Banc.Bot({nom = "Joueur"})
		local modo = Banc.Bot({nom = "Modo"})

		if (!joueur or !modo) then return Banc.Verifier(4, false, "bots non montés") end

		local peutGerer, repondre = Sanctions.PeutGerer, Sanctions.Repondre
		local recu = {}

		Sanctions.PeutGerer = function(client) return client == modo or peutGerer(client) end
		Sanctions.Repondre = function(client, genre, contenu) recu[client] = {genre = genre, contenu = contenu} end

		Banc.Defaire(function() Sanctions.PeutGerer, Sanctions.Repondre = peutGerer, repondre end)

		local function agir(client, filtres, vite)
			if (!vite) then Banc.Attendre(0.6) end

			recu[client] = nil
			Sanctions.Recevoir(client, "Journal", table.Merge({sanction = "", type = "", moderateur = "", compte = "", avant = 0}, filtres or {}))
			Banc.AttendreQue(function() return recu[client] != nil end, 3)

			return recu[client] or {}
		end

		local refus = {
			agir(joueur).genre,
			agir(modo, {compte = string.rep("a", Sanctions.FILTRE_MAX + 1)}).genre,
			agir(modo, {type = "inconnu"}).genre,
			agir(modo, {sanction = "tout"}).genre,
			agir(modo, {avant = -1}).genre
		}
		local premiere = agir(modo)
		local seconde = agir(modo, nil, true)

		Banc.Verifier(4, table.concat(refus, ",") == "refus,refus,refus,refus,refus" and premiere.genre == "journal"
			and seconde.genre == "refus" and tostring(seconde.contenu):find("Trop rapide", 1, true),
			"quatre refus de forme et de droit, puis le débit (" .. table.concat(refus, ",") .. " / " .. tostring(premiere.genre) .. " / " .. tostring(seconde.contenu) .. ")")

		local annule = creer(Q, C1, "insulte", "aucune")
		local leve = creer(Q, C2, "insulte", "temporaire")
		local ecrase = creer(Q, C3, "insulte", "temporaire")

		attendre(function(rendre) Sanctions.Annuler(Q, annule.id, rendre) end)

		local levee = mysql:Update("val_sanctions")
			levee:Update("levee_le", os.time() - 60)
			levee:Where("id", leve.id)
		levee:Execute()

		local avantDossiers, avantJournal = compter("val_sanctions"), compter("val_sanctions_journal")
		local lus = journal({moderateur = Q.steamid64})
		local presentes = contient(lus, annule.id) and contient(lus, leve.id) and contient(lus, ecrase.id)
		local brut = {}

		for _, dossier in ipairs(lus) do brut[dossier.id] = dossier end

		Banc.Verifier(5, presentes and brut[annule.id].annulee and brut[leve.id].levee_le and avantDossiers == compter("val_sanctions")
			and avantJournal == compter("val_sanctions_journal"),
			"annulé, levé et temporaire présents, " .. avantDossiers .. " lignes avant et après")

		-- Du CJK tiré au hasard : trois octets par caractère et presque incompressible, le pire texte d'une page.
		local function aleatoire()
			local lettres = {}

			for i = 1, Sanctions.TEXTE_MAX do lettres[i] = utf8.char(math.random(0x4E00, 0x9FFF))	end

			return table.concat(lettres)
			end

		for _ = 1, 50 do creer(B, C2, "autre", "aucune", aleatoire())	end

		local reponse = agir(modo, {type = "autre", moderateur = B.steamid64})
		local envoyes = reponse.contenu and reponse.contenu.dossiers or {}
		local taille = #util.Compress(util.TableToJSON(reponse.contenu or {}))

		Banc.Verifier(6, reponse.genre == "journal" and #envoyes >= 1 and taille <= 60000
			and (#envoyes == 50 or reponse.contenu.suite == true),
			"50 textes CJK de 1 000 caractères : " .. #envoyes .. " envoyés, " .. taille .. " octets compressés")

		local avantInjection = compter("val_sanctions")
		local inconnus = {}

		for _, filtre in ipairs({"%'", "%", "_", "'; DROP TABLE val_sanctions; --", "\\"}) do
			local pour, fini = nil, false

			Sanctions.Journal({sanction = "", type = "", moderateur = "", compte = filtre, avant = 0}, function(dossiers)
				pour, fini = dossiers, true
			end)
			Banc.AttendreQue(function() return fini end, 3)

			inconnus[#inconnus + 1] = (fini and #pour == 0) and "0" or (fini and tostring(#pour) or "erreur")
		end

		Banc.Verifier(7, table.concat(inconnus, ",") == "0,0,0,0,0" and compter("val_sanctions") == avantInjection,
			"cinq motifs hostiles : zéro dossier, table intacte (" .. table.concat(inconnus, ",") .. ")")
	end
}
