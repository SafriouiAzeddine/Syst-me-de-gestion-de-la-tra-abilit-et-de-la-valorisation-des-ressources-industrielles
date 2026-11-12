# RE:SOURCE

**Système de gestion du cycle de vie et de la seconde vie des ressources secondaires**

> « Ne suivons plus les déchets. Suivons la vie des ressources. »

RE:SOURCE est une application web (Flask + MySQL) qui donne à chaque ressource industrielle une **identité numérique** et une **mémoire** : son historique d'événements ne se supprime jamais. À partir de ces données, la plateforme met en relation producteurs et utilisateurs, et compare les **vies possibles** d'une ressource : réutilisation, transformation, recyclage ou autre valorisation.

Projet réalisé dans le cadre du module *Bases de Données Relationnelles* (Master Data & IA).

---

## Sommaire

1. [Fonctionnalités](#fonctionnalités)
2. [Technologies](#technologies)
3. [Prérequis](#prérequis)
4. [Installation](#installation)
5. [Lancer l'application](#lancer-lapplication)
6. [Structure du projet](#structure-du-projet)
7. [Base de données](#base-de-données)
8. [Règles de gestion](#règles-de-gestion)
9. [Scénario de démonstration](#scénario-de-démonstration)
10. [Dépannage](#dépannage)

---

```
resource_mcd_mysql.sql            (existant : création de la base, triggers, vues, jeu minimal)
sql/02_donnees_supplementaires.sql
sql/03_requetes.sql
sql/04_index_explain.sql
python/demo_mysql.py
```

## Fonctionnalités

| Section | Ce que fait l'application |
|---|---|
| **Tableau de bord** | Indicateurs clés, graphiques par statut et par matériau, derniers événements, meilleures correspondances |
| **Entreprises et rôles** | Gestion des acteurs (producteur, acheteur, transformateur, recycleur, transporteur, expert) et de leurs rôles |
| **Matériaux et distances** | Référentiel des matériaux et distances entre villes, utilisées par le matching |
| **Ressources** | Création avec composition en matériaux (total de 100 %), modification, **passeport numérique** |
| **Passeport et historique** | Chronologie complète des événements d'une ressource, ajout d'événements manuels |
| **Offres et demandes** | Publication d'offres et de demandes (quantité, qualité minimale, distance maximale, budget) |
| **Matching** | Mise en correspondance des offres et des demandes avec un score de compatibilité sur 100 |
| **Transactions** | Vente d'une ressource : le propriétaire change et l'historique s'enrichit automatiquement |
| **Scénarios de seconde vie** | Comparaison des scénarios classés par gain net, avec graphiques |
| **Rapports** | Réponses aux cinq questions métier du projet et contrôle de la qualité des données |

L'application ne se connecte pas avec un compte : l'utilisateur choisit l'**entreprise active** dans la barre de navigation.

## Technologies

| Couche | Outils |
|---|---|
| Backend | Python 3.11+, Flask 3, Flask-SQLAlchemy 3, Flask-WTF |
| Base de données | MySQL 8.0.16+ (pilote PyMySQL) |
| Frontend | Jinja2, Bootstrap 5.3, Bootstrap Icons, Chart.js |

## Prérequis

- **Python 3.11** ou plus récent
- **MySQL 8.0.16** ou plus récent (nécessaire pour les contraintes `CHECK` et les fonctions de fenêtre)
- **Git**
- Un client MySQL : MySQL Workbench, DBeaver ou la ligne de commande

## Installation


## 1. Installer et démarrer MySQL dans le Codespace

```bash
sudo apt-get update && sudo apt-get install -y mysql-server
sudo service mysql start
sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'root'; FLUSH PRIVILEGES;"
```

(le mot de passe `root` est un exemple ; changez-le si vous voulez)

## 2. Exécuter les scripts dans cet ordre

```bash
mysql --default-character-set=utf8mb4 -uroot -proot < resource_mcd_mysql.sql
mysql --default-character-set=utf8mb4 -uroot -proot < sql/02_donnees_supplementaires.sql
mysql --default-character-set=utf8mb4 -uroot -proot -t < sql/03_requetes.sql
mysql --default-character-set=utf8mb4 -uroot -proot -t < sql/04_index_explain.sql
```

- Le script 01 **supprime et recrée** `resource_db`.
- Le script 04 ajoute ~70 000 lignes de test. Pour revenir à un jeu propre (avant démo Flask par exemple), relancez 01 puis 02.
- `02` utilise `SET TIMESTAMP` pour dater l'historique dans le passé : il faut un utilisateur comme `root`.

## 3. Lancer le programme Python

```bash
pip install pymysql
DB_PASSWORD=root python3 python/demo_mysql.py
```

Variables possibles : `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`.
Lancez-le avant le script 04 si vous voulez des résultats lisibles et un jeu de données propre.

## Ce que montre chaque fichier

| Exigence | Fichier |
|---|---|
| ≥ 5 lignes par table principale | `02_donnees_supplementaires.sql` (affiche les volumes à la fin) |
| Sélection/filtrage, jointures, GROUP BY, sous-requêtes, requêtes élaborées | `03_requetes.sql` (sections A à E) |
| 2 index justifiés + EXPLAIN avant/après | `04_index_explain.sql` |
| Connexion Python, requêtes, affichage | `demo_mysql.py` |

## Résultats EXPLAIN obtenus (MySQL 8.0, 20 000 entreprises, 50 000 événements)

| Requête | Avant | Après |
|---|---|---|
| `WHERE ville = 'Ville_7'` | `type=ALL`, `key=NULL`, `rows≈20 247` | `type=ref`, `key=idx_entreprise_ville`, `rows=400` |
| `WHERE type='transport' AND date_heure >= NOW()-7j` | `type=ALL`, `key=NULL`, `rows≈49 818` | `type=range`, `key=idx_evenement_type_date`, `rows=122` |


### 1. Récupérer le projet

```bash
git clone https://github.com/VOTRE-NOM/NOM-DU-DEPOT.git
cd NOM-DU-DEPOT/resource_app
```

### 2. Créer l'environnement virtuel et installer les dépendances

Windows (PowerShell) :

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Mac ou Linux :

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 3. Créer la base de données

Le script `resource_mcd_mysql.sql` (à la racine du dépôt) crée la base `resource_db`, les tables, les triggers, les vues, les procédures et un jeu d'essai.

> ⚠️ Le script **supprime et recrée** la base `resource_db` si elle existe déjà.

Avec la ligne de commande (depuis `resource_app/`) :

```bash
mysql -u root -p < ../resource_mcd_mysql.sql
```

Ou avec MySQL Workbench / DBeaver : ouvrez le fichier `resource_mcd_mysql.sql` et exécutez-le en entier.

### 4. Configurer la connexion

Copiez le fichier modèle, puis modifiez-le :

```powershell
copy .env.example .env
```

Contenu du fichier `.env` :

```
FLASK_APP=run.py
SECRET_KEY=une-valeur-secrete-de-votre-choix
DATABASE_URL=mysql+pymysql://root:VOTRE_MOT_DE_PASSE@localhost:3306/resource_db?charset=utf8mb4
```

Remplacez `VOTRE_MOT_DE_PASSE` par le mot de passe de votre utilisateur MySQL. Si le mot de passe contient `@`, `#` ou `/`, remplacez ces caractères par `%40`, `%23` et `%2F`.

Le fichier `.env` contient des informations privées et n'est pas envoyé sur Git.

## Lancer l'application

Vérifiez d'abord la connexion à la base :

```powershell
flask --app run check-db
```

Puis démarrez le serveur :

```powershell
flask --app run run --debug
```

Ouvrez **http://127.0.0.1:5000** dans votre navigateur. La page `/sante` affiche l'état de la connexion et le nombre de lignes de chaque table.

## Structure du projet

```
.
├── resource_mcd_mysql.sql     # Base de données : tables, triggers, vues, procédures, jeu d'essai
├── README.md
└── resource_app/
    ├── run.py                 # Point d'entrée
    ├── requirements.txt
    ├── .env.example           # Modèle de configuration
    └── app/
        ├── __init__.py        # Fabrique d'application, gestion des erreurs
        ├── config.py          # Configuration (lit .env)
        ├── extensions.py      # SQLAlchemy et protection CSRF
        ├── models.py          # Modèles liés aux tables existantes
        ├── db_utils.py        # Requêtes, procédures, messages d'erreur
        ├── helpers.py         # Code de passeport, pagination, libellés
        ├── blueprints/        # Une section par fichier (ressources, offres, matching...)
        ├── templates/         # Pages HTML (Jinja2)
        └── static/            # Styles et scripts
```

## Base de données

Le modèle compte **9 entités** : `ENTREPRISE`, `ROLE`, `RESSOURCE`, `MATERIAU`, `EVENEMENT`, `OFFRE`, `DEMANDE`, `TRANSACTION`, `SCENARIO`.

Les associations plusieurs-à-plusieurs deviennent des tables : `JOUER` (entreprise et rôle), `COMPOSER` (ressource et matériau, avec pourcentage) et `CORRESPONDRE` (offre et demande, avec score). Une table technique, `DISTANCE_VILLE`, sert au calcul des distances.

### Ce que la base fait elle-même

L'application ne reproduit pas ces règles : elles vivent dans MySQL.

| Élément | Rôle |
|---|---|
| Trigger `RESSOURCE` (insertion) | Crée automatiquement l'événement de **production** |
| Trigger `RESSOURCE` (modification) | Interdit de changer le producteur d'origine ; enregistre les **changements de localisation** |
| Triggers `EVENEMENT` | Interdisent toute modification et toute suppression : l'historique est immuable |
| Triggers `COMPOSER` | Refusent une composition dépassant 100 % |
| Trigger `OFFRE` | Vérifie que l'éditeur est propriétaire et que la quantité ne dépasse pas le stock |
| Triggers `TRANSACTION` | Vérifient que le vendeur est propriétaire ; puis changent le propriétaire, ajoutent l'événement de **vente** et clôturent les offres |
| Fonction `fn_distance` | Distance entre deux villes |
| Vue `v_matching` | Offres et demandes compatibles, avec le score |
| Vues `v_historique_ressource`, `v_ressources_multi_proprietaires`, `v_composition_incomplete`, `v_comparaison_scenarios` | Historique, changements de propriétaire, qualité des données, classement des scénarios |
| Procédure `sp_generer_correspondances` | Enregistre les correspondances dans `CORRESPONDRE` |
| Procédure `sp_ressources_inutilisees` | Liste les ressources sans événement depuis X jours |

Les refus des triggers (`SQLSTATE 45000`) sont affichés dans l'application sous forme d'alertes en français.

**Score de compatibilité** (sur 100) : 40 points de proximité, 30 points de qualité, 30 points pour la part du matériau recherché dans la ressource.

## Règles de gestion

1. Une ressource a **un seul producteur d'origine** et **un seul propriétaire actuel**.
2. Une ressource a **une seule localisation actuelle**.
3. Une ressource est composée d'**un ou plusieurs matériaux**, dont les pourcentages totalisent 100 %.
4. **L'historique n'est jamais supprimé** : il s'enrichit à chaque événement.
5. Une transaction concerne un **vendeur** (propriétaire actuel) et un **acheteur différents**, et met à jour le propriétaire.
6. Une entreprise peut avoir **plusieurs rôles**.
7. Une offre porte sur une ressource ; une demande vise un matériau.

## Scénario de démonstration

Le jeu d'essai contient l'entreprise **AluMaroc** (Casablanca), **800 kg d'aluminium** de qualité 96 %, une offre ouverte, la demande d'**Atlas Transform** (Tanger, 340 km) et trois scénarios de seconde vie.

1. Ouvrez le **tableau de bord** : les indicateurs et les graphiques s'affichent.
2. Choisissez **AluMaroc** comme entreprise active, puis ouvrez le passeport de la ressource `RS-ALU-00001` : la chronologie montre l'événement de **production** créé automatiquement.
3. Allez dans **Matching** : l'offre de 800 kg correspond à la demande d'Atlas Transform. Cliquez sur **Enregistrer les correspondances**.
4. Cliquez sur **Créer la transaction** et validez : Atlas Transform devient propriétaire, un événement de **vente** apparaît, et l'offre est clôturée.
5. Toujours en tant qu'AluMaroc, essayez de vendre à nouveau la même ressource : le message du trigger s'affiche (« le vendeur n'est pas le propriétaire actuel de la ressource »).
6. Créez une ressource dont la composition totalise **90 %** : le formulaire la refuse, côté navigateur et côté serveur.
7. Ouvrez la **comparaison des scénarios** de la ressource : trois scénarios classés par gain net, avec graphiques.
8. Modifiez la **localisation** d'une ressource : un événement de changement de localisation apparaît dans l'historique.
9. Ouvrez les **Rapports** : les cinq sections retournent des résultats.
10. Vérifiez qu'**aucun bouton** ne permet de modifier ou supprimer un événement.

## Dépannage

| Problème | Cause probable et solution |
|---|---|
| `Access denied for user 'root'@'localhost'` | Le mot de passe de `.env` est faux. Testez-le dans MySQL Workbench, corrigez `.env`, puis relancez l'application. |
| `Unknown database 'resource_db'` | Le script SQL n'a pas été exécuté (étape 3 de l'installation). |
| `Can't connect to MySQL server` | Le serveur MySQL n'est pas démarré, ou le port n'est pas 3306. |
| `ERR_CONNECTION_RESET` dans le navigateur | Le serveur Flask n'est pas lancé ou a planté : regardez le terminal. Essayez aussi un autre port : `flask --app run run --debug --port 5001`. |
| `Activate.ps1 cannot be loaded` (PowerShell) | Exécutez `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`, puis réactivez l'environnement. |
| Le fichier `.env` n'est pas pris en compte | Il doit s'appeler exactement `.env`, se trouver dans `resource_app/`, et le serveur doit être relancé. |

## Auteur

Projet universitaire — Master Data & IA, module Bases de Données Relationnelles.