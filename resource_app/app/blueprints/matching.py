"""Matching from v_matching and persistence via sp_generer_correspondances."""

from __future__ import annotations

from flask import Blueprint, flash, redirect, render_template, request, url_for
from sqlalchemy import select
from sqlalchemy.orm import joinedload

from app.db_utils import call_procedure, friendly_db_error, run_view
from app.extensions import db
from app.forms import ConfirmForm
from app.helpers import paginate_rows
from app.models import Demande, Materiau

bp = Blueprint("matching", __name__, url_prefix="/matching")


@bp.route("/")
def index():
    id_demande = request.args.get("demande", type=int)
    materiau = request.args.get("materiau", "")
    score_min = request.args.get("score_min", type=float)
    page = request.args.get("page", 1, type=int)

    sql = """
        SELECT * FROM v_matching
        WHERE 1 = 1
    """
    params: dict = {}
    if id_demande:
        sql += " AND id_demande = :id_demande"
        params["id_demande"] = id_demande
    if materiau:
        sql += " AND materiau = :materiau"
        params["materiau"] = materiau
    if score_min is not None:
        sql += " AND score_compatibilite >= :score_min"
        params["score_min"] = score_min
    sql += " ORDER BY score_compatibilite DESC"
    rows = run_view(sql, params)
    pagination = paginate_rows(rows, page, 10)

    stored = run_view(
        """
        SELECT c.id_offre, c.id_demande, c.score_compatibilite, c.distance_km,
               o.id_ressource, o.quantite_proposee, o.prix,
               eo.nom AS entreprise_offre, ed.nom AS entreprise_demande,
               m.nom AS materiau, d.quantite_requise
        FROM CORRESPONDRE c
        JOIN OFFRE o ON o.id_offre = c.id_offre
        JOIN DEMANDE d ON d.id_demande = c.id_demande
        JOIN ENTREPRISE eo ON eo.id_entreprise = o.id_entreprise
        JOIN ENTREPRISE ed ON ed.id_entreprise = d.id_entreprise
        JOIN MATERIAU m ON m.id_materiau = d.id_materiau
        ORDER BY c.score_compatibilite DESC
        """
    )
    demandes = (
        db.session.execute(
            select(Demande).options(joinedload(Demande.entreprise)).order_by(Demande.id_demande.desc())
        )
        .unique()
        .scalars()
        .all()
    )
    materiaux = db.session.execute(select(Materiau).order_by(Materiau.nom)).scalars().all()
    return render_template(
        "matching/index.html",
        pagination=pagination,
        stored=stored,
        demandes=demandes,
        materiaux=materiaux,
        filters={"demande": id_demande, "materiau": materiau, "score_min": score_min},
        confirm_form=ConfirmForm(),
    )


@bp.route("/enregistrer", methods=["POST"])
def enregistrer():
    form = ConfirmForm()
    if not form.validate_on_submit():
        flash("Requête invalide.", "danger")
        return redirect(url_for("matching.index"))
    try:
        call_procedure("sp_generer_correspondances")
        flash("Correspondances enregistrées dans CORRESPONDRE.", "success")
    except Exception as exc:  # noqa: BLE001
        flash(friendly_db_error(exc), "danger")
    return redirect(url_for("matching.index") + "#enregistrees")
