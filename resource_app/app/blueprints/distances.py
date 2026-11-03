"""CRUD for DISTANCE_VILLE, required by matching and fn_distance."""

from __future__ import annotations

from flask import Blueprint, flash, redirect, render_template, request, url_for
from sqlalchemy import or_, select

from app.db_utils import commit_session
from app.extensions import db
from app.forms import DistanceForm
from app.models import DistanceVille

bp = Blueprint("distances", __name__, url_prefix="/distances")


@bp.route("/")
def list_distances():
    q = request.args.get("q", "").strip()
    page = request.args.get("page", 1, type=int)
    query = select(DistanceVille).order_by(DistanceVille.ville_a, DistanceVille.ville_b)
    if q:
        like = f"%{q}%"
        query = query.where(or_(DistanceVille.ville_a.like(like), DistanceVille.ville_b.like(like)))
    pagination = db.paginate(query, page=page, per_page=10, error_out=False)
    return render_template("distances/list.html", pagination=pagination, q=q)


@bp.route("/nouvelle", methods=["GET", "POST"])
def create():
    form = DistanceForm()
    if form.validate_on_submit():
        db.session.add(
            DistanceVille(
                ville_a=form.ville_a.data.strip(),
                ville_b=form.ville_b.data.strip(),
                distance_km=form.distance_km.data,
            )
        )
        error = commit_session()
        if error:
            flash(error, "danger")
        else:
            flash("Distance enregistrée.", "success")
            return redirect(url_for("distances.list_distances"))
    return render_template("distances/form.html", form=form, title="Nouvelle distance")


@bp.route("/<ville_a>/<ville_b>/modifier", methods=["GET", "POST"])
def edit(ville_a: str, ville_b: str):
    row = db.session.get(DistanceVille, (ville_a, ville_b))
    if row is None:
        return render_template("errors/404.html"), 404
    form = DistanceForm(obj=row)
    if form.validate_on_submit():
        # Primary key may change: delete + insert in one transaction.
        db.session.delete(row)
        db.session.flush()
        db.session.add(
            DistanceVille(
                ville_a=form.ville_a.data.strip(),
                ville_b=form.ville_b.data.strip(),
                distance_km=form.distance_km.data,
            )
        )
        error = commit_session()
        if error:
            flash(error, "danger")
        else:
            flash("Distance mise à jour.", "success")
            return redirect(url_for("distances.list_distances"))
    return render_template("distances/form.html", form=form, title="Modifier la distance")


@bp.route("/<ville_a>/<ville_b>/supprimer", methods=["POST"])
def delete(ville_a: str, ville_b: str):
    row = db.session.get(DistanceVille, (ville_a, ville_b))
    if row is None:
        return render_template("errors/404.html"), 404
    db.session.delete(row)
    error = commit_session()
    if error:
        flash(error, "danger")
    else:
        flash("Distance supprimée.", "success")
    return redirect(url_for("distances.list_distances"))
