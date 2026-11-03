"""Flask-WTF forms. Labels are in French; field names stay in English/schema."""

from __future__ import annotations

from flask_wtf import FlaskForm
from wtforms import (
    DateField,
    DateTimeLocalField,
    DecimalField,
    SelectField,
    SelectMultipleField,
    StringField,
    SubmitField,
    TextAreaField,
)
from wtforms.validators import DataRequired, Length, NumberRange, Optional, ValidationError

from app.models import (
    STATUT_DEMANDE,
    STATUT_OFFRE,
    STATUT_RESSOURCE,
    TYPE_EVENEMENT_MANUEL,
    TYPE_SCENARIO,
)


def _choices(values: tuple[str, ...], labels: dict[str, str] | None = None):
    labels = labels or {}
    return [(v, labels.get(v, v)) for v in values]


STATUT_RESSOURCE_LABELS = {
    "disponible": "Disponible",
    "reservee": "Réservée",
    "en_transformation": "En transformation",
    "transformee": "Transformée",
    "recyclee": "Recyclée",
}
STATUT_OFFRE_LABELS = {"ouverte": "Ouverte", "cloturee": "Clôturée", "annulee": "Annulée"}
STATUT_DEMANDE_LABELS = {
    "ouverte": "Ouverte",
    "satisfaite": "Satisfaite",
    "annulee": "Annulée",
}
TYPE_EVENEMENT_LABELS = {
    "decoupe": "Découpe",
    "stockage": "Stockage",
    "transport": "Transport",
    "controle": "Contrôle",
    "transformation": "Transformation",
}
TYPE_SCENARIO_LABELS = {
    "reutilisation": "Réutilisation",
    "transformation": "Transformation",
    "recyclage": "Recyclage",
    "autre": "Autre",
}


class EntrepriseForm(FlaskForm):
    nom = StringField("Nom", validators=[DataRequired(), Length(max=100)])
    secteur = StringField("Secteur", validators=[Optional(), Length(max=100)])
    ville = StringField("Ville", validators=[DataRequired(), Length(max=80)])
    roles = SelectMultipleField(
        "Rôles",
        coerce=int,
        validators=[DataRequired(message="Une entreprise doit avoir au moins un rôle.")],
    )
    date_debut = DateField(
        "Date de début des nouveaux rôles",
        validators=[DataRequired()],
    )
    submit = SubmitField("Enregistrer")


class RoleForm(FlaskForm):
    libelle = StringField("Libellé", validators=[DataRequired(), Length(max=50)])
    submit = SubmitField("Enregistrer")


class MateriauForm(FlaskForm):
    nom = StringField("Nom", validators=[DataRequired(), Length(max=100)])
    categorie = StringField("Catégorie", validators=[Optional(), Length(max=50)])
    proprietes = TextAreaField("Propriétés", validators=[Optional()])
    submit = SubmitField("Enregistrer")


class DistanceForm(FlaskForm):
    ville_a = StringField("Ville A", validators=[DataRequired(), Length(max=80)])
    ville_b = StringField("Ville B", validators=[DataRequired(), Length(max=80)])
    distance_km = DecimalField(
        "Distance (km)",
        validators=[DataRequired(), NumberRange(min=0.01)],
        places=2,
    )
    submit = SubmitField("Enregistrer")

    def validate_ville_b(self, field):
        if field.data and self.ville_a.data and field.data.strip() == self.ville_a.data.strip():
            raise ValidationError("Les deux villes doivent être distinctes.")


class RessourceForm(FlaskForm):
    quantite = DecimalField(
        "Quantité",
        validators=[DataRequired(), NumberRange(min=0.01)],
        places=2,
    )
    unite = StringField("Unité", validators=[DataRequired(), Length(max=20)], default="kg")
    qualite = DecimalField(
        "Qualité (%)",
        validators=[DataRequired(), NumberRange(min=0, max=100)],
        places=2,
    )
    statut = SelectField(
        "Statut",
        choices=_choices(STATUT_RESSOURCE, STATUT_RESSOURCE_LABELS),
        validators=[DataRequired()],
    )
    localisation_actuelle = SelectField("Localisation actuelle", validators=[DataRequired()])
    date_disponibilite = DateField("Date de disponibilité", validators=[Optional()])
    id_producteur = SelectField("Producteur", coerce=int, validators=[Optional()])
    submit = SubmitField("Enregistrer")


class EvenementForm(FlaskForm):
    type = SelectField(
        "Type",
        choices=_choices(TYPE_EVENEMENT_MANUEL, TYPE_EVENEMENT_LABELS),
        validators=[DataRequired()],
    )
    date_heure = DateTimeLocalField("Date et heure", validators=[Optional()], format="%Y-%m-%dT%H:%M")
    description = TextAreaField("Description", validators=[Optional()])
    submit = SubmitField("Ajouter l'événement")


class OffreForm(FlaskForm):
    id_ressource = SelectField("Ressource", coerce=int, validators=[DataRequired()])
    quantite_proposee = DecimalField(
        "Quantité proposée",
        validators=[DataRequired(), NumberRange(min=0.01)],
        places=2,
    )
    prix = DecimalField(
        "Prix",
        validators=[DataRequired(), NumberRange(min=0)],
        places=2,
    )
    submit = SubmitField("Publier l'offre")


class OffreStatutForm(FlaskForm):
    statut = SelectField(
        "Statut",
        choices=_choices(STATUT_OFFRE, STATUT_OFFRE_LABELS),
        validators=[DataRequired()],
    )
    submit = SubmitField("Mettre à jour")


class DemandeForm(FlaskForm):
    id_materiau = SelectField("Matériau", coerce=int, validators=[DataRequired()])
    quantite_requise = DecimalField(
        "Quantité requise",
        validators=[DataRequired(), NumberRange(min=0.01)],
        places=2,
    )
    qualite_min = DecimalField(
        "Qualité minimale (%)",
        validators=[DataRequired(), NumberRange(min=0, max=100)],
        places=2,
        default=0,
    )
    distance_max = DecimalField(
        "Distance maximale (km)",
        validators=[DataRequired(), NumberRange(min=0.01, message="La distance maximale est obligatoire et doit être positive.")],
        places=2,
    )
    budget = DecimalField("Budget", validators=[Optional(), NumberRange(min=0)], places=2)
    date_limite = DateField("Date limite", validators=[Optional()])
    submit = SubmitField("Enregistrer la demande")


class DemandeStatutForm(FlaskForm):
    statut = SelectField(
        "Statut",
        choices=_choices(STATUT_DEMANDE, STATUT_DEMANDE_LABELS),
        validators=[DataRequired()],
    )
    submit = SubmitField("Mettre à jour")


class TransactionForm(FlaskForm):
    id_ressource = SelectField("Ressource", coerce=int, validators=[DataRequired()])
    id_acheteur = SelectField("Acheteur", coerce=int, validators=[DataRequired()])
    quantite = DecimalField(
        "Quantité",
        validators=[DataRequired(), NumberRange(min=0.01)],
        places=2,
    )
    prix = DecimalField(
        "Prix",
        validators=[DataRequired(), NumberRange(min=0)],
        places=2,
    )
    date_transaction = DateField("Date", validators=[DataRequired()])
    submit = SubmitField("Enregistrer la transaction")


class ScenarioForm(FlaskForm):
    id_ressource = SelectField("Ressource", coerce=int, validators=[DataRequired()])
    type = SelectField(
        "Type",
        choices=_choices(TYPE_SCENARIO, TYPE_SCENARIO_LABELS),
        validators=[DataRequired()],
    )
    cout_estime = DecimalField(
        "Coût estimé",
        validators=[DataRequired(), NumberRange(min=0)],
        places=2,
    )
    valeur_estimee = DecimalField(
        "Valeur estimée",
        validators=[DataRequired()],
        places=2,
    )
    distance_km = DecimalField("Distance (km)", validators=[Optional(), NumberRange(min=0)], places=2)
    impact_environnemental = DecimalField(
        "Impact environnemental",
        validators=[Optional()],
        places=2,
    )
    submit = SubmitField("Enregistrer le scénario")


class ConfirmForm(FlaskForm):
    submit = SubmitField("Confirmer")
