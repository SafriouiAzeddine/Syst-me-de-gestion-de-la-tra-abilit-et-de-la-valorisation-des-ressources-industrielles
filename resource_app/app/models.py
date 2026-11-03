"""ORM models mapped onto the existing resource_db tables. Never call db.create_all()."""

from __future__ import annotations

from app.extensions import db

STATUT_RESSOURCE = (
    "disponible",
    "reservee",
    "en_transformation",
    "transformee",
    "recyclee",
)
TYPE_EVENEMENT = (
    "production",
    "decoupe",
    "stockage",
    "transport",
    "controle",
    "transformation",
    "vente",
    "changement_localisation",
)
TYPE_EVENEMENT_MANUEL = (
    "decoupe",
    "stockage",
    "transport",
    "controle",
    "transformation",
)
STATUT_OFFRE = ("ouverte", "cloturee", "annulee")
STATUT_DEMANDE = ("ouverte", "satisfaite", "annulee")
TYPE_SCENARIO = ("reutilisation", "transformation", "recyclage", "autre")


class Role(db.Model):
    __tablename__ = "ROLE"

    id_role = db.Column(db.Integer, primary_key=True)
    libelle = db.Column(db.String(50), unique=True, nullable=False)

    jouers = db.relationship("Jouer", back_populates="role")

    def __repr__(self) -> str:
        return f"<Role {self.libelle}>"


class Entreprise(db.Model):
    __tablename__ = "ENTREPRISE"

    id_entreprise = db.Column(db.Integer, primary_key=True)
    nom = db.Column(db.String(100), nullable=False)
    secteur = db.Column(db.String(100))
    ville = db.Column(db.String(80), nullable=False)

    jouers = db.relationship("Jouer", back_populates="entreprise", cascade="all, delete-orphan")
    ressources_produites = db.relationship(
        "Ressource",
        foreign_keys="Ressource.id_producteur",
        back_populates="producteur",
    )
    ressources_possedees = db.relationship(
        "Ressource",
        foreign_keys="Ressource.id_proprietaire",
        back_populates="proprietaire",
    )
    evenements = db.relationship("Evenement", back_populates="entreprise")
    offres = db.relationship("Offre", back_populates="entreprise")
    demandes = db.relationship("Demande", back_populates="entreprise")
    ventes = db.relationship(
        "Transaction",
        foreign_keys="Transaction.id_vendeur",
        back_populates="vendeur",
    )
    achats = db.relationship(
        "Transaction",
        foreign_keys="Transaction.id_acheteur",
        back_populates="acheteur",
    )

    def __repr__(self) -> str:
        return f"<Entreprise {self.nom}>"


class Jouer(db.Model):
    __tablename__ = "JOUER"

    id_entreprise = db.Column(
        db.Integer, db.ForeignKey("ENTREPRISE.id_entreprise"), primary_key=True
    )
    id_role = db.Column(db.Integer, db.ForeignKey("ROLE.id_role"), primary_key=True)
    date_debut = db.Column(db.Date, nullable=False)

    entreprise = db.relationship("Entreprise", back_populates="jouers")
    role = db.relationship("Role", back_populates="jouers")


class Materiau(db.Model):
    __tablename__ = "MATERIAU"

    id_materiau = db.Column(db.Integer, primary_key=True)
    nom = db.Column(db.String(100), unique=True, nullable=False)
    categorie = db.Column(db.String(50))
    proprietes = db.Column(db.Text)

    composers = db.relationship("Composer", back_populates="materiau")
    demandes = db.relationship("Demande", back_populates="materiau")

    def __repr__(self) -> str:
        return f"<Materiau {self.nom}>"


class Ressource(db.Model):
    __tablename__ = "RESSOURCE"

    id_ressource = db.Column(db.Integer, primary_key=True)
    quantite = db.Column(db.Numeric(12, 2), nullable=False)
    unite = db.Column(db.String(20), nullable=False, default="kg")
    qualite = db.Column(db.Numeric(5, 2), nullable=False)
    statut = db.Column(db.String(20), nullable=False, default="disponible")
    localisation_actuelle = db.Column(db.String(80), nullable=False)
    date_disponibilite = db.Column(db.Date)
    id_producteur = db.Column(db.Integer, db.ForeignKey("ENTREPRISE.id_entreprise"), nullable=False)
    id_proprietaire = db.Column(
        db.Integer, db.ForeignKey("ENTREPRISE.id_entreprise"), nullable=False
    )

    producteur = db.relationship(
        "Entreprise", foreign_keys=[id_producteur], back_populates="ressources_produites"
    )
    proprietaire = db.relationship(
        "Entreprise", foreign_keys=[id_proprietaire], back_populates="ressources_possedees"
    )
    composers = db.relationship("Composer", back_populates="ressource")
    evenements = db.relationship(
        "Evenement",
        back_populates="ressource",
        order_by="Evenement.date_heure",
    )
    offres = db.relationship("Offre", back_populates="ressource")
    transactions = db.relationship(
        "Transaction",
        back_populates="ressource",
        order_by="Transaction.date_transaction",
    )
    scenarios = db.relationship("Scenario", back_populates="ressource")

    def __repr__(self) -> str:
        return f"<Ressource {self.id_ressource}>"


class Composer(db.Model):
    __tablename__ = "COMPOSER"

    id_ressource = db.Column(
        db.Integer, db.ForeignKey("RESSOURCE.id_ressource"), primary_key=True
    )
    id_materiau = db.Column(db.Integer, db.ForeignKey("MATERIAU.id_materiau"), primary_key=True)
    pourcentage = db.Column(db.Numeric(5, 2), nullable=False)

    ressource = db.relationship("Ressource", back_populates="composers")
    materiau = db.relationship("Materiau", back_populates="composers")


class Evenement(db.Model):
    __tablename__ = "EVENEMENT"

    id_evenement = db.Column(db.Integer, primary_key=True)
    type = db.Column(db.String(30), nullable=False)
    date_heure = db.Column(db.DateTime, nullable=False)
    description = db.Column(db.Text)
    id_ressource = db.Column(db.Integer, db.ForeignKey("RESSOURCE.id_ressource"), nullable=False)
    id_entreprise = db.Column(
        db.Integer, db.ForeignKey("ENTREPRISE.id_entreprise"), nullable=False
    )

    ressource = db.relationship("Ressource", back_populates="evenements")
    entreprise = db.relationship("Entreprise", back_populates="evenements")


class Offre(db.Model):
    __tablename__ = "OFFRE"

    id_offre = db.Column(db.Integer, primary_key=True)
    date_publication = db.Column(db.Date, nullable=False)
    quantite_proposee = db.Column(db.Numeric(12, 2), nullable=False)
    prix = db.Column(db.Numeric(12, 2), nullable=False)
    statut = db.Column(db.String(20), nullable=False, default="ouverte")
    id_entreprise = db.Column(
        db.Integer, db.ForeignKey("ENTREPRISE.id_entreprise"), nullable=False
    )
    id_ressource = db.Column(db.Integer, db.ForeignKey("RESSOURCE.id_ressource"), nullable=False)

    entreprise = db.relationship("Entreprise", back_populates="offres")
    ressource = db.relationship("Ressource", back_populates="offres")
    correspondances = db.relationship("Correspondre", back_populates="offre")


class Demande(db.Model):
    __tablename__ = "DEMANDE"

    id_demande = db.Column(db.Integer, primary_key=True)
    quantite_requise = db.Column(db.Numeric(12, 2), nullable=False)
    qualite_min = db.Column(db.Numeric(5, 2), nullable=False, default=0)
    distance_max = db.Column(db.Numeric(8, 2), nullable=False)
    budget = db.Column(db.Numeric(12, 2))
    date_limite = db.Column(db.Date)
    statut = db.Column(db.String(20), nullable=False, default="ouverte")
    id_entreprise = db.Column(
        db.Integer, db.ForeignKey("ENTREPRISE.id_entreprise"), nullable=False
    )
    id_materiau = db.Column(db.Integer, db.ForeignKey("MATERIAU.id_materiau"), nullable=False)

    entreprise = db.relationship("Entreprise", back_populates="demandes")
    materiau = db.relationship("Materiau", back_populates="demandes")
    correspondances = db.relationship("Correspondre", back_populates="demande")


class Correspondre(db.Model):
    __tablename__ = "CORRESPONDRE"

    id_offre = db.Column(db.Integer, db.ForeignKey("OFFRE.id_offre"), primary_key=True)
    id_demande = db.Column(db.Integer, db.ForeignKey("DEMANDE.id_demande"), primary_key=True)
    score_compatibilite = db.Column(db.Numeric(5, 2), nullable=False)
    distance_km = db.Column(db.Numeric(8, 2))

    offre = db.relationship("Offre", back_populates="correspondances")
    demande = db.relationship("Demande", back_populates="correspondances")


class Transaction(db.Model):
    __tablename__ = "TRANSACTION"

    id_transaction = db.Column(db.Integer, primary_key=True)
    date_transaction = db.Column(db.Date, nullable=False)
    quantite = db.Column(db.Numeric(12, 2), nullable=False)
    prix = db.Column(db.Numeric(12, 2), nullable=False)
    id_ressource = db.Column(db.Integer, db.ForeignKey("RESSOURCE.id_ressource"), nullable=False)
    id_vendeur = db.Column(db.Integer, db.ForeignKey("ENTREPRISE.id_entreprise"), nullable=False)
    id_acheteur = db.Column(db.Integer, db.ForeignKey("ENTREPRISE.id_entreprise"), nullable=False)

    ressource = db.relationship("Ressource", back_populates="transactions")
    vendeur = db.relationship("Entreprise", foreign_keys=[id_vendeur], back_populates="ventes")
    acheteur = db.relationship("Entreprise", foreign_keys=[id_acheteur], back_populates="achats")


class Scenario(db.Model):
    __tablename__ = "SCENARIO"

    id_scenario = db.Column(db.Integer, primary_key=True)
    type = db.Column(db.String(30), nullable=False)
    cout_estime = db.Column(db.Numeric(12, 2), nullable=False)
    valeur_estimee = db.Column(db.Numeric(12, 2), nullable=False)
    distance_km = db.Column(db.Numeric(8, 2))
    impact_environnemental = db.Column(db.Numeric(10, 2))
    id_ressource = db.Column(db.Integer, db.ForeignKey("RESSOURCE.id_ressource"), nullable=False)

    ressource = db.relationship("Ressource", back_populates="scenarios")


class DistanceVille(db.Model):
    __tablename__ = "DISTANCE_VILLE"

    ville_a = db.Column(db.String(80), primary_key=True)
    ville_b = db.Column(db.String(80), primary_key=True)
    distance_km = db.Column(db.Numeric(8, 2), nullable=False)
