"""Company CRUD, including roles in JOUER."""

from __future__ import annotations

from datetime import date

from flask import Blueprint, flash, redirect, render_template, request, url_for
from sqlalchemy import or_, select
from sqlalchemy.orm import joinedload

from app.db_utils import commit_session
from app.extensions import db
from app.forms import EntrepriseForm
from app.models import Entreprise, Jouer, Role

bp = Blueprint("entreprises", __name__, url_prefix="/entreprises")


def _load_role_choices(form: EntrepriseForm) -> None:
    form.roles.choices = [
        (r.id_role, r.libelle)
        for r in db.session.execute(select(Role).order_by(Role.libelle)).scalars()
    ]


@bp.route("/")
def list_entreprises():
    q = request.args.get("q", "").strip()
    page = request.args.get("page", 1, type=int)
    query = select(Entreprise).order_by(Entreprise.nom)
    if q:
        like = f"%{q}%"
        query = query.where(
            or_(
                Entreprise.nom.like(like),
                Entreprise.secteur.like(like),
                Entreprise.ville.like(like),
            )
        )
    pagination = db.paginate(query, page=page, per_page=10, error_out=False)
    return render_template("entreprises/list.html", pagination=pagination, q=q)


@bp.route("/nouvelle", methods=["GET", "POST"])
def create():
    form = EntrepriseForm()
    _load_role_choices(form)
    if not form.date_debut.data:
        form.date_debut.data = date.today()
    if form.validate_on_submit():
        entreprise = Entreprise(
            nom=form.nom.data.strip(),
            secteur=(form.secteur.data or "").strip() or None,
            ville=form.ville.data.strip(),
        )
        db.session.add(entreprise)
        db.session.flush()
        for role_id in form.roles.data:
            db.session.add(
                Jouer(
                    id_entreprise=entreprise.id_entreprise,
                    id_role=role_id,
                    date_debut=form.date_debut.data,
                )
            )
        error = commit_session()
        if error:
            flash(error, "danger")
        else:
            flash("Entreprise créée.", "success")
            return redirect(url_for("entreprises.detail", id_entreprise=entreprise.id_entreprise))
    return render_template("entreprises/form.html", form=form, title="Nouvelle entreprise")


@bp.route("/<int:id_entreprise>")
def detail(id_entreprise: int):
    entreprise = db.session.get(Entreprise, id_entreprise)
    if entreprise is None:
        return render_template("errors/404.html"), 404
    entreprise = db.session.execute(
        select(Entreprise)
        .options(joinedload(Entreprise.jouers).joinedload(Jouer.role))
        .where(Entreprise.id_entreprise == id_entreprise)
    ).unique().scalar_one()
    return render_template("entreprises/detail.html", entreprise=entreprise)


@bp.route("/<int:id_entreprise>/modifier", methods=["GET", "POST"])
def edit(id_entreprise: int):
    entreprise = db.session.get(Entreprise, id_entreprise)
    if entreprise is None:
        return render_template("errors/404.html"), 404
    form = EntrepriseForm(obj=entreprise)
    _load_role_choices(form)
    if request.method == "GET":
        form.roles.data = [j.id_role for j in entreprise.jouers]
        form.date_debut.data = date.today()
    if form.validate_on_submit():
        entreprise.nom = form.nom.data.strip()
        entreprise.secteur = (form.secteur.data or "").strip() or None
        entreprise.ville = form.ville.data.strip()
        selected = set(form.roles.data)
        existing = {j.id_role: j for j in entreprise.jouers}
        for role_id, jouer in list(existing.items()):
            if role_id not in selected:
                db.session.delete(jouer)
        for role_id in selected:
            if role_id not in existing:
                db.session.add(
                    Jouer(
                        id_entreprise=entreprise.id_entreprise,
                        id_role=role_id,
                        date_debut=form.date_debut.data,
                    )
                )
        error = commit_session()
        if error:
            flash(error, "danger")
        else:
            flash("Entreprise mise à jour.", "success")
            return redirect(url_for("entreprises.detail", id_entreprise=entreprise.id_entreprise))
    return render_template(
        "entreprises/form.html", form=form, title="Modifier l'entreprise", entreprise=entreprise
    )


@bp.route("/<int:id_entreprise>/supprimer", methods=["POST"])
def delete(id_entreprise: int):
    entreprise = db.session.get(Entreprise, id_entreprise)
    if entreprise is None:
        return render_template("errors/404.html"), 404
    db.session.delete(entreprise)
    error = commit_session()
    if error:
        flash(error, "danger")
        return redirect(url_for("entreprises.detail", id_entreprise=id_entreprise))
    flash("Entreprise supprimée.", "success")
    return redirect(url_for("entreprises.list_entreprises"))
