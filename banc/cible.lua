-- Chantier sanctions, tâche 5 : la résolution de cible de `!sanctions`, et le menu C ouvert au seul droit.
return {
	contenu = true,
	delai = 40,
	run = function(Banc)
		local Sanctions = VALDERAAN.Sanctions
		local modo = Banc.Bot({nom = "Modo"})
		local cible = Banc.Bot({nom = "Ciblé"})

		if (!modo or !cible) then return Banc.Verifier(0, false, "bots non montés") end

		local steamid64 = util.SteamIDTo64("STEAM_0:1:4242")
		local resultats = {
			Sanctions.ResoudreCible("STEAM_0:1:4242", modo) == steamid64,
			Sanctions.ResoudreCible(steamid64, modo) == steamid64,
			Sanctions.ResoudreCible("^", modo) == modo:SteamID64(),
			Sanctions.ResoudreCible("Ciblé", modo) == cible:SteamID64()
		}
		local rien, raison = Sanctions.ResoudreCible("zzz", modo)
		local lus = {}

		for i, ok in ipairs(resultats) do
			lus[i] = tostring(ok)
		end

		Banc.Verifier(1, !table.HasValue(resultats, false) and rien == nil and isstring(raison),
			"SteamID, SteamID64, ^, nom, puis zzz (" .. table.concat(lus, ",") .. ", zzz : " .. tostring(raison) .. ")")

		-- ⚠️ Un bot n'a jamais d'accès ULib (garde de sv_banc_bot) : le droit du modérateur se pose ici.
		local peutGerer = Sanctions.PeutGerer

		Sanctions.PeutGerer = function(client) return client == modo or peutGerer(client) end
		Banc.Defaire(function() Sanctions.PeutGerer = peutGerer end)

		local propriete = properties.List.sanctions
		local pourModo = propriete:Filter(cible, modo)
		local pourCible = propriete:Filter(cible, cible)
		local surMonde = propriete:Filter(game.GetWorld(), modo)

		Banc.Verifier(2, pourModo == true and pourCible == false and surMonde == false and ix.plugin.list.sanctions.CanProperty == nil,
			"menu C : modérateur " .. tostring(pourModo) .. ", sans droit " .. tostring(pourCible) .. ", hors joueur " .. tostring(surMonde) .. ", CanProperty de Helix intact")

		local inscrite = false

		for _, commande in ipairs(ulx.cmdsByCategory.Valderaan or {}) do
			inscrite = inscrite or commande.cmd == "ulx sanctions"
		end

		Banc.Verifier(3, inscrite and ULib.ucl.accessStrings["ulx sanctions"] != nil, "!sanctions inscrite dans ULX, accès enregistré")
	end
}
