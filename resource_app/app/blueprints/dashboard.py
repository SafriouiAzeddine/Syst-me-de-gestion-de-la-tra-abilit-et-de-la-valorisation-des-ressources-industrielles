"""Dashboard with KPIs, charts and recent activity."""

from __future__ import annotations

from decimal import Decimal

from flask import Blueprint, render_template
from sqlalchemy import case, exists, func, select, text

from app.db_utils import run_view
from app.extensions import db
from app.models import Correspondre, Demande, Offre, Ressource, Transaction

bp = Blueprint("dashboard", __name__)


def _num(value) -> float:
    if value is None:
        return 0.0
    if isinstance(value, Decimal):
        return float(value)
    return float(value)


@bp.route("/")
def index():
    nb_ressources = db.session.execute(select(func.count()).select_from(Ressource)).scalar_one()
    total_quantite = db.session.execute(select(func.coalesce(func.sum(Ressource.quantite), 0))).scalar_one()
    par_statut = dict(
        db.session.execute(
            select(Ressource.statut, func.count()).group_by(Ressource.statut)
        ).all()
    )
    offres_ouvertes = db.session.execute(
        select(func.count()).select_from(Offre).where(Offre.statut == "ouverte")
    ).scalar_one()
    demandes_ouvertes = db.session.execute(
        select(func.count()).select_from(Demande).where(Demande.statut == "ouverte")
    ).scalar_one()
    nb_matches = db.session.execute(select(func.count()).select_from(Correspondre)).scalar_one()
    nb_transactions = db.session.execute(select(func.count()).select_from(Transaction)).scalar_one()

    has_tx = exists(select(Transaction.id_transaction).where(Transaction.id_ressource == Ressource.id_ressource))
    utilised = case(
        (Ressource.statut.in_(("transformee", "recyclee")) | has_tx, 1),
        else_=0,
    )
    if nb_ressources:
        taux_utilisation = db.session.execute(
            select(100.0 * func.sum(utilised) / func.count()).select_from(Ressource)
        ).scalar_one()
    else:
        taux_utilisation = 0
    tracabilite = db.session.execute(
        text(
            """
            SELECT COALESCE(AVG(nb), 0) FROM (
                SELECT COUNT(*) AS nb FROM EVENEMENT GROUP BY id_ressource
            ) t
            """
        )
    ).scalar_one()

    derniers_evenements = db.session.execute(
        text(
            """
            SELECT ev.date_heure, ev.type, ev.description, ev.id_ressource,
                   en.nom AS acteur
            FROM EVENEMENT ev
            JOIN ENTREPRISE en ON en.id_entreprise = ev.id_entreprise
            ORDER BY ev.date_heure DESC
            LIMIT 10
            """
        )
    ).mappings().all()

    top_matches = run_view(
        """
        SELECT id_offre, id_demande, materiau, entreprise_offre, entreprise_demande,
               score_compatibilite, distance_km, id_ressource
        FROM v_matching
        ORDER BY score_compatibilite DESC
        LIMIT 5
        """
    )

    par_materiau = db.session.execute(
        text(
            """
            SELECT m.nom AS materiau, COUNT(DISTINCT c.id_ressource) AS nb
            FROM COMPOSER c
            JOIN MATERIAU m ON m.id_materiau = c.id_materiau
            GROUP BY m.nom
            ORDER BY nb DESC
            """
        )
    ).mappings().all()

    tx_mois = db.session.execute(
        text(
            """
            SELECT DATE_FORMAT(date_transaction, '%Y-%m') AS mois, COUNT(*) AS nb
            FROM TRANSACTION
            GROUP BY DATE_FORMAT(date_transaction, '%Y-%m')
            ORDER BY mois
            """
        )
    ).mappings().all()

    chart = {
        "statuts_labels": list(par_statut.keys()),
        "statuts_values": [int(v) for v in par_statut.values()],
        "materiaux_labels": [row["materiau"] for row in par_materiau],
        "materiaux_values": [int(row["nb"]) for row in par_materiau],
        "tx_labels": [row["mois"] for row in tx_mois],
        "tx_values": [int(row["nb"]) for row in tx_mois],
    }

    return render_template(
        "dashboard/index.html",
        nb_ressources=nb_ressources,
        total_quantite=_num(total_quantite),
        par_statut=par_statut,
        offres_ouvertes=offres_ouvertes,
        demandes_ouvertes=demandes_ouvertes,
        nb_matches=nb_matches,
        nb_transactions=nb_transactions,
        taux_utilisation=_num(taux_utilisation),
        tracabilite=_num(tracabilite),
        derniers_evenements=derniers_evenements,
        top_matches=top_matches,
        chart=chart,
    )
