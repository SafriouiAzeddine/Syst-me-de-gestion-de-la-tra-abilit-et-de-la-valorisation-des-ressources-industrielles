-- #####################################################################
--  PROJET RE:SOURCE - SCRIPT SQL COMPLET (MySQL 8.0.16+)
--  Master Data & IA - Bases de données relationnelles
--
--  Exécution : mysql --default-character-set=utf8mb4 -u root -p -t < projet_complet.sql
--
--  Correspondance avec les exigences du sujet :
--   4. MLD (tables, PK, FK, clés composées) ........ PARTIE 1 (en-tête + CREATE TABLE)
--   5. Implémentation MySQL + contraintes ........... PARTIE 1 (PK, FK, NOT NULL, UNIQUE, CHECK)
--   6. Peuplement (>= 5 lignes / table principale) .. PARTIE 1 (jeu minimal) + PARTIE 2
--   7. Triggers (règles métier expliquées) .......... PARTIE 1, section 3
--   8. Requêtes (filtrage, jointures, GROUP BY,
--      sous-requêtes, requêtes élaborées) ........... PARTIE 3
--   9. Index + EXPLAIN avant/après ................... PARTIE 4
--
--  ATTENTION : le script supprime et recrée la base resource_db.
--  La PARTIE 4 ajoute ~70 000 lignes de test (EVENEMENT est immuable) :
--  pour retrouver un jeu propre, ré-exécuter le script sans la PARTIE 4.
-- #####################################################################

-- ############ PARTIE 1 : SCHÉMA, TRIGGERS, VUES, PROCÉDURES, JEU MINIMAL ############
-- =====================================================================
--  RE:SOURCE - Système de gestion du cycle de vie et de la seconde vie
--  des ressources secondaires
--  Script MySQL 8.0.16 ou plus récent (CHECK appliqués, fonctions de fenêtre)
-- =====================================================================
--
--  MLD (clés primaires soulignées par #, clés étrangères précédées de →)
--
--  ROLE(#id_role, libelle)
--  ENTREPRISE(#id_entreprise, nom, secteur, ville)
--  JOUER(#id_entreprise →ENTREPRISE, #id_role →ROLE, date_debut)
--  MATERIAU(#id_materiau, nom, categorie, proprietes)
--  RESSOURCE(#id_ressource, quantite, unite, qualite, statut,
--            localisation_actuelle, date_disponibilite,
--            id_producteur →ENTREPRISE, id_proprietaire →ENTREPRISE)
--  COMPOSER(#id_ressource →RESSOURCE, #id_materiau →MATERIAU, pourcentage)
--  EVENEMENT(#id_evenement, type, date_heure, description,
--            id_ressource →RESSOURCE, id_entreprise →ENTREPRISE)
--  OFFRE(#id_offre, date_publication, quantite_proposee, prix, statut,
--        id_entreprise →ENTREPRISE, id_ressource →RESSOURCE)
--  DEMANDE(#id_demande, quantite_requise, qualite_min, distance_max,
--          budget, date_limite, statut,
--          id_entreprise →ENTREPRISE, id_materiau →MATERIAU)
--  CORRESPONDRE(#id_offre →OFFRE, #id_demande →DEMANDE,
--               score_compatibilite, distance_km)
--  TRANSACTION(#id_transaction, date_transaction, quantite, prix,
--              id_ressource →RESSOURCE, id_vendeur →ENTREPRISE,
--              id_acheteur →ENTREPRISE)
--  SCENARIO(#id_scenario, type, cout_estime, valeur_estimee, distance_km,
--           impact_environnemental, id_ressource →RESSOURCE)
--
--  Table technique hors MCD : DISTANCE_VILLE(#ville_a, #ville_b, distance_km)
--  (sert au calcul des distances pour le matching)
--
--  Règles de passage MCD -> MLD appliquées :
--   - association (1,1)-(0,N) : clé étrangère côté (1,1)
--     (PRODUIRE, DETENIR, CONCERNER, REALISER, PUBLIER, PORTER_SUR,
--      EMETTRE, CIBLER, ECHANGER, VENDRE, ACHETER, EVALUER)
--   - association (N,N) : nouvelle table (JOUER, COMPOSER, CORRESPONDRE)


DROP DATABASE IF EXISTS resource_db;
CREATE DATABASE resource_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE resource_db;

-- 1. TABLES ET CONTRAINTES


CREATE TABLE ROLE (
    id_role   INT AUTO_INCREMENT PRIMARY KEY,
    libelle   VARCHAR(50) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE ENTREPRISE (
    id_entreprise INT AUTO_INCREMENT PRIMARY KEY,
    nom           VARCHAR(100) NOT NULL,
    secteur       VARCHAR(100),
    ville         VARCHAR(80) NOT NULL
) ENGINE=InnoDB;

-- Association JOUER (1,N) - (0,N)
CREATE TABLE JOUER (
    id_entreprise INT NOT NULL,
    id_role       INT NOT NULL,
    date_debut    DATE NOT NULL DEFAULT (CURRENT_DATE),
    PRIMARY KEY (id_entreprise, id_role),
    FOREIGN KEY (id_entreprise) REFERENCES ENTREPRISE(id_entreprise),
    FOREIGN KEY (id_role)       REFERENCES ROLE(id_role)
) ENGINE=InnoDB;

CREATE TABLE MATERIAU (
    id_materiau INT AUTO_INCREMENT PRIMARY KEY,
    nom         VARCHAR(100) NOT NULL UNIQUE,
    categorie   VARCHAR(50),
    proprietes  TEXT
) ENGINE=InnoDB;

-- PRODUIRE et DETENIR deviennent id_producteur et id_proprietaire
CREATE TABLE RESSOURCE (
    id_ressource          INT AUTO_INCREMENT PRIMARY KEY,
    quantite              DECIMAL(12,2) NOT NULL,
    unite                 VARCHAR(20)   NOT NULL DEFAULT 'kg',
    qualite               DECIMAL(5,2)  NOT NULL,
    statut                VARCHAR(20)   NOT NULL DEFAULT 'disponible',
    localisation_actuelle VARCHAR(80)   NOT NULL,
    date_disponibilite    DATE,
    id_producteur         INT NOT NULL,
    id_proprietaire       INT NOT NULL,
    CONSTRAINT ck_ressource_quantite CHECK (quantite > 0),
    CONSTRAINT ck_ressource_qualite  CHECK (qualite BETWEEN 0 AND 100),
    CONSTRAINT ck_ressource_statut   CHECK (statut IN
        ('disponible','reservee','en_transformation','transformee','recyclee')),
    FOREIGN KEY (id_producteur)   REFERENCES ENTREPRISE(id_entreprise),
    FOREIGN KEY (id_proprietaire) REFERENCES ENTREPRISE(id_entreprise),
    INDEX idx_ressource_statut (statut)
) ENGINE=InnoDB;

-- Association COMPOSER (1,N) - (0,N)
CREATE TABLE COMPOSER (
    id_ressource INT NOT NULL,
    id_materiau  INT NOT NULL,
    pourcentage  DECIMAL(5,2) NOT NULL,
    PRIMARY KEY (id_ressource, id_materiau),
    CONSTRAINT ck_composer_pct CHECK (pourcentage > 0 AND pourcentage <= 100),
    FOREIGN KEY (id_ressource) REFERENCES RESSOURCE(id_ressource),
    FOREIGN KEY (id_materiau)  REFERENCES MATERIAU(id_materiau)
) ENGINE=InnoDB;

-- Historique : jamais supprimé ni modifié (voir triggers)
CREATE TABLE EVENEMENT (
    id_evenement INT AUTO_INCREMENT PRIMARY KEY,
    type         VARCHAR(30) NOT NULL,
    date_heure   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    description  TEXT,
    id_ressource INT NOT NULL,
    id_entreprise INT NOT NULL,
    CONSTRAINT ck_evenement_type CHECK (type IN
        ('production','decoupe','stockage','transport','controle',
         'transformation','vente','changement_localisation')),
    FOREIGN KEY (id_ressource)  REFERENCES RESSOURCE(id_ressource),
    FOREIGN KEY (id_entreprise) REFERENCES ENTREPRISE(id_entreprise),
    INDEX idx_evenement_ressource (id_ressource, date_heure)
) ENGINE=InnoDB;

CREATE TABLE OFFRE (
    id_offre          INT AUTO_INCREMENT PRIMARY KEY,
    date_publication  DATE NOT NULL DEFAULT (CURRENT_DATE),
    quantite_proposee DECIMAL(12,2) NOT NULL,
    prix              DECIMAL(12,2) NOT NULL,
    statut            VARCHAR(20) NOT NULL DEFAULT 'ouverte',
    id_entreprise     INT NOT NULL,
    id_ressource      INT NOT NULL,
    CONSTRAINT ck_offre_quantite CHECK (quantite_proposee > 0),
    CONSTRAINT ck_offre_prix     CHECK (prix >= 0),
    CONSTRAINT ck_offre_statut   CHECK (statut IN ('ouverte','cloturee','annulee')),
    FOREIGN KEY (id_entreprise) REFERENCES ENTREPRISE(id_entreprise),
    FOREIGN KEY (id_ressource)  REFERENCES RESSOURCE(id_ressource),
    INDEX idx_offre_statut (statut)
) ENGINE=InnoDB;

CREATE TABLE DEMANDE (
    id_demande      INT AUTO_INCREMENT PRIMARY KEY,
    quantite_requise DECIMAL(12,2) NOT NULL,
    qualite_min     DECIMAL(5,2)  NOT NULL DEFAULT 0,
    distance_max    DECIMAL(8,2)  NOT NULL,
    budget          DECIMAL(12,2),
    date_limite     DATE,
    statut          VARCHAR(20) NOT NULL DEFAULT 'ouverte',
    id_entreprise   INT NOT NULL,
    id_materiau     INT NOT NULL,
    CONSTRAINT ck_demande_quantite CHECK (quantite_requise > 0),
    CONSTRAINT ck_demande_qualite  CHECK (qualite_min BETWEEN 0 AND 100),
    CONSTRAINT ck_demande_distance CHECK (distance_max > 0),
    CONSTRAINT ck_demande_statut   CHECK (statut IN ('ouverte','satisfaite','annulee')),
    FOREIGN KEY (id_entreprise) REFERENCES ENTREPRISE(id_entreprise),
    FOREIGN KEY (id_materiau)   REFERENCES MATERIAU(id_materiau),
    INDEX idx_demande_materiau (id_materiau, statut)
) ENGINE=InnoDB;

-- Association CORRESPONDRE (0,N) - (0,N)
CREATE TABLE CORRESPONDRE (
    id_offre            INT NOT NULL,
    id_demande          INT NOT NULL,
    score_compatibilite DECIMAL(5,2) NOT NULL,
    distance_km         DECIMAL(8,2),
    PRIMARY KEY (id_offre, id_demande),
    CONSTRAINT ck_correspondre_score CHECK (score_compatibilite BETWEEN 0 AND 100),
    FOREIGN KEY (id_offre)   REFERENCES OFFRE(id_offre),
    FOREIGN KEY (id_demande) REFERENCES DEMANDE(id_demande)
) ENGINE=InnoDB;

-- Pas d'action ON UPDATE / ON DELETE sur id_vendeur et id_acheteur :
-- MySQL les interdit sur les colonnes utilisées dans un CHECK.
CREATE TABLE TRANSACTION (
    id_transaction   INT AUTO_INCREMENT PRIMARY KEY,
    date_transaction DATE NOT NULL DEFAULT (CURRENT_DATE),
    quantite         DECIMAL(12,2) NOT NULL,
    prix             DECIMAL(12,2) NOT NULL,
    id_ressource     INT NOT NULL,
    id_vendeur       INT NOT NULL,
    id_acheteur      INT NOT NULL,
    CONSTRAINT ck_transaction_quantite CHECK (quantite > 0),
    CONSTRAINT ck_transaction_prix     CHECK (prix >= 0),
    -- RG6 : le vendeur et l'acheteur sont deux entreprises différentes
    CONSTRAINT ck_transaction_acteurs  CHECK (id_vendeur <> id_acheteur),
    FOREIGN KEY (id_ressource) REFERENCES RESSOURCE(id_ressource),
    FOREIGN KEY (id_vendeur)   REFERENCES ENTREPRISE(id_entreprise),
    FOREIGN KEY (id_acheteur)  REFERENCES ENTREPRISE(id_entreprise)
) ENGINE=InnoDB;

CREATE TABLE SCENARIO (
    id_scenario            INT AUTO_INCREMENT PRIMARY KEY,
    type                   VARCHAR(30) NOT NULL,
    cout_estime            DECIMAL(12,2) NOT NULL,
    valeur_estimee         DECIMAL(12,2) NOT NULL,
    distance_km            DECIMAL(8,2),
    impact_environnemental DECIMAL(10,2),
    id_ressource           INT NOT NULL,
    CONSTRAINT ck_scenario_type CHECK (type IN
        ('reutilisation','transformation','recyclage','autre')),
    CONSTRAINT ck_scenario_cout CHECK (cout_estime >= 0),
    FOREIGN KEY (id_ressource) REFERENCES RESSOURCE(id_ressource),
    INDEX idx_scenario_ressource (id_ressource)
) ENGINE=InnoDB;

-- Table technique (hors MCD) : distances routières entre villes
CREATE TABLE DISTANCE_VILLE (
    ville_a     VARCHAR(80) NOT NULL,
    ville_b     VARCHAR(80) NOT NULL,
    distance_km DECIMAL(8,2) NOT NULL,
    PRIMARY KEY (ville_a, ville_b),
    CONSTRAINT ck_distance_ville CHECK (ville_a <> ville_b AND distance_km > 0)
) ENGINE=InnoDB;

-- =====================================================================
-- 2. FONCTION : distance entre deux villes (symétrique)
-- =====================================================================
DELIMITER $$

CREATE FUNCTION fn_distance(p_ville1 VARCHAR(80), p_ville2 VARCHAR(80))
RETURNS DECIMAL(8,2)
READS SQL DATA
BEGIN
    DECLARE v_dist DECIMAL(8,2) DEFAULT NULL;
    IF p_ville1 = p_ville2 THEN
        RETURN 0;
    END IF;
    SELECT distance_km INTO v_dist
    FROM DISTANCE_VILLE
    WHERE (ville_a = p_ville1 AND ville_b = p_ville2)
       OR (ville_a = p_ville2 AND ville_b = p_ville1)
    LIMIT 1;
    RETURN v_dist;          -- NULL si la distance n'est pas renseignée
END$$

-- =====================================================================
-- 3. TRIGGERS
-- =====================================================================

-- RG5 : l'historique ne se modifie pas et ne se supprime pas
CREATE TRIGGER trg_evenement_bu BEFORE UPDATE ON EVENEMENT
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RG5 : un événement de l''historique ne peut pas être modifié';
END$$

CREATE TRIGGER trg_evenement_bd BEFORE DELETE ON EVENEMENT
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'RG5 : un événement de l''historique ne peut pas être supprimé';
END$$

-- RG5 : la création d'une ressource ouvre son historique (événement de production)
CREATE TRIGGER trg_ressource_ai AFTER INSERT ON RESSOURCE
FOR EACH ROW
BEGIN
    INSERT INTO EVENEMENT (type, description, id_ressource, id_entreprise)
    VALUES ('production', 'Création de la ressource dans le système',
            NEW.id_ressource, NEW.id_producteur);
END$$

-- RG1 : le producteur d'origine ne change jamais
CREATE TRIGGER trg_ressource_bu BEFORE UPDATE ON RESSOURCE
FOR EACH ROW
BEGIN
    IF NEW.id_producteur <> OLD.id_producteur THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RG1 : le producteur d''origine ne peut pas être modifié';
    END IF;
END$$

-- RG3 / RG5 : tout changement de localisation est tracé dans l'historique
CREATE TRIGGER trg_ressource_au AFTER UPDATE ON RESSOURCE
FOR EACH ROW
BEGIN
    IF NEW.localisation_actuelle <> OLD.localisation_actuelle THEN
        INSERT INTO EVENEMENT (type, description, id_ressource, id_entreprise)
        VALUES ('changement_localisation',
                CONCAT('De ', OLD.localisation_actuelle, ' vers ', NEW.localisation_actuelle),
                NEW.id_ressource, NEW.id_proprietaire);
    END IF;
END$$

-- RG4 : la somme des pourcentages d'une ressource ne dépasse jamais 100
-- (le total exact de 100 se contrôle avec la vue v_composition_incomplete)
CREATE TRIGGER trg_composer_bi BEFORE INSERT ON COMPOSER
FOR EACH ROW
BEGIN
    DECLARE v_total DECIMAL(7,2);
    SELECT COALESCE(SUM(pourcentage), 0) INTO v_total
    FROM COMPOSER
    WHERE id_ressource = NEW.id_ressource AND id_materiau <> NEW.id_materiau;
    IF v_total + NEW.pourcentage > 100 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RG4 : la somme des pourcentages dépasse 100';
    END IF;
END$$

CREATE TRIGGER trg_composer_bu BEFORE UPDATE ON COMPOSER
FOR EACH ROW
BEGIN
    DECLARE v_total DECIMAL(7,2);
    SELECT COALESCE(SUM(pourcentage), 0) INTO v_total
    FROM COMPOSER
    WHERE id_ressource = NEW.id_ressource AND id_materiau <> NEW.id_materiau;
    IF v_total + NEW.pourcentage > 100 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RG4 : la somme des pourcentages dépasse 100';
    END IF;
END$$

-- Règle complémentaire : une offre est publiée par le propriétaire de la
-- ressource, et ne dépasse pas la quantité disponible
CREATE TRIGGER trg_offre_bi BEFORE INSERT ON OFFRE
FOR EACH ROW
BEGIN
    DECLARE v_proprietaire INT;
    DECLARE v_quantite DECIMAL(12,2);
    SELECT id_proprietaire, quantite INTO v_proprietaire, v_quantite
    FROM RESSOURCE WHERE id_ressource = NEW.id_ressource;
    IF v_proprietaire <> NEW.id_entreprise THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Une offre doit être publiée par le propriétaire de la ressource';
    END IF;
    IF NEW.quantite_proposee > v_quantite THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'La quantité proposée dépasse la quantité de la ressource';
    END IF;
END$$

-- RG6 (complément) : le vendeur doit être le propriétaire actuel
CREATE TRIGGER trg_transaction_bi BEFORE INSERT ON TRANSACTION
FOR EACH ROW
BEGIN
    DECLARE v_proprietaire INT;
    SELECT id_proprietaire INTO v_proprietaire
    FROM RESSOURCE WHERE id_ressource = NEW.id_ressource;
    IF v_proprietaire <> NEW.id_vendeur THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'RG6 : le vendeur n''est pas le propriétaire actuel de la ressource';
    END IF;
END$$

-- RG6 : la transaction met à jour le propriétaire, enrichit l'historique
-- et clôture les offres ouvertes du vendeur sur cette ressource
CREATE TRIGGER trg_transaction_ai AFTER INSERT ON TRANSACTION
FOR EACH ROW
BEGIN
    UPDATE RESSOURCE
       SET id_proprietaire = NEW.id_acheteur
     WHERE id_ressource = NEW.id_ressource;

    INSERT INTO EVENEMENT (type, description, id_ressource, id_entreprise)
    VALUES ('vente',
            CONCAT('Cession à l''entreprise n° ', NEW.id_acheteur,
                   ' pour ', NEW.prix),
            NEW.id_ressource, NEW.id_vendeur);

    UPDATE OFFRE
       SET statut = 'cloturee'
     WHERE id_ressource = NEW.id_ressource
       AND id_entreprise = NEW.id_vendeur
       AND statut = 'ouverte';
END$$

-- =====================================================================
-- 4. PROCÉDURES
-- =====================================================================

-- Q1 : ressources disponibles sans événement depuis plus de p_jours jours
CREATE PROCEDURE sp_ressources_inutilisees(IN p_jours INT)
BEGIN
    SELECT r.id_ressource, r.quantite, r.unite, r.localisation_actuelle,
           MAX(ev.date_heure) AS dernier_evenement,
           DATEDIFF(CURRENT_DATE, MAX(ev.date_heure)) AS jours_inactivite
    FROM RESSOURCE r
    JOIN EVENEMENT ev ON ev.id_ressource = r.id_ressource
    WHERE r.statut = 'disponible'
    GROUP BY r.id_ressource, r.quantite, r.unite, r.localisation_actuelle
    HAVING DATEDIFF(CURRENT_DATE, MAX(ev.date_heure)) > p_jours
    ORDER BY jours_inactivite DESC;
END$$

-- Matching : enregistre dans CORRESPONDRE les paires offre/demande compatibles
CREATE PROCEDURE sp_generer_correspondances()
BEGIN
    INSERT INTO CORRESPONDRE (id_offre, id_demande, score_compatibilite, distance_km)
    SELECT id_offre, id_demande, MAX(score_compatibilite), MIN(distance_km)
    FROM v_matching
    GROUP BY id_offre, id_demande
    ON DUPLICATE KEY UPDATE
        score_compatibilite = VALUES(score_compatibilite),
        distance_km         = VALUES(distance_km);
END$$

DELIMITER ;

-- =====================================================================
-- 5. VUES
-- =====================================================================

-- Q3 : historique complet d'une ressource
CREATE VIEW v_historique_ressource AS
SELECT ev.id_ressource, ev.date_heure, ev.type, ev.description,
       en.nom AS acteur
FROM EVENEMENT ev
JOIN ENTREPRISE en ON en.id_entreprise = ev.id_entreprise
ORDER BY ev.id_ressource, ev.date_heure;

-- Q4 : ressources ayant changé plusieurs fois de propriétaire
CREATE VIEW v_ressources_multi_proprietaires AS
SELECT r.id_ressource, r.id_producteur, r.id_proprietaire,
       COUNT(t.id_transaction) AS nb_changements
FROM RESSOURCE r
JOIN TRANSACTION t ON t.id_ressource = r.id_ressource
GROUP BY r.id_ressource, r.id_producteur, r.id_proprietaire
HAVING COUNT(t.id_transaction) > 1;

-- RG4 : ressources dont la composition ne totalise pas 100 %
CREATE VIEW v_composition_incomplete AS
SELECT r.id_ressource,
       COALESCE(SUM(c.pourcentage), 0) AS total_pourcentage
FROM RESSOURCE r
LEFT JOIN COMPOSER c ON c.id_ressource = r.id_ressource
GROUP BY r.id_ressource
HAVING COALESCE(SUM(c.pourcentage), 0) <> 100;

-- Q2 : MATCHING - offres compatibles avec des demandes
--  Critères : matériau, qualité, quantité, budget, date limite, distance.
--  Score (sur 100) = 40 x proximité + 30 x qualité + 30 x part du matériau
CREATE VIEW v_matching AS
SELECT o.id_offre, d.id_demande, r.id_ressource,
       eo.nom  AS entreprise_offre,
       ed.nom  AS entreprise_demande,
       m.nom   AS materiau,
       c.pourcentage,
       r.qualite,
       o.quantite_proposee, d.quantite_requise,
       o.prix, d.budget,
       fn_distance(r.localisation_actuelle, ed.ville) AS distance_km,
       ROUND( 40 * (1 - fn_distance(r.localisation_actuelle, ed.ville) / d.distance_max)
            + 30 * r.qualite / 100
            + 30 * c.pourcentage / 100, 2) AS score_compatibilite
FROM OFFRE o
JOIN RESSOURCE  r  ON r.id_ressource = o.id_ressource
JOIN COMPOSER   c  ON c.id_ressource = r.id_ressource
JOIN DEMANDE    d  ON d.id_materiau  = c.id_materiau
JOIN MATERIAU   m  ON m.id_materiau  = d.id_materiau
JOIN ENTREPRISE eo ON eo.id_entreprise = o.id_entreprise
JOIN ENTREPRISE ed ON ed.id_entreprise = d.id_entreprise
WHERE o.statut = 'ouverte'
  AND d.statut = 'ouverte'
  AND o.id_entreprise <> d.id_entreprise
  AND r.qualite >= d.qualite_min
  AND o.quantite_proposee >= d.quantite_requise
  AND (d.budget IS NULL OR o.prix <= d.budget)
  AND (d.date_limite IS NULL OR d.date_limite >= CURRENT_DATE)
  AND fn_distance(r.localisation_actuelle, ed.ville) <= d.distance_max;

-- Q5 : comparaison des scénarios de seconde vie (classés par gain net)
CREATE VIEW v_comparaison_scenarios AS
SELECT s.id_ressource, s.id_scenario, s.type,
       s.cout_estime, s.valeur_estimee,
       (s.valeur_estimee - s.cout_estime) AS gain_net,
       s.distance_km, s.impact_environnemental,
       RANK() OVER (PARTITION BY s.id_ressource
                    ORDER BY (s.valeur_estimee - s.cout_estime) DESC) AS rang
FROM SCENARIO s;

-- =====================================================================
-- 6. JEU D'ESSAI
-- =====================================================================

INSERT INTO ROLE (libelle) VALUES
 ('producteur'), ('acheteur'), ('transformateur'),
 ('recycleur'), ('transporteur'), ('expert');

INSERT INTO ENTREPRISE (nom, secteur, ville) VALUES
 ('AluMaroc',        'Métallurgie', 'Casablanca'),   -- 1
 ('PlastiRecycle',   'Recyclage',   'Rabat'),        -- 2
 ('Atlas Transform', 'Industrie',   'Tanger'),       -- 3
 ('BatiPro',         'BTP',         'Marrakech'),    -- 4
 ('TransLog',        'Transport',   'Casablanca');   -- 5

INSERT INTO JOUER (id_entreprise, id_role) VALUES
 (1,1), (1,2), (2,1), (2,4), (3,3), (3,2), (4,2), (5,5);

INSERT INTO MATERIAU (nom, categorie, proprietes) VALUES
 ('Aluminium', 'métal',      'Léger, recyclable à l''infini'),   -- 1
 ('Plastique PET', 'plastique', 'Recyclage industriel possible'),-- 2
 ('Acier',     'métal',      'Résistant, magnétique');           -- 3

-- Distances routières indicatives en km (à remplacer par vos propres valeurs)
INSERT INTO DISTANCE_VILLE (ville_a, ville_b, distance_km) VALUES
 ('Casablanca','Rabat',90),      ('Casablanca','Tanger',340),
 ('Casablanca','Marrakech',240), ('Rabat','Tanger',250),
 ('Rabat','Marrakech',330),      ('Tanger','Marrakech',580);

-- Les triggers créent automatiquement l'événement « production »
INSERT INTO RESSOURCE (quantite, unite, qualite, statut, localisation_actuelle,
                       date_disponibilite, id_producteur, id_proprietaire) VALUES
 (800,  'kg', 96, 'disponible', 'Casablanca', CURRENT_DATE, 1, 1),  -- 1 chutes d'aluminium
 (2000, 'kg', 85, 'disponible', 'Rabat',      CURRENT_DATE, 2, 2);  -- 2 plastique PET

INSERT INTO COMPOSER (id_ressource, id_materiau, pourcentage) VALUES
 (1, 1, 100), (2, 2, 100);

INSERT INTO OFFRE (quantite_proposee, prix, id_entreprise, id_ressource) VALUES
 (800,  12000, 1, 1),
 (2000,  8000, 2, 2);

INSERT INTO DEMANDE (quantite_requise, qualite_min, distance_max, budget,
                     date_limite, id_entreprise, id_materiau) VALUES
 (500,  90, 400, 15000, DATE_ADD(CURRENT_DATE, INTERVAL 30 DAY), 3, 1),
 (1500, 80, 400,  9000, DATE_ADD(CURRENT_DATE, INTERVAL 30 DAY), 4, 2);

INSERT INTO SCENARIO (type, cout_estime, valeur_estimee, distance_km,
                      impact_environnemental, id_ressource) VALUES
 ('reutilisation',  500, 12000, 340, 40, 1),
 ('transformation', 3000, 15000, 90, 120, 1),
 ('recyclage',      1500,  9000, 90, 200, 1);

-- =====================================================================
-- 7. REQUÊTES DE TEST (questions métier de la fiche projet)
-- =====================================================================

-- Matching : offres compatibles avec les demandes, puis enregistrement
SELECT * FROM v_matching ORDER BY score_compatibilite DESC;
CALL sp_generer_correspondances();
SELECT * FROM CORRESPONDRE;

-- Q5 : comparaison des scénarios pour la ressource 1
SELECT * FROM v_comparaison_scenarios WHERE id_ressource = 1 ORDER BY rang;

-- Une vente : le trigger met à jour le propriétaire et l'historique
INSERT INTO TRANSACTION (quantite, prix, id_ressource, id_vendeur, id_acheteur)
VALUES (800, 12000, 1, 1, 3);

-- Q3 : historique complet de la ressource 1
SELECT * FROM v_historique_ressource WHERE id_ressource = 1;

-- Q1 : ressources inutilisées depuis plus de 30 jours
CALL sp_ressources_inutilisees(30);

-- Q4 : ressources ayant changé plusieurs fois de propriétaire
SELECT * FROM v_ressources_multi_proprietaires;

-- RG4 : ressources dont la composition n'est pas complète
SELECT * FROM v_composition_incomplete;

-- Tests de contraintes (chacun doit être refusé) :
-- UPDATE EVENEMENT SET type = 'stockage' WHERE id_evenement = 1;            -- RG5
-- DELETE FROM EVENEMENT WHERE id_evenement = 1;                              -- RG5
-- INSERT INTO TRANSACTION (quantite, prix, id_ressource, id_vendeur, id_acheteur)
--   VALUES (10, 100, 2, 2, 2);                                               -- RG6
-- UPDATE RESSOURCE SET id_producteur = 5 WHERE id_ressource = 2;             -- RG1
-- INSERT INTO COMPOSER VALUES (2, 3, 50);                                    -- RG4


-- =====================================================================
-- PARTIE 2 : JEU DE DONNÉES COMPLÉMENTAIRE (>= 5 lignes par table principale)
-- =====================================================================
USE resource_db;


-- ---------- Entreprises (3 nouvelles -> 8 au total) ----------
INSERT INTO ENTREPRISE (nom, secteur, ville) VALUES
 ('FerroSteel',   'Métallurgie', 'Fès'),      -- 6
 ('EcoVerre',     'Verre',       'Agadir'),   -- 7
 ('TextilRecup',  'Textile',     'Fès');      -- 8

INSERT INTO JOUER (id_entreprise, id_role) VALUES
 (6,1), (6,3), (7,1), (7,4), (8,1), (8,2), (5,6), (4,1);

-- ---------- Distances pour les nouvelles villes ----------
INSERT INTO DISTANCE_VILLE (ville_a, ville_b, distance_km) VALUES
 ('Casablanca','Fès',290),  ('Casablanca','Agadir',510),
 ('Rabat','Fès',200),       ('Rabat','Agadir',600),
 ('Tanger','Fès',300),      ('Tanger','Agadir',850),
 ('Marrakech','Fès',530),   ('Marrakech','Agadir',270),
 ('Fès','Agadir',780);

-- ---------- Matériaux (3 nouveaux -> 6 au total) ----------
INSERT INTO MATERIAU (nom, categorie, proprietes) VALUES
 ('Verre',  'verre',  'Recyclable, fusion à haute température'),  -- 4
 ('Cuivre', 'métal',  'Excellent conducteur, très recyclable'),   -- 5
 ('Carton', 'papier', 'Fibres cellulosiques, recyclage papetier');-- 6

-- ---------- Historique daté dans le passé ----------
-- SET TIMESTAMP fait croire à la session qu'on est à une autre date : les triggers
-- (événements "production" et "vente") et les valeurs par défaut (CURRENT_DATE)
-- produisent alors un historique chronologiquement cohérent.
-- (Nécessite un utilisateur ayant le droit de modifier cette variable, ex. root.)

-- Heure réelle de référence, mémorisée avant tout décalage
SET @t0 = UNIX_TIMESTAMP();

-- J-40 : création des ressources 3 à 8 (le trigger crée l'événement "production")
SET TIMESTAMP = @t0 - 40*86400;
INSERT INTO RESSOURCE (quantite, unite, qualite, statut, localisation_actuelle,
                       date_disponibilite, id_producteur, id_proprietaire) VALUES
 (1500, 'kg', 92, 'disponible',        'Fès',        CURRENT_DATE, 6, 6),  -- 3 acier
 ( 600, 'kg', 88, 'disponible',        'Agadir',     CURRENT_DATE, 7, 7),  -- 4 verre
 ( 300, 'kg', 97, 'disponible',        'Casablanca', CURRENT_DATE, 1, 1),  -- 5 cuivre
 (1200, 'kg', 75, 'disponible',        'Fès',        CURRENT_DATE, 8, 8),  -- 6 carton
 ( 900, 'kg', 90, 'en_transformation', 'Marrakech',  CURRENT_DATE, 4, 4),  -- 7 acier + cuivre
 (2500, 'kg', 80, 'disponible',        'Rabat',      CURRENT_DATE, 2, 2);  -- 8 PET (reste inactive)

INSERT INTO COMPOSER (id_ressource, id_materiau, pourcentage) VALUES
 (3, 3, 100),
 (4, 4, 100),
 (5, 5, 100),
 (6, 6, 100),
 (7, 3,  70), (7, 5, 30),
 (8, 2, 100);

-- Chaque INSERT dans TRANSACTION déclenche : contrôle du vendeur, changement de
-- propriétaire, événement "vente" et clôture des offres ouvertes du vendeur.
SET TIMESTAMP = @t0 - 35*86400;
INSERT INTO EVENEMENT (type, description, id_ressource, id_entreprise) VALUES
 ('stockage', 'Stockage en entrepôt sec', 3, 6);

SET TIMESTAMP = @t0 - 30*86400;
INSERT INTO EVENEMENT (type, description, id_ressource, id_entreprise) VALUES
 ('controle', 'Contrôle de pureté avant vente', 5, 1);

SET TIMESTAMP = @t0 - 20*86400;
INSERT INTO TRANSACTION (quantite, prix, id_ressource, id_vendeur, id_acheteur)
VALUES (300, 25000, 5, 1, 3);          -- cuivre : AluMaroc -> Atlas Transform

SET TIMESTAMP = @t0 - 15*86400;
INSERT INTO TRANSACTION (quantite, prix, id_ressource, id_vendeur, id_acheteur)
VALUES (1500, 18000, 3, 6, 4);         -- acier : FerroSteel -> BatiPro

SET TIMESTAMP = @t0 - 12*86400;
INSERT INTO EVENEMENT (type, description, id_ressource, id_entreprise) VALUES
 ('decoupe', 'Découpe en plaques de 2 m', 3, 4);

SET TIMESTAMP = @t0 - 9*86400;
INSERT INTO EVENEMENT (type, description, id_ressource, id_entreprise) VALUES
 ('transformation', 'Fusion et mise en lingots', 7, 4);

SET TIMESTAMP = @t0 - 7*86400;
INSERT INTO TRANSACTION (quantite, prix, id_ressource, id_vendeur, id_acheteur)
VALUES (600, 6000, 4, 7, 2);           -- verre : EcoVerre -> PlastiRecycle

SET TIMESTAMP = @t0 - 6*86400;
INSERT INTO EVENEMENT (type, description, id_ressource, id_entreprise) VALUES
 ('controle', 'Analyse de pureté du cuivre', 5, 3);

SET TIMESTAMP = @t0 - 5*86400;
INSERT INTO TRANSACTION (quantite, prix, id_ressource, id_vendeur, id_acheteur)
VALUES (1200, 4000, 6, 8, 1);          -- carton : TextilRecup -> AluMaroc

SET TIMESTAMP = @t0 - 4*86400;
INSERT INTO EVENEMENT (type, description, id_ressource, id_entreprise) VALUES
 ('transport', 'Livraison Agadir vers Rabat', 4, 5);

SET TIMESTAMP = @t0 - 2*86400;
INSERT INTO TRANSACTION (quantite, prix, id_ressource, id_vendeur, id_acheteur)
VALUES (300, 27000, 5, 3, 2);          -- cuivre : Atlas Transform -> PlastiRecycle (2e changement)

SET TIMESTAMP = @t0 - 1*86400;
INSERT INTO EVENEMENT (type, description, id_ressource, id_entreprise) VALUES
 ('stockage', 'Mise en stock du carton compacté', 6, 1);

-- Retour à l'heure réelle
SET TIMESTAMP = DEFAULT;

-- Ressource 1 (créée et vendue à Atlas Transform par le script 01, aujourd'hui) :
-- contrôle, transport, puis revente à BatiPro (2e changement de propriétaire)
INSERT INTO EVENEMENT (type, description, id_ressource, id_entreprise) VALUES
 ('controle',  'Contrôle qualité à réception',     1, 3),
 ('transport', 'Transport Casablanca vers Tanger', 1, 5);
INSERT INTO TRANSACTION (quantite, prix, id_ressource, id_vendeur, id_acheteur)
VALUES (800, 14000, 1, 3, 4);          -- alu : Atlas Transform -> BatiPro

-- ---------- Offres (6 nouvelles -> 8 au total) : le propriétaire actuel publie ----------
-- Propriétaires actuels : res3=4, res5=2, res6=1, res4=2, res7=4, res8=2
INSERT INTO OFFRE (date_publication, quantite_proposee, prix, id_entreprise, id_ressource) VALUES
 (CURRENT_DATE - INTERVAL 3 DAY, 1500, 18500, 4, 3),
 (CURRENT_DATE - INTERVAL 2 DAY,  300, 26000, 2, 5),
 (CURRENT_DATE - INTERVAL 2 DAY, 1200,  4500, 1, 6),
 (CURRENT_DATE - INTERVAL 1 DAY,  600,  6500, 2, 4),
 (CURRENT_DATE,                   900, 11000, 4, 7),
 (CURRENT_DATE,                  2500,  9500, 2, 8);

-- ---------- Demandes (5 nouvelles -> 7 au total) ----------
INSERT INTO DEMANDE (quantite_requise, qualite_min, distance_max, budget, date_limite, id_entreprise, id_materiau) VALUES
 (1000, 85, 700, 20000, CURRENT_DATE + INTERVAL 45 DAY, 6, 3),  -- FerroSteel veut de l'acier
 ( 500, 80, 600,  7000, CURRENT_DATE + INTERVAL 45 DAY, 1, 4),  -- AluMaroc veut du verre
 ( 200, 90, 500, 30000, CURRENT_DATE + INTERVAL 45 DAY, 3, 5),  -- Atlas Transform veut du cuivre
 (1000, 70, 500,  5000, CURRENT_DATE + INTERVAL 45 DAY, 5, 6),  -- TransLog veut du carton
 ( 200, 90, 500, 10000, CURRENT_DATE + INTERVAL 45 DAY, 8, 1);  -- TextilRecup veut de l'aluminium

-- La demande n°1 (aluminium) a été satisfaite par la vente de la ressource 1
UPDATE DEMANDE SET statut = 'satisfaite' WHERE id_demande = 1;

-- ---------- Scénarios de seconde vie (sur plusieurs ressources) ----------
INSERT INTO SCENARIO (type, cout_estime, valeur_estimee, distance_km, impact_environnemental, id_ressource) VALUES
 ('reutilisation',  800, 18000, 290,  60, 3),
 ('recyclage',     2000, 14000, 100, 180, 3),
 ('recyclage',      900,  7000, 270, 150, 4),
 ('reutilisation',  300,  6500, 510,  30, 4),
 ('transformation',1500, 28000,  90,  90, 5),
 ('recyclage',      600,  4500, 290, 110, 6),
 ('autre',          400,  3000, 120,  70, 6),
 ('transformation',2500, 13000, 240, 130, 7),
 ('recyclage',     1800,  9500,  90, 160, 8);

-- ---------- Vérification des volumes ----------
SELECT 'ENTREPRISE' AS table_name, COUNT(*) AS nb FROM ENTREPRISE UNION ALL
SELECT 'ROLE',        COUNT(*) FROM ROLE         UNION ALL
SELECT 'MATERIAU',    COUNT(*) FROM MATERIAU     UNION ALL
SELECT 'RESSOURCE',   COUNT(*) FROM RESSOURCE    UNION ALL
SELECT 'COMPOSER',    COUNT(*) FROM COMPOSER     UNION ALL
SELECT 'EVENEMENT',   COUNT(*) FROM EVENEMENT    UNION ALL
SELECT 'OFFRE',       COUNT(*) FROM OFFRE        UNION ALL
SELECT 'DEMANDE',     COUNT(*) FROM DEMANDE      UNION ALL
SELECT 'TRANSACTION', COUNT(*) FROM TRANSACTION  UNION ALL
SELECT 'SCENARIO',    COUNT(*) FROM SCENARIO;


-- =====================================================================
-- PARTIE 3 : REQUÊTES SQL
-- =====================================================================
USE resource_db;


-- ---------------------------------------------------------------------
-- A. SÉLECTION ET FILTRAGE
-- ---------------------------------------------------------------------

-- A1. Ressources disponibles de haute qualité (>= 90), de la meilleure à la moins bonne
SELECT id_ressource, quantite, unite, qualite, localisation_actuelle
FROM RESSOURCE
WHERE statut = 'disponible' AND qualite >= 90
ORDER BY qualite DESC;

-- A2. Offres ouvertes dont le prix est inférieur à 10 000
SELECT id_offre, id_ressource, quantite_proposee, prix
FROM OFFRE
WHERE statut = 'ouverte' AND prix < 10000
ORDER BY prix;

-- A3. Entreprises basées à Fès ou Casablanca dont le nom commence par une lettre de A à F
SELECT id_entreprise, nom, secteur, ville
FROM ENTREPRISE
WHERE ville IN ('Fès', 'Casablanca') AND nom BETWEEN 'A' AND 'G'
ORDER BY nom;

-- ---------------------------------------------------------------------
-- B. JOINTURES
-- ---------------------------------------------------------------------

-- B1. Fiche de chaque ressource : producteur d'origine, propriétaire actuel et matériaux
SELECT r.id_ressource,
       GROUP_CONCAT(CONCAT(m.nom, ' (', c.pourcentage, '%)') SEPARATOR ' + ') AS composition,
       p.nom  AS producteur,
       pr.nom AS proprietaire_actuel,
       r.localisation_actuelle
FROM RESSOURCE r
JOIN ENTREPRISE p   ON p.id_entreprise  = r.id_producteur
JOIN ENTREPRISE pr  ON pr.id_entreprise = r.id_proprietaire
JOIN COMPOSER   c   ON c.id_ressource   = r.id_ressource
JOIN MATERIAU   m   ON m.id_materiau    = c.id_materiau
GROUP BY r.id_ressource, p.nom, pr.nom, r.localisation_actuelle
ORDER BY r.id_ressource;

-- B2. Historique des transactions avec vendeur, acheteur et matériau principal
SELECT t.id_transaction, t.date_transaction,
       v.nom AS vendeur, a.nom AS acheteur,
       t.id_ressource, t.quantite, t.prix
FROM TRANSACTION t
JOIN ENTREPRISE v ON v.id_entreprise = t.id_vendeur
JOIN ENTREPRISE a ON a.id_entreprise = t.id_acheteur
ORDER BY t.date_transaction;

-- B3. LEFT JOIN : toutes les entreprises, avec leurs rôles (même sans rôle)
SELECT e.nom, e.ville, COALESCE(GROUP_CONCAT(ro.libelle ORDER BY ro.libelle), 'aucun rôle') AS roles
FROM ENTREPRISE e
LEFT JOIN JOUER j  ON j.id_entreprise = e.id_entreprise
LEFT JOIN ROLE  ro ON ro.id_role      = j.id_role
GROUP BY e.id_entreprise, e.nom, e.ville
ORDER BY e.nom;

-- ---------------------------------------------------------------------
-- C. AGRÉGATION AVEC GROUP BY
-- ---------------------------------------------------------------------

-- C1. Quantité totale de chaque matériau en stock (pondérée par la composition)
SELECT m.nom AS materiau,
       COUNT(DISTINCT r.id_ressource)                 AS nb_ressources,
       ROUND(SUM(r.quantite * c.pourcentage / 100), 2) AS quantite_kg_equivalente
FROM MATERIAU m
JOIN COMPOSER  c ON c.id_materiau  = m.id_materiau
JOIN RESSOURCE r ON r.id_ressource = c.id_ressource
GROUP BY m.id_materiau, m.nom
ORDER BY quantite_kg_equivalente DESC;

-- C2. Chiffre d'affaires des ventes par entreprise vendeuse (au moins une vente)
SELECT v.nom AS vendeur, COUNT(*) AS nb_ventes, SUM(t.prix) AS chiffre_affaires,
       ROUND(AVG(t.prix), 2) AS prix_moyen
FROM TRANSACTION t
JOIN ENTREPRISE v ON v.id_entreprise = t.id_vendeur
GROUP BY v.id_entreprise, v.nom
HAVING COUNT(*) >= 1
ORDER BY chiffre_affaires DESC;

-- C3. Nombre d'événements par type : seuls les types présents au moins 2 fois sont conservés
SELECT type, COUNT(*) AS nb_evenements
FROM EVENEMENT
GROUP BY type
HAVING COUNT(*) >= 2
ORDER BY nb_evenements DESC;

-- ---------------------------------------------------------------------
-- D. SOUS-REQUÊTES
-- ---------------------------------------------------------------------

-- D1. Sous-requête scalaire : ressources dont la qualité dépasse la moyenne générale
SELECT id_ressource, quantite, qualite
FROM RESSOURCE
WHERE qualite > (SELECT AVG(qualite) FROM RESSOURCE)
ORDER BY qualite DESC;

-- D2. NOT EXISTS : entreprises qui n'ont jamais réalisé de vente
SELECT e.id_entreprise, e.nom, e.ville
FROM ENTREPRISE e
WHERE NOT EXISTS (SELECT 1 FROM TRANSACTION t WHERE t.id_vendeur = e.id_entreprise);

-- D3. IN : ressources ayant au moins un scénario de type "recyclage"
SELECT r.id_ressource, r.quantite, r.localisation_actuelle
FROM RESSOURCE r
WHERE r.id_ressource IN (SELECT s.id_ressource FROM SCENARIO s WHERE s.type = 'recyclage');

-- ---------------------------------------------------------------------
-- E. REQUÊTES PLUS ÉLABORÉES
-- ---------------------------------------------------------------------

-- E1. Bilan financier par entreprise (CTE + jointures + RANK)
--     ventes, achats, solde net, et classement par solde
WITH ventes AS (
    SELECT id_vendeur AS id_entreprise, SUM(prix) AS total_ventes
    FROM TRANSACTION GROUP BY id_vendeur
), achats AS (
    SELECT id_acheteur AS id_entreprise, SUM(prix) AS total_achats
    FROM TRANSACTION GROUP BY id_acheteur
)
SELECT e.nom,
       COALESCE(v.total_ventes, 0)                           AS ventes,
       COALESCE(a.total_achats, 0)                           AS achats,
       COALESCE(v.total_ventes, 0) - COALESCE(a.total_achats, 0) AS solde_net,
       RANK() OVER (ORDER BY COALESCE(v.total_ventes, 0) - COALESCE(a.total_achats, 0) DESC) AS rang
FROM ENTREPRISE e
LEFT JOIN ventes v ON v.id_entreprise = e.id_entreprise
LEFT JOIN achats a ON a.id_entreprise = e.id_entreprise
ORDER BY rang;

-- E2. Meilleur scénario de seconde vie par ressource (gain net maximal) avec la vue fournie
SELECT id_ressource, type AS meilleur_scenario, gain_net, impact_environnemental
FROM v_comparaison_scenarios
WHERE rang = 1
ORDER BY gain_net DESC;

-- E3. Offres ouvertes avec leur meilleure demande compatible (vue v_matching)
SELECT id_offre, entreprise_offre, materiau, entreprise_demande,
       distance_km, score_compatibilite
FROM v_matching
ORDER BY score_compatibilite DESC;

-- E4. Parcours de chaque ressource : nombre de propriétaires successifs et d'événements
SELECT r.id_ressource,
       1 + COUNT(DISTINCT t.id_transaction) AS nb_proprietaires_successifs,
       (SELECT COUNT(*) FROM EVENEMENT ev WHERE ev.id_ressource = r.id_ressource) AS nb_evenements
FROM RESSOURCE r
LEFT JOIN TRANSACTION t ON t.id_ressource = r.id_ressource
GROUP BY r.id_ressource
ORDER BY nb_proprietaires_successifs DESC, nb_evenements DESC;

-- E5. Vues de contrôle fournies par le projet
SELECT * FROM v_ressources_multi_proprietaires;
SELECT * FROM v_composition_incomplete;


-- =====================================================================
-- PARTIE 4 : INDEXATION ET OPTIMISATION (EXPLAIN avant/après)
-- =====================================================================
USE resource_db;


-- ---------------------------------------------------------------------
-- 0. VOLUME DE TEST : sur 8 lignes, MySQL préfère toujours un parcours complet.
--    On génère donc des données pour que l'index ait un intérêt mesurable.
-- ---------------------------------------------------------------------
SET SESSION cte_max_recursion_depth = 60000;

-- 20 000 entreprises réparties sur 50 villes fictives
INSERT INTO ENTREPRISE (nom, secteur, ville)
WITH RECURSIVE seq (n) AS (
    SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 20000
)
SELECT CONCAT('Entreprise_test_', n),
       ELT(1 + n MOD 4, 'Métallurgie', 'Recyclage', 'BTP', 'Transport'),
       CONCAT('Ville_', n MOD 50)
FROM seq;

-- 50 000 événements répartis sur 365 jours, 8 types, sur les 8 ressources réelles
INSERT INTO EVENEMENT (type, date_heure, description, id_ressource, id_entreprise)
WITH RECURSIVE seq (n) AS (
    SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < 50000
)
SELECT ELT(1 + n MOD 8, 'production','decoupe','stockage','transport',
                        'controle','transformation','vente','changement_localisation'),
       NOW() - INTERVAL (n MOD 365) DAY - INTERVAL (n MOD 86400) SECOND,
       'Événement généré pour le test de performance',
       1 + n MOD 8,
       1 + n MOD 8
FROM seq;

ANALYZE TABLE ENTREPRISE, EVENEMENT;

-- Index déjà présents avant ce script (pour mémoire)
SHOW INDEX FROM EVENEMENT;
SHOW INDEX FROM ENTREPRISE;

-- =====================================================================
-- INDEX N°1 : ENTREPRISE(ville)
-- Justification : la ville sert à retrouver les entreprises d'une zone et à calculer
-- les distances du matching (jointure avec fn_distance, recherche de partenaires proches).
-- La colonne n'est pas une clé étrangère, donc aucun index n'existe automatiquement.
-- Sélectivité : 50 villes -> un filtre élimine ~98 % des lignes.
-- =====================================================================
-- Requête testée
EXPLAIN
SELECT id_entreprise, nom, secteur
FROM ENTREPRISE
WHERE ville = 'Ville_7';

-- Mesure du plan réel (nombre de lignes lues, temps)
EXPLAIN ANALYZE
SELECT id_entreprise, nom, secteur
FROM ENTREPRISE
WHERE ville = 'Ville_7';

-- Création de l'index
CREATE INDEX idx_entreprise_ville ON ENTREPRISE (ville);

ANALYZE TABLE ENTREPRISE;

-- Même requête après indexation
EXPLAIN
SELECT id_entreprise, nom, secteur
FROM ENTREPRISE
WHERE ville = 'Ville_7';

EXPLAIN ANALYZE
SELECT id_entreprise, nom, secteur
FROM ENTREPRISE
WHERE ville = 'Ville_7';

-- =====================================================================
-- INDEX N°2 : EVENEMENT(type, date_heure)  (index composite)
-- Justification : le suivi demande souvent « les événements d'un type donné sur une
-- période » (transports des 7 derniers jours, contrôles du mois...), et les rapports
-- regroupent par type. L'index existant idx_evenement_ressource (id_ressource, date_heure)
-- commence par id_ressource : il ne sert pas à filtrer d'abord par type.
-- Ordre des colonnes : l'égalité (type) d'abord, puis la plage (date_heure).
-- =====================================================================
EXPLAIN
SELECT id_evenement, id_ressource, date_heure
FROM EVENEMENT
WHERE type = 'transport'
  AND date_heure >= NOW() - INTERVAL 7 DAY;

EXPLAIN ANALYZE
SELECT id_evenement, id_ressource, date_heure
FROM EVENEMENT
WHERE type = 'transport'
  AND date_heure >= NOW() - INTERVAL 7 DAY;

CREATE INDEX idx_evenement_type_date ON EVENEMENT (type, date_heure);

ANALYZE TABLE EVENEMENT;

EXPLAIN
SELECT id_evenement, id_ressource, date_heure
FROM EVENEMENT
WHERE type = 'transport'
  AND date_heure >= NOW() - INTERVAL 7 DAY;

EXPLAIN ANALYZE
SELECT id_evenement, id_ressource, date_heure
FROM EVENEMENT
WHERE type = 'transport'
  AND date_heure >= NOW() - INTERVAL 7 DAY;

-- =====================================================================
-- Lecture des résultats : colonnes à comparer dans EXPLAIN
--   type          ALL (parcours complet)  ->  ref / range (accès par index)
--   key           NULL                    ->  nom de l'index utilisé
--   rows          nombre de lignes estimées à lire (doit chuter fortement)
--   filtered/Extra  "Using where"  ->  "Using index condition"
-- =====================================================================