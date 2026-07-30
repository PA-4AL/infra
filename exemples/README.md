# Fichiers d'exemple pour l'import d'équipes

Fichiers `.xlsx` destinés à éprouver l'import depuis l'interface :
**Participants → « Importer un fichier »**.

Les deux premiers sont des **effectifs complets**, prêts pour une démonstration. Les
suivants couvrent des cas limites, dont un qui doit **échouer proprement** — un import
qui refuse en expliquant pourquoi vaut mieux qu'un import qui aboutit sur des données
fausses, et une démonstration doit montrer les deux comportements.

| Fichier | Ce qu'il éprouve | Mapping à choisir | Résultat attendu |
|---|---|---|---|
| `import-4-equipes-5-joueurs.xlsx` | **effectif complet 5v5** — 4 équipes de 5 | Équipe **A** · Pseudo **B** · Rang **C**, en-tête coché | 4 équipes, 20 joueurs |
| `import-12-equipes-3-joueurs.xlsx` | **effectif complet 3v3** — 12 équipes de 3 | Équipe **A** · Pseudo **B** · Rang **C**, en-tête coché | 12 équipes, 36 joueurs |
| `import-esport-standard.xlsx` | cas nominal | Équipe **A** · Pseudo **B** · Rang **C**, en-tête coché | 2 équipes, 6 joueurs |
| `import-esport-colonnes-libres.xlsx` | libellés quelconques, colonnes dispersées, colonnes parasites | Équipe **B** · Pseudo **D** · Rang **E**, en-tête coché | 2 équipes, 4 joueurs |
| `import-esport-sans-entete.xlsx` | fichier sans ligne de titres | Équipe **A** · Pseudo **B** · Rang **C**, en-tête **décoché** | 2 équipes, 4 joueurs |
| `import-football.xlsx` | gabarit football, 5 colonnes de joueur | Équipe **A** · Nom **B** · Prénom **C** · Poste **D** · Numéro **E** | 2 équipes, 5 joueurs |
| `import-esport-ligne-invalide.xlsx` | nom d'équipe vide en ligne 3 | Équipe **A** · Pseudo **B** · Rang **C** | **échec** : « Colonne 'Équipe' vide à la ligne 3 » |

## Comment régler le tournoi avant d'importer

C'est la confusion la plus facile à faire, et elle change tout :

| Champ du formulaire | Pour 12 équipes de 3 | Ce qu'il commande |
|---|---|---|
| **Taille des équipes** | `3v3` | l'effectif attendu **par équipe** — c'est lui qui décide si une équipe est signalée incomplète |
| **Participants max** | `12` | le plafond d'**équipes**, pas de joueurs |

**Une équipe compte pour un participant**, quel que soit son nombre de joueurs : le
décompte porte sur les inscriptions (`registrations`), pas sur les personnes. Mettre
`36` dans « participants max » autoriserait 36 équipes de 3, soit 108 joueurs.

## Les deux fichiers prêts pour une démonstration

`import-4-equipes-5-joueurs.xlsx` — 4 équipes de **exactement 5 joueurs**. Tournoi
en `5v5`, 4 participants max. L'arbre se génère ensuite sur 4 participants : deux
demi-finales et une finale, le cas le plus simple à montrer.

`import-12-equipes-3-joueurs.xlsx` — 12 équipes de **exactement 3 joueurs**. Tournoi
en `3v3`, 12 participants max.

> **12 n'est pas une puissance de deux.** En élimination simple, le générateur
> construit un tableau de 16 avec **4 exemptions** : les quatre premières têtes de
> série passent le premier tour sans jouer. C'est correct et standard, mais cela se
> voit à l'écran. En **élimination double**, 12 fonctionne sans réserve — et le
> tableau des perdants est ce que ce projet a de plus intéressant à montrer. En
> round robin, 12 équipes donnent **66 matchs** sur 11 journées : beaucoup à saisir
> pour arriver à un tournoi terminé.

Importés dans un tournoi d'une autre taille, les équipes sont créées quand même mais
signalées « 3/5 » ou « 5/11 » dans le résultat du traitement — c'est un avertissement,
pas un refus, l'organisateur seul sachant si l'effectif est normal.

## Le fichier qui justifie la fonctionnalité

`import-esport-colonnes-libres.xlsx`. Ses colonnes s'appellent *Club*, *Joueur*,
*Niveau* — pas *Équipe*, *Pseudo*, *Rang* — et une colonne *Ville* s'intercale au
milieu. Avant le choix explicite des colonnes, il était **impossible à importer** : le
worker les cherchait par leur en-tête et refusait le fichier pour colonne manquante.
L'organisateur devait renommer et réordonner ses colonnes à la main avant chaque import.

Le **gabarit** — esport ou football — est une propriété du tournoi, choisie à sa
création (`tournaments.file_template`). Il était auparavant déduit de la taille
d'équipe (`11` → football), ce qui se trompait dès qu'un tournoi de football ne se
jouait pas à 11. Importer `import-football.xlsx` dans un tournoi déclaré esport
proposera donc les colonnes esport et refusera le fichier : les deux gabarits ne
décrivent pas les mêmes données.

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

```bash
cd infra/exemples && python3 generer-exemples.py
```

Le script réécrit les deux fichiers d'effectif complet, puis **relit ce qu'il vient
d'écrire** plutôt que de faire confiance à l'écriture : il échoue si un effectif ne
correspond pas à ce qui est annoncé, ou si un pseudo apparaît deux fois.

Cette dernière vérification n'est pas cosmétique : la matérialisation d'un import
dédoublonne les joueurs **par pseudo**, donc un homonyme se retrouverait rattaché à
deux équipes. Un fichier d'exemple qui produirait des données fausses serait pire
qu'aucun fichier.

Les modifier à la main dans un tableur fonctionne aussi : seul le contenu compte, pas
la façon dont il a été écrit. Les quatre fichiers de cas limites, eux, ne sont pas
régénérés par le script — ils sont figés, c'est ce qui en fait des cas de référence.
