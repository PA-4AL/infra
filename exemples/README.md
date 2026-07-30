# Fichiers d'exemple pour l'import d'équipes

Fichiers `.xlsx` destinés à éprouver l'import depuis l'interface :
**Participants → « Importer un fichier »**.

Chacun couvre un cas précis. Les trois premiers doivent réussir, le dernier doit
**échouer proprement** — un import qui refuse en expliquant pourquoi vaut mieux
qu'un import qui aboutit sur des données fausses.

| Fichier | Ce qu'il éprouve | Mapping à choisir | Résultat attendu |
|---|---|---|---|
| `import-4-equipes-5-joueurs.xlsx` | **effectif complet 5v5** — 4 équipes de 5 | Équipe **A** · Pseudo **B** · Rang **C**, en-tête coché | 4 équipes, 20 joueurs |
| `import-esport-standard.xlsx` | cas nominal | Équipe **A** · Pseudo **B** · Rang **C**, en-tête coché | 2 équipes, 6 joueurs |
| `import-esport-colonnes-libres.xlsx` | libellés quelconques, colonnes dispersées, colonnes parasites | Équipe **B** · Pseudo **D** · Rang **E**, en-tête coché | 2 équipes, 4 joueurs |
| `import-esport-sans-entete.xlsx` | fichier sans ligne de titres | Équipe **A** · Pseudo **B** · Rang **C**, en-tête **décoché** | 2 équipes, 4 joueurs |
| `import-football.xlsx` | gabarit football, 5 colonnes de joueur | Équipe **A** · Nom **B** · Prénom **C** · Poste **D** · Numéro **E** | 2 équipes, 5 joueurs |
| `import-esport-ligne-invalide.xlsx` | nom d'équipe vide en ligne 3 | Équipe **A** · Pseudo **B** · Rang **C** | **échec** : « Colonne 'Équipe' vide à la ligne 3 » |

## Le fichier prêt pour une démonstration

`import-4-equipes-5-joueurs.xlsx` — 4 équipes de **exactement 5 joueurs**, rangs
plausibles, pseudos uniques. À importer dans un tournoi déclaré **5v5** : l'effectif
correspond au format, aucune équipe n'est signalée incomplète, et l'arbre se génère
ensuite sur 4 participants.

Importé dans un tournoi d'une autre taille, les équipes sont créées quand même mais
signalées « 5/3 » ou « 5/11 » dans le résultat du traitement — c'est un avertissement,
pas un refus, l'organisateur seul sachant si l'effectif est normal.

## Le fichier qui compte

`import-esport-colonnes-libres.xlsx` est celui qui justifie la fonctionnalité.
Ses colonnes s'appellent *Club*, *Joueur*, *Niveau* — pas *Équipe*, *Pseudo*,
*Rang* — et une colonne *Ville* s'intercale au milieu. Avant le choix explicite
des colonnes, il était **impossible à importer** : le worker les cherchait par
leur en-tête et refusait le fichier pour colonne manquante. L'organisateur devait
renommer et réordonner ses colonnes à la main avant chaque import.

Le gabarit (esport ou football) est déduit de la **taille d'équipe du tournoi** :
11 joueurs relèvent du modèle football, tout le reste du modèle esport. Importer
`import-football.xlsx` dans un tournoi à 5 joueurs proposera donc les colonnes
esport et refusera le fichier — c'est voulu, les deux gabarits ne décrivent pas
les mêmes données.

## Deux points de vigilance dans l'interface

**La même lettre pour deux données** est refusée avant l'envoi. Sans ce contrôle,
le worker lirait deux fois la même colonne et créerait des joueurs dont le pseudo
vaut le nom de l'équipe, **sans rien signaler** — une donnée fausse et
silencieuse, le pire des deux mondes.

**Décocher « la première ligne contient les titres »** sur un fichier qui en a un
transforme cette ligne d'en-tête en équipe : vous verriez apparaître une équipe
nommée « Équipe » avec un joueur « Pseudo ». L'inverse ampute la première équipe.

## Ce que l'import écrit réellement

Une équipe par valeur distincte de la colonne Équipe, un **joueur fantôme** par
pseudo (utilisateur sans compte Keycloak, rattachable plus tard par email), le
rang en jeu dans `team_members.rank`, et l'inscription au tournoi visé. Le premier
joueur listé devient capitaine.

L'opération est **idempotente** : réimporter le même fichier ne duplique rien et
met les rangs à jour. C'est une nécessité, pas un confort — Pub/Sub garantit *au
moins* une livraison, le même message peut donc arriver deux fois.

## Regénérer ces fichiers

Ils sont produits par le bloc `python3` documenté dans l'historique git de ce
dossier (`openpyxl`). Les modifier à la main dans un tableur fonctionne aussi :
seul le contenu compte, pas la façon dont il a été écrit.
