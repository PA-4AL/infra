#!/usr/bin/env python3
"""Jeu de données de démonstration — tournois esport.

Peuple l'environnement **via l'API**, jamais par SQL direct : la génération des
brackets, le chaînage `next_match_id`, les seeds, les byes et la propagation des
vainqueurs sont produits par la vraie logique métier du backend. Des insertions
SQL fabriquées à la main donneraient des brackets incohérents que l'interface
révélerait au premier clic.

Idempotent : un tournoi dont le nom existe déjà est ignoré. Rejouable sans
dupliquer.

Usage :
    API_URL=https://api.patournament.fr TOKEN=<jeton JWT organizer> \\
        python3 scripts/seed-demo.py [--dry-run]

Le jeton doit porter le rôle `organizer` ou `admin` : c'est son porteur qui
devient propriétaire des tournois créés.
"""

from __future__ import annotations

import json
import os
import random
import sys
import urllib.error
import urllib.request

API = os.environ.get("API_URL", "").rstrip("/")
TOKEN = os.environ.get("TOKEN", "")
DRY = "--dry-run" in sys.argv

if not API or not TOKEN:
    sys.exit("API_URL et TOKEN sont requis (voir l'en-tête du script)")

# Graine fixe : deux exécutions produisent le même tirage, ce qui rend les
# captures d'écran et les démonstrations reproductibles.
random.seed(4)


# --------------------------------------------------------------------------- #
# Jeu de données — uniquement des jeux dotés d'une scène esport réelle
# --------------------------------------------------------------------------- #

ORGS = [
    "Nova Syndicate", "Iron Vanguard", "Void Collective", "Solaris Esports",
    "Crimson Pact", "Northern Lights", "Obsidian Order", "Zenith Gaming",
    "Aurora Division", "Titan Foundry", "Echo Dynasty", "Phantom Ascent",
    "Meridian Squad", "Kraken Athletics", "Wildfire Union", "Static Legion",
]

PRENOMS = [
    "Lucas", "Emma", "Noah", "Léa", "Gabriel", "Chloé", "Adam", "Jade",
    "Louis", "Alice", "Rayan", "Mila", "Hugo", "Anna", "Nathan", "Zoé",
]

TOURNOIS = [
    {
        "name": "Valorant Champions Series — Qualifier Paris",
        "description": "Qualification ouverte européenne, format élimination directe. "
                       "Les deux finalistes accèdent au tournoi principal.",
        "game": "Valorant", "best_of": 3, "team_size": 5,
        "participants": 8, "etat": "termine",
    },
    {
        "name": "Rift Masters — Split Été 2026",
        "description": "Compétition League of Legends sur trois week-ends. "
                       "Phase finale en élimination directe.",
        "game": "League of Legends", "best_of": 5, "team_size": 5,
        "participants": 8, "etat": "termine",
    },
    {
        "name": "PA Major CS2 — Qualification EU",
        "description": "Counter-Strike 2, seize équipes, un seul billet pour le Major.",
        "game": "Counter-Strike 2", "best_of": 3, "team_size": 5,
        "participants": 16, "etat": "en_cours",
    },
    {
        "name": "Aerial Cup — Rocket League 3v3",
        "description": "Tournoi hebdomadaire Rocket League, ouvert à tous les niveaux.",
        "game": "Rocket League", "best_of": 5, "team_size": 3,
        "participants": 8, "etat": "en_cours",
    },
    {
        "name": "Overwatch Champions Series — PA Invitational",
        "description": "Huit équipes invitées, Overwatch 2. Les inscriptions "
                       "ferment 24 h avant le coup d'envoi.",
        "game": "Overwatch 2", "best_of": 3, "team_size": 5,
        "participants": 8, "etat": "inscriptions",
    },
    {
        "name": "Ancients Open — Dota 2",
        "description": "Tournoi Dota 2 ouvert, seize équipes maximum.",
        "game": "Dota 2", "best_of": 3, "team_size": 5,
        "participants": 12, "etat": "inscriptions",
    },
    {
        "name": "Apex Predator Trials",
        "description": "Apex Legends en trios, élimination directe.",
        "game": "Apex Legends", "best_of": 3, "team_size": 3,
        "participants": 8, "etat": "inscriptions",
    },
]


# --------------------------------------------------------------------------- #
# Client HTTP minimal
# --------------------------------------------------------------------------- #

def appel(methode: str, chemin: str, corps: dict | None = None) -> tuple[int, object]:
    requete = urllib.request.Request(
        f"{API}{chemin}",
        method=methode,
        data=json.dumps(corps).encode() if corps is not None else None,
        headers={
            "Authorization": f"Bearer {TOKEN}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(requete, timeout=60) as reponse:
            brut = reponse.read().decode()
            return reponse.status, (json.loads(brut) if brut else None)
    except urllib.error.HTTPError as erreur:
        brut = erreur.read().decode()
        try:
            return erreur.code, json.loads(brut)
        except json.JSONDecodeError:
            return erreur.code, brut


def exiger(condition: bool, message: str) -> None:
    if not condition:
        sys.exit(f"ÉCHEC — {message}")


# --------------------------------------------------------------------------- #
# Peuplement
# --------------------------------------------------------------------------- #

def tournois_existants() -> set[str]:
    code, corps = appel("GET", "/api/v1/tournaments")
    exiger(code == 200, f"impossible de lister les tournois (HTTP {code})")
    return {t["name"] for t in corps}


def creer_tournoi(spec: dict) -> str:
    code, corps = appel("POST", "/api/v1/tournaments", {
        "name": spec["name"],
        "description": spec["description"],
        "games": [{"name": spec["game"], "bestOf": spec["best_of"]}],
        "format": "single_elim",
        "teamSize": spec["team_size"],
        "maxParticipants": spec["participants"],
        "visibility": "public",
    })
    exiger(code == 201, f"création de « {spec['name']} » : HTTP {code} — {corps}")
    return corps["id"]


def inscrire_participants(tid: str, noms: list[str]) -> None:
    for nom in noms:
        code, corps = appel("POST", f"/api/v1/tournaments/{tid}/participants", {"name": nom})
        exiger(code in (200, 201), f"inscription de « {nom} » : HTTP {code} — {corps}")


def generer_bracket(tid: str) -> dict:
    code, corps = appel("POST", f"/api/v1/tournaments/{tid}/bracket/generate", {})
    exiger(code == 200, f"génération du bracket : HTTP {code} — {corps}")
    return corps


def jouer(tid: str, rounds_a_jouer: int | None) -> int:
    """Joue les matchs round par round. `None` = jusqu'à la finale.

    On relit le bracket après chaque match : les vainqueurs remontent, donc les
    participants du round suivant ne sont connus qu'une fois le précédent terminé.
    """
    joues = 0
    while True:
        code, bracket = appel("GET", f"/api/v1/tournaments/{tid}/bracket")
        exiger(code == 200, f"lecture du bracket : HTTP {code}")
        rounds = bracket.get("rounds", [])
        if not rounds:
            return joues

        index_courant = next(
            (i for i, r in enumerate(rounds)
             if any(m["status"] != "done" for m in r["matches"])),
            None,
        )
        if index_courant is None:
            return joues  # tout est joué
        if rounds_a_jouer is not None and index_courant >= rounds_a_jouer:
            return joues  # on s'arrête volontairement en cours de route

        for match in rounds[index_courant]["matches"]:
            if match["status"] == "done":
                continue
            if match["a"].get("tbd") or match["b"].get("tbd"):
                continue  # bye déjà résolu, ou adversaire pas encore connu
            gagne_a = random.random() < 0.5
            score_a, score_b = (2, random.choice([0, 1])) if gagne_a else (random.choice([0, 1]), 2)
            code, corps = appel("POST", f"/api/v1/matches/{match['matchId']}/score",
                                {"scoreA": score_a, "scoreB": score_b})
            exiger(code == 200, f"saisie du score : HTTP {code} — {corps}")
            joues += 1


def main() -> None:
    deja_la = tournois_existants()
    print(f"→ {len(deja_la)} tournoi(s) déjà présent(s)")

    orgs = ORGS.copy()
    total_matchs = 0

    for spec in TOURNOIS:
        if spec["name"] in deja_la:
            print(f"  = « {spec['name']} » existe déjà, ignoré")
            continue
        if DRY:
            print(f"  ~ créerait « {spec['name']} » ({spec['game']}, "
                  f"{spec['participants']} équipes, état {spec['etat']})")
            continue

        tid = creer_tournoi(spec)
        random.shuffle(orgs)
        noms = [orgs[i % len(orgs)] + (f" {spec['game'][:2].upper()}" if i >= len(orgs) else "")
                for i in range(spec["participants"])]
        inscrire_participants(tid, noms)
        print(f"  + « {spec['name']} » — {spec['participants']} équipes", end="")

        if spec["etat"] == "inscriptions":
            print(" — inscriptions ouvertes")
            continue

        bracket = generer_bracket(tid)
        nb_rounds = len(bracket.get("rounds", []))
        # « en cours » : on s'arrête avant les deux derniers tours pour laisser
        # des matchs à jouer pendant la démonstration.
        limite = None if spec["etat"] == "termine" else max(1, nb_rounds - 2)
        joues = jouer(tid, limite)
        total_matchs += joues
        print(f" — bracket {nb_rounds} tours, {joues} match(s) joué(s)"
              f"{' — terminé' if spec['etat'] == 'termine' else ' — en cours'}")

    if not DRY:
        print(f"\n✓ terminé — {total_matchs} matchs saisis au total")


if __name__ == "__main__":
    main()
