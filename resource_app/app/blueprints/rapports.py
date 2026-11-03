"""Reports answering the five business questions plus data quality."""

from __future__ import annotations

from flask import Blueprint, flash, render_template, request
from sqlalchemy import select
from sqlalchemy.orm import joinedload

from app.db_utils import call_procedure, friendly_db_error, run_view
from app.extensions import db
from app.helpers import passport_code
from app.models import Demande, Ressource

bp = Blueprint("rapports", __name__, url_prefix="/rapports")


@bp.route("/", methods=["GET", "POST"])
def index():
    demandes = (
        db.session.execute(
            select(Demande).options(joinedload(Demande.entreprise)).order_by(Demande.id_demande.desc())
        )
        .unique()
        .scalars()
        .all()
    )
    ressources = (
        db.session.execute(select(Ressource).order_by(Ressource.id_ressource)).scalars().all()
    )

    unused = None
    unused_days = request.values.get("jours", default=30, type=int) or 30
    run_unused = request.values.get("run") == "unused" or not request.args
    if run_unused:
        try:
            unused = call_procedure("sp_ressources_inutilisees", (unused_days,))
        except Exception as exc:  # noqa: BLE001
            flash(friendly_db_error(exc), "danger")
            unused = []

    compatible = None
    demand_id = request.values.get("id_demande", type=int)
    max_km = request.values.get("max_km", type=float)
    if request.values.get("run") == "compatible" and demand_id:
        sql = """
            SELECT * FROM v_matching
            WHERE id_demande = :id_demande
        """
        params = {"id_demande": demand_id}
        if max_km is not None:
            sql += " AND distance_km <= :max_km"
            params["max_km"] = max_km
        sql += " ORDER BY score_compatibilite DESC"
        compatible = run_view(sql, params)

    historique = None
    hist_id = request.values.get("hist_ressource", type=int)
    if request.values.get("run") == "historique" and hist_id:
        historique = run_view(
            """
            SELECT * FROM v_historique_ressource
            WHERE id_ressource = :id
            ORDER BY date_heure
            """,
            {"id": hist_id},
        )

    scen_rows = None
    scen_id = request.values.get("scen_ressource", type=int)
    if request.values.get("run") == "scenarios" and scen_id:
        scen_rows = run_view(
            """
            SELECT * FROM v_comparaison_scenarios
            WHERE id_ressource = :id
            ORDER BY rang
            """,
            {"id": scen_id},
        )

    if not request.args.get("run") and ressources:
        first_id = ressources[0].id_ressource
        if historique is None:
            hist_id = first_id
            historique = run_view(
                """
                SELECT * FROM v_historique_ressource
                WHERE id_ressource = :id
                ORDER BY date_heure
                """,
                {"id": hist_id},
            )
        if scen_rows is None:
            scen_id = first_id
            scen_rows = run_view(
                """
                SELECT * FROM v_comparaison_scenarios
                WHERE id_ressource = :id
                ORDER BY rang
                """,
                {"id": scen_id},
            )
        if compatible is None and demandes:
            demand_id = demandes[0].id_demande
            compatible = run_view(
                """
                SELECT * FROM v_matching
                WHERE id_demande = :id_demande
                ORDER BY score_compatibilite DESC
                """,
                {"id_demande": demand_id},
            )

    multi = run_view("SELECT * FROM v_ressources_multi_proprietaires ORDER BY nb_changements DESC")
    incomplete = run_view("SELECT * FROM v_composition_incomplete ORDER BY id_ressource")

    codes = {}
    for r in ressources:
        codes[r.id_ressource] = passport_code(r)

    return render_template(
        "rapports/index.html",
        demandes=demandes,
        ressources=ressources,
        unused=unused,
        unused_days=unused_days,
        compatible=compatible,
        demand_id=demand_id,
        max_km=max_km,
        historique=historique,
        hist_id=hist_id,
        scen_rows=scen_rows,
        scen_id=scen_id,
        multi=multi,
        incomplete=incomplete,
        codes=codes,
    )
