-- Chantier sanctions, tâche 1 : la formule d'état, sur des dossiers construits à la main, à horodatage fixé.
return {
	delai = 20,
	run = function(Banc)
		local Sanctions = VALDERAAN.Sanctions

		Banc.Verifier(1, Sanctions != nil and isfunction(Sanctions.Etat), "VALDERAAN.Sanctions.Etat existe côté serveur")

		if (!Sanctions or !Sanctions.Etat) then return end

		local T = 1800000000
		local J = Sanctions.JOUR

		local function dossier(champs)
			return table.Merge({sanction = "aucune", debut = T - 10 * J, annulee = false}, champs)
		end

		local cas = {
			{dossier({annulee = true, sanction = "definitive"}), "annule"},
			{dossier({}), "avertissement"},
			{dossier({sanction = "definitive", levee_le = T - J}), "leve"},
			{dossier({sanction = "definitive"}), "banni"},
			{dossier({sanction = "temporaire", fin = T + 20 * J}), "banni_jusqu"},
			{dossier({sanction = "temporaire", fin = T - 7 * J}), "termine"}
		}

		local faux = {}

		for i, ligne in ipairs(cas) do
			local etat = Sanctions.Etat(ligne[1], T)

			if (etat != ligne[2]) then
				faux[#faux + 1] = i .. ":" .. etat .. "≠" .. ligne[2]
			end
		end

		local _, echeance = Sanctions.Etat(cas[5][1], T)

		Banc.Verifier(2, #faux == 0 and echeance == T + 20 * J,
			"six états attendus, échéance = fin (" .. (#faux == 0 and "ok" or table.concat(faux, ", ")) .. ", échéance " .. tostring(echeance) .. ")")

		local pile = dossier({sanction = "temporaire", fin = T})
		Banc.Verifier(3, Sanctions.Etat(pile, T) == "termine", "échéance exactement maintenant : terminé (" .. Sanctions.Etat(pile, T) .. ")")

		Banc.Verifier(4, Sanctions.Libelle("type_disparu") == "Autre" and Sanctions.Libelle("freekill") == "Freekill",
			"un type inconnu s'affiche « Autre » (" .. tostring(Sanctions.Libelle("type_disparu")) .. ")")
	end
}
