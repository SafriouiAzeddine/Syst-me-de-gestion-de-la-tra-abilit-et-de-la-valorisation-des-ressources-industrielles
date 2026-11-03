# PROMPT FOR CURSOR — RE:SOURCE Flask Web Application

> Before sending this prompt: put `resource_mcd_mysql.sql` in the project folder and reference it in Cursor with `@resource_mcd_mysql.sql`. It is the source of truth for the database.

---

## 1. Your role and the goal

You are a senior full-stack Python developer. Build a complete, working web application with **Flask** (backend) and **Jinja2 + Bootstrap 5** (frontend) for an information system called **RE:SOURCE**, an *Intelligent Resource Lifecycle & Second-Life Platform*.

The application sits on top of an **existing MySQL database** that already contains tables, constraints, triggers, views, a function and stored procedures (`resource_mcd_mysql.sql`). **Do not recreate or alter the schema.** The app must use it and respect it.

This is a university project for a *Relational Databases* course (Master Data & AI). Code quality, a clear structure and a demonstrable use of the database features (joins, aggregations, views, triggers, procedures) matter more than visual fireworks.

## 2. Business context

Companies produce industrial by-products ("waste") that can be a resource for other companies. RE:SOURCE gives each resource a **digital passport** and a **memory** (a history of events that is never deleted), connects the actors, and compares the possible **second lives** of a resource: direct reuse, transformation, recycling, or other valorisation.

Core idea: instead of asking "where can I sell this material?", ask "what are the possible lives of this resource, and under which conditions?".

Concrete example used for demos: *800 kg of aluminium scraps, quality 96 %, produced by company A in Casablanca*. The system searches interested companies, then compares scenarios.

## 3. Technical stack (mandatory)

- Python 3.11+, **Flask 3** with the **application factory pattern** and **Blueprints**
- **Flask-SQLAlchemy 3** (ORM models mapped onto the *existing* tables, never `db.create_all()`), driver **PyMySQL**
- **Flask-WTF** (forms + CSRF), **python-dotenv** (configuration)
- Frontend: **Jinja2 templates**, **Bootstrap 5.3** and **Bootstrap Icons** via CDN, **Chart.js** via CDN. No React/Vue/SPA.
- Database: **MySQL 8.0.16+** (the triggers and CHECK constraints require it). Do not use SQLite.
- User interface language: **French** (labels, buttons, flash messages, page titles). Code, comments, variable names and the README: English. Database table and column names stay exactly as they are (French, without accents).

## 4. Database (source of truth: `resource_mcd_mysql.sql`)

Database name: `resource_db`. Table names are **uppercase** (case-sensitive on Linux): use `__tablename__ = "RESSOURCE"` etc. The table `TRANSACTION` is valid unquoted in MySQL.

### 4.1 Tables

```
ROLE(id_role PK, libelle UNIQUE)
ENTREPRISE(id_entreprise PK, nom, secteur, ville)
JOUER(id_entreprise FK, id_role FK, date_debut)                 -- PK (id_entreprise, id_role)
MATERIAU(id_materiau PK, nom UNIQUE, categorie, proprietes)
RESSOURCE(id_ressource PK, quantite, unite, qualite, statut, localisation_actuelle,
          date_disponibilite, id_producteur FK->ENTREPRISE, id_proprietaire FK->ENTREPRISE)
COMPOSER(id_ressource FK, id_materiau FK, pourcentage)          -- PK (id_ressource, id_materiau)
EVENEMENT(id_evenement PK, type, date_heure, description,
          id_ressource FK, id_entreprise FK)
OFFRE(id_offre PK, date_publication, quantite_proposee, prix, statut,
      id_entreprise FK, id_ressource FK)
DEMANDE(id_demande PK, quantite_requise, qualite_min, distance_max, budget,
        date_limite, statut, id_entreprise FK, id_materiau FK)
CORRESPONDRE(id_offre FK, id_demande FK, score_compatibilite, distance_km)  -- PK (id_offre, id_demande)
TRANSACTION(id_transaction PK, date_transaction, quantite, prix,
            id_ressource FK, id_vendeur FK->ENTREPRISE, id_acheteur FK->ENTREPRISE)
SCENARIO(id_scenario PK, type, cout_estime, valeur_estimee, distance_km,
         impact_environnemental, id_ressource FK)
DISTANCE_VILLE(ville_a, ville_b, distance_km)                   -- PK (ville_a, ville_b), technical table
```

### 4.2 Allowed values (CHECK constraints)

- `RESSOURCE.statut`: `disponible`, `reservee`, `en_transformation`, `transformee`, `recyclee`
- `RESSOURCE.qualite`: 0 to 100; `quantite` > 0
- `EVENEMENT.type`: `production`, `decoupe`, `stockage`, `transport`, `controle`, `transformation`, `vente`, `changement_localisation`
- `OFFRE.statut`: `ouverte`, `cloturee`, `annulee`
- `DEMANDE.statut`: `ouverte`, `satisfaite`, `annulee`; `distance_max` > 0 and NOT NULL; `qualite_min` 0 to 100
- `SCENARIO.type`: `reutilisation`, `transformation`, `recyclage`, `autre`
- `COMPOSER.pourcentage`: > 0 and <= 100
- `TRANSACTION`: `id_vendeur <> id_acheteur`

### 4.3 What the database already does (do NOT duplicate this logic in Python)

**Triggers**
- `EVENEMENT`: any UPDATE or DELETE is refused (history is immutable).
- `RESSOURCE` after insert: automatically inserts a `production` event. **The app must not insert it.**
- `RESSOURCE` before update: `id_producteur` cannot change.
- `RESSOURCE` after update: when `localisation_actuelle` changes, a `changement_localisation` event is inserted automatically.
- `COMPOSER` before insert/update: the sum of percentages of one resource cannot exceed 100.
- `OFFRE` before insert: the publishing company must be the current owner of the resource, and `quantite_proposee` cannot exceed the resource quantity.
- `TRANSACTION` before insert: the seller must be the current owner of the resource.
- `TRANSACTION` after insert: sets `RESSOURCE.id_proprietaire` to the buyer, inserts a `vente` event, and closes the seller's open offers on that resource. **The app must not do these three things itself.**

All trigger refusals raise `SQLSTATE '45000'` with a French message. Catch the SQLAlchemy/PyMySQL exception (`sqlalchemy.exc.DBAPIError`, message in `exc.orig.args[1]`) and display that message to the user in a Bootstrap `alert-danger` flash. Also translate `IntegrityError` (foreign key, CHECK, duplicate) into friendly French messages.

**Function**
- `fn_distance(ville1, ville2)` returns the distance in km from `DISTANCE_VILLE` (0 if same city, NULL if unknown).

**Views** (query them with `db.session.execute(text(...))`, or map them as read-only models)
- `v_matching(id_offre, id_demande, id_ressource, entreprise_offre, entreprise_demande, materiau, pourcentage, qualite, quantite_proposee, quantite_requise, prix, budget, distance_km, score_compatibilite)`: compatible offer/demand pairs (material, quality, quantity, budget, deadline, distance).
- `v_historique_ressource(id_ressource, date_heure, type, description, acteur)`
- `v_ressources_multi_proprietaires(id_ressource, id_producteur, id_proprietaire, nb_changements)`
- `v_composition_incomplete(id_ressource, total_pourcentage)`
- `v_comparaison_scenarios(id_ressource, id_scenario, type, cout_estime, valeur_estimee, gain_net, distance_km, impact_environnemental, rang)`

**Stored procedures**
- `sp_generer_correspondances()`: fills/updates `CORRESPONDRE` from `v_matching`. No result set.
- `sp_ressources_inutilisees(IN p_jours INT)`: returns a result set of available resources with no event for more than `p_jours` days (columns: `id_ressource, quantite, unite, localisation_actuelle, dernier_evenement, jours_inactivite`). Because it returns a result set, call it through the raw PyMySQL cursor (`connection.connection.cursor()` then `callproc`) and `fetchall()`.

### 4.4 Business rules the app must respect

1. A resource has exactly one origin producer (never editable) and one current owner (changes only through a transaction).
2. A resource has one current location (`localisation_actuelle`, stored as a city name that must exist in `DISTANCE_VILLE` or in `ENTREPRISE.ville`).
3. A resource is composed of one or more materials whose percentages total 100 %. The form must validate the total = 100 on the client and on the server.
4. History is never deleted or edited: **no edit/delete buttons for events anywhere**.
5. A transaction has a seller different from the buyer; the seller is the current owner.
6. A company may have several roles (table `JOUER`).
7. An offer targets one resource; a demand targets one material; matching links offers and demands.

## 5. Application features and pages

Navigation: a Bootstrap sidebar or navbar with the sections below. Include an **"Acting company" selector** in the navbar: the user picks which `ENTREPRISE` they act as, stored in the Flask session (`session["entreprise_id"]`). There is no login system in this version. Forms for offers, demands and transactions use the acting company by default (seller of a transaction, publisher of an offer, issuer of a demand).

### 5.1 Dashboard (`/`)
- KPI cards: number of resources (and total quantity), resources by status, open offers, open demands, number of stored matches, number of transactions.
- Chart.js charts: resources by status (doughnut), resources by material (bar), transactions per month (line).
- Two simple indicators computed with SQL (show the formula in a tooltip): *Resource Utilization Rate* = % of resources that have at least one transaction or status `transformee`/`recyclee`; *Traceability level* = average number of events per resource.
- Table of the 10 latest events across all resources, and the top 5 matches by score.

### 5.2 Companies (`/entreprises`)
- List with search (name, sector, city) and pagination; create, edit, delete.
- The form manages the company's **roles** (multi-select on `ROLE`, with `date_debut` for each, stored in `JOUER`). A company must have at least one role.
- Detail page: roles, resources produced, resources currently owned, offers, demands, transactions as seller and as buyer.
- Deleting a company that is referenced must show a friendly message instead of crashing.

### 5.3 Materials (`/materiaux`) and roles
- Simple CRUD for `MATERIAU` (name, category, properties). Role list management (`ROLE`) can be a small page.

### 5.4 Resources and digital passport (`/ressources`)
- List with filters (status, material, owner, city, quality range) and pagination. Show a **passport code** such as `RS-ALU-00042`, built in Python as `RS-<first 3 letters of the main material, uppercase>-<id padded to 5 digits>`. The main material is the one with the highest percentage in `COMPOSER`. This code is a display value only, not stored.
- **Create form**: quantity, unit, quality, status, location (select), availability date, producer (defaults to the acting company; the owner is set equal to the producer at creation), and a **dynamic composition table** (rows: material + percentage; add/remove row with JavaScript; live total; submit blocked unless total = 100). Insert `RESSOURCE` then `COMPOSER` rows in **one transaction**. Do not insert the production event (trigger).
- **Edit form**: producer and owner are read-only. Changing the location is allowed (the trigger logs it).
- **Passport page** (`/ressources/<id>`), the most important page, with Bootstrap tabs:
  1. *Informations*: all fields, status badge, producer, current owner.
  2. *Composition*: materials with percentage progress bars.
  3. *Historique*: a **vertical timeline** from `v_historique_ressource` (date, event type with an icon, description, actor). A button "Ajouter un événement" opens a form limited to the types `decoupe`, `stockage`, `transport`, `controle`, `transformation` (the types `production`, `vente`, `changement_localisation` are automatic).
  4. *Offres et correspondances*: offers on this resource and their matches.
  5. *Transactions*: ownership changes in chronological order.
  6. *Scénarios*: table + Chart.js bar chart (see 5.8).
- Deleting a resource is not offered (history must be preserved).

### 5.5 Offers (`/offres`)
- List with filters (status, material, company); create an offer by choosing among the resources **owned by the acting company**; quantity and price; close or cancel an offer (status change).
- Show the number of compatible demands for each open offer (from `v_matching`).

### 5.6 Demands (`/demandes`)
- List with filters; create a demand: material, required quantity, minimum quality, **maximum distance (km, required)**, budget (optional), deadline (optional); change status (`satisfaite`, `annulee`).
- For each open demand, a link to "Offres compatibles" showing its rows in `v_matching`.

### 5.7 Matching (`/matching`)
- Table from `v_matching` ordered by `score_compatibilite` descending, with filters by demand, material and minimum score. Show the score as a colored progress bar and the distance in km.
- Button **"Enregistrer les correspondances"** calling `sp_generer_correspondances()`, then displaying the stored rows of `CORRESPONDRE` joined with offer and demand details.
- On each match row, a button **"Créer la transaction"** that opens the transaction form pre-filled (resource, seller = offer company, buyer = demand company, quantity, price).
- Add a short "How the score works" box: 40 points proximity + 30 points quality + 30 points share of the material in the resource.

### 5.8 Second-life scenarios (`/scenarios`)
- Create a scenario for a resource: type (four values), estimated cost, estimated value, distance, environmental impact.
- **Comparison page per resource**: table from `v_comparaison_scenarios` ordered by rank, with the net gain highlighted (rank 1 = recommended, green badge), plus a grouped bar chart (cost vs value per scenario). Add a sentence explaining that the system proposes options and does not impose a solution.

### 5.9 Transactions (`/transactions`)
- List and detail; create form: resource (owned by the seller), buyer (a company different from the seller), quantity, price, date. After success, flash the message "Propriétaire mis à jour" and redirect to the resource passport so that the new `vente` event is visible.
- There is no edit and no delete for transactions.

### 5.10 Reports (`/rapports`)
One page with sections that answer the five business questions of the project, each with its own short form or table:
1. Resources unused for more than **X days** (input X, uses `sp_ressources_inutilisees`).
2. Resources compatible with a chosen demand within **X km** (select a demand, input X, filter `v_matching`).
3. Full history of a chosen resource, including transformations (select a resource, uses `v_historique_ressource`).
4. Resources that changed owner several times (`v_ressources_multi_proprietaires`).
5. Possible second-life scenarios of a chosen resource (`v_comparaison_scenarios`).
Plus a data quality block: resources whose composition is not 100 % (`v_composition_incomplete`) with a link to fix each one.

### 5.11 Distances (`/distances`)
Small CRUD page for `DISTANCE_VILLE` (city A, city B, km) so that matching works for new cities. Show a warning on the resource and demand forms when a distance is missing.

## 6. Project structure

```
resource_app/
├── app/
│   ├── __init__.py          # create_app(), extensions, blueprint registration, error handlers
│   ├── config.py            # Config class reading .env
│   ├── extensions.py        # db = SQLAlchemy(), csrf = CSRFProtect()
│   ├── models.py            # ORM models mapped to existing tables (read the SQL file)
│   ├── db_utils.py          # run_view(), call_procedure(), friendly_db_error()
│   ├── forms.py             # Flask-WTF forms
│   ├── blueprints/
│   │   ├── dashboard.py  entreprises.py  materiaux.py  ressources.py
│   │   ├── offres.py  demandes.py  matching.py  scenarios.py
│   │   ├── transactions.py  rapports.py  distances.py
│   ├── templates/           # base.html + one folder per blueprint + partials (_pagination, _flash)
│   └── static/              # css/custom.css, js/composition.js, js/charts.js
├── requirements.txt
├── .env.example
├── .gitignore
├── run.py
└── README.md
```

## 7. Coding requirements

- Application factory and blueprints, as above. One responsibility per module.
- ORM models must match the schema exactly (types, nullability, foreign keys, relationships with `back_populates`). Do **not** call `db.create_all()`.
- Use ORM queries for CRUD; use `text()` or the views for matching, reporting and procedures. Use bound parameters everywhere (no string formatting in SQL).
- Wrap writes in transactions: `db.session.commit()` in a `try`, `db.session.rollback()` on exception, then flash the friendly message.
- Server-side validation with Flask-WTF for every form, plus HTML5 attributes on the client. CSRF on all POST requests.
- Pagination (10 or 20 rows) and search on every list page.
- Templates extend `base.html`. Reusable macros for status badges, flash messages and pagination. Responsive layout (mobile friendly tables with `table-responsive`).
- Status badge colors: `disponible` green, `reservee` yellow, `en_transformation` blue, `transformee` and `recyclee` grey; `ouverte` green, `cloturee` grey, `annulee` red.
- Handle 404 and 500 with custom pages. No stack trace shown to the user.
- Comments in English, short docstrings on non-trivial functions, type hints where useful.

## 8. Configuration and run instructions (generate in README.md)

`.env.example`:
```
FLASK_APP=run.py
SECRET_KEY=change-me
DATABASE_URL=mysql+pymysql://root:password@localhost:3306/resource_db?charset=utf8mb4
```

README must explain, step by step: create the virtual environment, `pip install -r requirements.txt`, run `resource_mcd_mysql.sql` in MySQL (it creates `resource_db` and the sample data), copy `.env.example` to `.env`, then `flask --app run run --debug`. Add a section "Demo scenario" with the steps below and a screenshot checklist.

`requirements.txt` (pin reasonable versions): Flask, Flask-SQLAlchemy, SQLAlchemy, PyMySQL, cryptography, Flask-WTF, WTForms, email-validator, python-dotenv.

## 9. Demo scenario the app must support end to end (acceptance test)

Using the sample data from the SQL file:
1. Open the dashboard: counts and charts display.
2. Select "AluMaroc" as acting company. Open the passport of the 800 kg aluminium resource: the timeline shows the automatic `production` event.
3. Go to Matching: the offer of 800 kg aluminium matches the demand of "Atlas Transform" (Tanger, 340 km). Click "Enregistrer les correspondances": the stored matches appear.
4. Click "Créer la transaction" from the match, confirm: the resource owner becomes "Atlas Transform", a `vente` event appears in the timeline, the offer is closed.
5. Try to sell the same resource again as "AluMaroc": the app displays the trigger error message in French.
6. Try to create a resource whose composition totals 90 %: blocked client side and server side.
7. Open the scenario comparison of the aluminium resource: three scenarios ranked by net gain with a chart.
8. Open Reports: all five sections return data, and the "unused for more than 30 days" report works with the procedure.
9. Change a resource location: a `changement_localisation` event appears automatically.
10. Check that there is no way in the UI to edit or delete an event.

## 10. How to work (important)

Work in phases and finish each phase completely before the next one. After each phase, state what to run and how to test it.

1. Project skeleton, configuration, extensions, models mapped to the existing tables, base template, database connection check.
2. Companies, roles, materials, distances (CRUD).
3. Resources, composition form, passport page with timeline and manual events.
4. Offers, demands, matching page and procedure call.
5. Transactions with trigger error handling.
6. Scenarios and comparison charts.
7. Dashboard and reports.
8. Error pages, polish, README, final review against the acceptance test in section 9.

Do not invent new tables or columns. If something in the schema blocks a feature, tell me in a short note instead of changing the database. Prefer simple, readable code that a student can explain during an oral defence.
