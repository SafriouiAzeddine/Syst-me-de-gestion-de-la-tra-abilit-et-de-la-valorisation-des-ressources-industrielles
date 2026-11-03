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
