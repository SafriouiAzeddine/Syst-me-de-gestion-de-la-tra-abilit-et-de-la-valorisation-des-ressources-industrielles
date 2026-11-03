"""Demand CRUD and compatible offers from v_matching."""

from __future__ import annotations

from flask import Blueprint, flash, redirect, render_template, request, url_for
from sqlalchemy import select
from sqlalchemy.orm import joinedload

from app.db_utils import commit_session, run_view
from app.extensions import db
from app.forms import DemandeForm, DemandeStatutForm
from app.helpers import acting_entreprise_id, materiau_choices, missing_distance_pairs, require_acting_entreprise
from app.models import Demande, Entreprise, Materiau, STATUT_DEMANDE

bp = Blueprint("demandes", __name__, url_prefix="/demandes")


@bp.route("/")
def list_demandes():
    page = request.args.get("page", 1, type=int)
    statut = request.args.get("statut", "")
    materiau_id = request.args.get("materiau", type=int)
    entreprise_id = request.args.get("entreprise", type=int)

    query = (
        select(Demande)
        .options(joinedload(Demande.entreprise), joinedload(Demande.materiau))
        .order_by(Demande.id_demande.desc())
    )
    if statut:
        query = query.where(Demande.statut == statut)
    if materiau_id:
        query = query.where(Demande.id_materiau == materiau_id)
    if entreprise_id:
        query = query.where(Demande.id_entreprise == entreprise_id)

    pagination = db.paginate(query, page=page, per_page=10, error_out=False)
    materiaux = db.session.execute(select(Materiau).order_by(Materiau.nom)).scalars().all()
    entreprises = db.session.execute(select(Entreprise).order_by(Entreprise.nom)).scalars().all()
    return render_template(
        "demandes/list.html",
        pagination=pagination,
        materiaux=materiaux,
        entreprises=entreprises,
        statuts=STATUT_DEMANDE,
        filters={"statut": statut, "materiau": materiau_id, "entreprise": entreprise_id},
        statut_form=DemandeStatutForm(),
    )


@bp.route("/nouvelle", methods=["GET", "POST"])
def create():
    blocked = require_acting_entreprise()
    if blocked:
        return blocked
    form = DemandeForm()
    form.id_materiau.choices = materiau_choices()
    if form.validate_on_submit():
        db.session.add(
            Demande(
                quantite_requise=form.quantite_requise.data,
                qualite_min=form.qualite_min.data,
                distance_max=form.distance_max.data,
                budget=form.budget.data,
                date_limite=form.date_limite.data,
                statut="ouverte",
                id_entreprise=acting_entreprise_id(),
                id_materiau=form.id_materiau.data,
            )
        )
        error = commit_session()
        if error:
            flash(error, "danger")
        else:
            flash("Demande créée.", "success")
            return redirect(url_for("demandes.list_demandes"))
    return render_template(
        "demandes/form.html",
        form=form,
        title="Nouvelle demande",
        missing_pairs=missing_distance_pairs(),
    )


@bp.route("/<int:id_demande>/statut", methods=["POST"])
def change_status(id_demande: int):
    demande = db.session.get(Demande, id_demande)
    if demande is None:
        return render_template("errors/404.html"), 404
    form = DemandeStatutForm()
    if form.validate_on_submit():
        demande.statut = form.statut.data
        error = commit_session()
        if error:
            flash(error, "danger")
        else:
            flash("Statut de la demande mis à jour.", "success")
    return redirect(url_for("demandes.list_demandes"))


@bp.route("/<int:id_demande>/offres")
def compatibles(id_demande: int):
    demande = db.session.get(Demande, id_demande)
    if demande is None:
        return render_template("errors/404.html"), 404
    rows = run_view(
        """
        SELECT * FROM v_matching
        WHERE id_demande = :id
        ORDER BY score_compatibilite DESC
        """,
        {"id": id_demande},
    )
    return render_template("demandes/compatibles.html", demande=demande, rows=rows)
