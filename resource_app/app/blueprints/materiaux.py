"""Material and role CRUD."""

from __future__ import annotations

from flask import Blueprint, flash, redirect, render_template, request, url_for
from sqlalchemy import or_, select

from app.db_utils import commit_session
from app.extensions import db
from app.forms import MateriauForm, RoleForm
from app.models import Materiau, Role

bp = Blueprint("materiaux", __name__, url_prefix="/materiaux")
roles_bp = Blueprint("roles", __name__, url_prefix="/roles")


@bp.route("/")
def list_materiaux():
    q = request.args.get("q", "").strip()
    page = request.args.get("page", 1, type=int)
    query = select(Materiau).order_by(Materiau.nom)
    if q:
        like = f"%{q}%"
        query = query.where(
            or_(Materiau.nom.like(like), Materiau.categorie.like(like), Materiau.proprietes.like(like))
        )
    pagination = db.paginate(query, page=page, per_page=10, error_out=False)
    return render_template("materiaux/list.html", pagination=pagination, q=q)


@bp.route("/nouveau", methods=["GET", "POST"])
def create():
    form = MateriauForm()
    if form.validate_on_submit():
        db.session.add(
            Materiau(
                nom=form.nom.data.strip(),
                categorie=(form.categorie.data or "").strip() or None,
                proprietes=(form.proprietes.data or "").strip() or None,
            )
        )
        error = commit_session()
        if error:
            flash(error, "danger")
        else:
            flash("Matériau créé.", "success")
            return redirect(url_for("materiaux.list_materiaux"))
    return render_template("materiaux/form.html", form=form, title="Nouveau matériau")


@bp.route("/<int:id_materiau>/modifier", methods=["GET", "POST"])
def edit(id_materiau: int):
    materiau = db.session.get(Materiau, id_materiau)
    if materiau is None:
        return render_template("errors/404.html"), 404
    form = MateriauForm(obj=materiau)
    if form.validate_on_submit():
        materiau.nom = form.nom.data.strip()
        materiau.categorie = (form.categorie.data or "").strip() or None
        materiau.proprietes = (form.proprietes.data or "").strip() or None
        error = commit_session()
        if error:
            flash(error, "danger")
        else:
            flash("Matériau mis à jour.", "success")
            return redirect(url_for("materiaux.list_materiaux"))
    return render_template("materiaux/form.html", form=form, title="Modifier le matériau")


@bp.route("/<int:id_materiau>/supprimer", methods=["POST"])
def delete(id_materiau: int):
    materiau = db.session.get(Materiau, id_materiau)
    if materiau is None:
        return render_template("errors/404.html"), 404
    db.session.delete(materiau)
    error = commit_session()
    if error:
        flash(error, "danger")
        return redirect(url_for("materiaux.list_materiaux"))
    flash("Matériau supprimé.", "success")
    return redirect(url_for("materiaux.list_materiaux"))


@roles_bp.route("/")
def list_roles():
    q = request.args.get("q", "").strip()
    page = request.args.get("page", 1, type=int)
    query = select(Role).order_by(Role.libelle)
    if q:
        query = query.where(Role.libelle.like(f"%{q}%"))
    pagination = db.paginate(query, page=page, per_page=10, error_out=False)
    return render_template("roles/list.html", pagination=pagination, q=q)


@roles_bp.route("/nouveau", methods=["GET", "POST"])
def create():
    form = RoleForm()
    if form.validate_on_submit():
        db.session.add(Role(libelle=form.libelle.data.strip()))
        error = commit_session()
        if error:
            flash(error, "danger")
        else:
            flash("Rôle créé.", "success")
            return redirect(url_for("roles.list_roles"))
    return render_template("roles/form.html", form=form, title="Nouveau rôle")


@roles_bp.route("/<int:id_role>/modifier", methods=["GET", "POST"])
def edit(id_role: int):
    role = db.session.get(Role, id_role)
    if role is None:
        return render_template("errors/404.html"), 404
    form = RoleForm(obj=role)
    if form.validate_on_submit():
        role.libelle = form.libelle.data.strip()
        error = commit_session()
        if error:
            flash(error, "danger")
        else:
            flash("Rôle mis à jour.", "success")
            return redirect(url_for("roles.list_roles"))
    return render_template("roles/form.html", form=form, title="Modifier le rôle")


@roles_bp.route("/<int:id_role>/supprimer", methods=["POST"])
def delete(id_role: int):
    role = db.session.get(Role, id_role)
    if role is None:
        return render_template("errors/404.html"), 404
    db.session.delete(role)
    error = commit_session()
    if error:
        flash(error, "danger")
        return redirect(url_for("roles.list_roles"))
    flash("Rôle supprimé.", "success")
    return redirect(url_for("roles.list_roles"))
