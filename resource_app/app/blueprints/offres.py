"""Offer list, creation and status changes."""

from __future__ import annotations

from datetime import date

from flask import Blueprint, flash, redirect, render_template, request, url_for
from sqlalchemy import select
from sqlalchemy.orm import joinedload

from app.db_utils import commit_session, run_view
from app.extensions import db
from app.forms import OffreForm, OffreStatutForm
from app.helpers import acting_entreprise_id, require_acting_entreprise
from app.models import Materiau, Offre, Ressource, STATUT_OFFRE

bp = Blueprint("offres", __name__, url_prefix="/offres")


@bp.route("/")
def list_offres():
    page = request.args.get("page", 1, type=int)
    statut = request.args.get("statut", "")
    materiau_id = request.args.get("materiau", type=int)
    entreprise_id = request.args.get("entreprise", type=int)

    query = (
        select(Offre)
        .options(joinedload(Offre.entreprise), joinedload(Offre.ressource))
        .order_by(Offre.id_offre.desc())
    )
    if statut:
        query = query.where(Offre.statut == statut)
    if entreprise_id:
        query = query.where(Offre.id_entreprise == entreprise_id)
    if materiau_id:
        from app.models import Composer

        query = query.join(Ressource, Offre.id_ressource == Ressource.id_ressource).join(
            Composer, Composer.id_ressource == Ressource.id_ressource
        ).where(Composer.id_materiau == materiau_id)

    pagination = db.paginate(query, page=page, per_page=10, error_out=False)
    counts = {
        row["id_offre"]: row["nb"]
        for row in run_view(
            """
            SELECT id_offre, COUNT(DISTINCT id_demande) AS nb
            FROM v_matching
            GROUP BY id_offre
            """
        )
    }
    materiaux = db.session.execute(select(Materiau).order_by(Materiau.nom)).scalars().all()
    from app.models import Entreprise

    entreprises = db.session.execute(select(Entreprise).order_by(Entreprise.nom)).scalars().all()
    return render_template(
        "offres/list.html",
        pagination=pagination,
        counts=counts,
        materiaux=materiaux,
        entreprises=entreprises,
        statuts=STATUT_OFFRE,
        filters={"statut": statut, "materiau": materiau_id, "entreprise": entreprise_id},
        statut_form=OffreStatutForm(),
    )


@bp.route("/nouvelle", methods=["GET", "POST"])
def create():
    blocked = require_acting_entreprise()
    if blocked:
        return blocked
    form = OffreForm()
    owned = (
        db.session.execute(
            select(Ressource)
            .where(Ressource.id_proprietaire == acting_entreprise_id())
            .order_by(Ressource.id_ressource)
        )
        .scalars()
        .all()
    )
    form.id_ressource.choices = [
        (r.id_ressource, f"#{r.id_ressource} — {r.quantite} {r.unite} ({r.localisation_actuelle})")
        for r in owned
    ]
    if form.validate_on_submit():
        db.session.add(
            Offre(
                date_publication=date.today(),
                quantite_proposee=form.quantite_proposee.data,
                prix=form.prix.data,
                statut="ouverte",
                id_entreprise=acting_entreprise_id(),
                id_ressource=form.id_ressource.data,
            )
        )
        error = commit_session()
        if error:
            flash(error, "danger")
        else:
            flash("Offre publiée.", "success")
            return redirect(url_for("offres.list_offres"))
    return render_template("offres/form.html", form=form, title="Nouvelle offre")


@bp.route("/<int:id_offre>/statut", methods=["POST"])
def change_status(id_offre: int):
    offre = db.session.get(Offre, id_offre)
    if offre is None:
        return render_template("errors/404.html"), 404
    form = OffreStatutForm()
    if form.validate_on_submit():
        offre.statut = form.statut.data
        error = commit_session()
        if error:
            flash(error, "danger")
        else:
            flash("Statut de l'offre mis à jour.", "success")
    return redirect(url_for("offres.list_offres"))
