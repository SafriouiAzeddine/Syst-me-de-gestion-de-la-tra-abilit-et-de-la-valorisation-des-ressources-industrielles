"""Transactions. Owner update, sale event and offer closing are done by triggers."""

from __future__ import annotations

from datetime import date

from flask import Blueprint, flash, redirect, render_template, request, url_for
from sqlalchemy import select
from sqlalchemy.orm import aliased, joinedload

from app.db_utils import commit_session
from app.extensions import db
from app.forms import TransactionForm
from app.helpers import acting_entreprise_id, entreprise_choices, require_acting_entreprise
from app.models import Demande, Offre, Ressource, Transaction

bp = Blueprint("transactions", __name__, url_prefix="/transactions")


@bp.route("/")
def list_transactions():
    from app.models import Entreprise

    q = request.args.get("q", "").strip()
    page = request.args.get("page", 1, type=int)
    vendeur = aliased(Entreprise)
    acheteur = aliased(Entreprise)
    query = (
        select(Transaction)
        .join(vendeur, vendeur.id_entreprise == Transaction.id_vendeur)
        .join(acheteur, acheteur.id_entreprise == Transaction.id_acheteur)
        .options(
            joinedload(Transaction.ressource),
            joinedload(Transaction.vendeur),
            joinedload(Transaction.acheteur),
        )
        .order_by(Transaction.id_transaction.desc())
    )
    if q:
        like = f"%{q}%"
        query = query.where(vendeur.nom.like(like) | acheteur.nom.like(like))
    pagination = db.paginate(query, page=page, per_page=10, error_out=False)
    return render_template("transactions/list.html", pagination=pagination, q=q)


@bp.route("/nouvelle", methods=["GET", "POST"])
def create():
    blocked = require_acting_entreprise()
    if blocked:
        return blocked
    seller_id = acting_entreprise_id()
    form = TransactionForm()
    # All resources are listed so a sale by a non-owner can surface the trigger message.
    all_ressources = (
        db.session.execute(
            select(Ressource)
            .options(joinedload(Ressource.proprietaire))
            .order_by(Ressource.id_ressource)
        )
        .unique()
        .scalars()
        .all()
    )
    form.id_ressource.choices = [
        (
            r.id_ressource,
            f"#{r.id_ressource} — {r.quantite} {r.unite} (propriétaire : {r.proprietaire.nom})",
        )
        for r in all_ressources
    ]
    form.id_acheteur.choices = [(i, n) for i, n in entreprise_choices() if i != seller_id]
    if not form.date_transaction.data:
        form.date_transaction.data = date.today()

    # Prefill from a match (offer / demand ids).
    if request.method == "GET":
        id_offre = request.args.get("offre", type=int)
        id_demande = request.args.get("demande", type=int)
        if id_offre and id_demande:
            offre = db.session.get(Offre, id_offre)
            demande = db.session.get(Demande, id_demande)
            if offre and demande:
                form.id_ressource.data = offre.id_ressource
                form.id_acheteur.data = demande.id_entreprise
                form.quantite.data = min(offre.quantite_proposee, demande.quantite_requise)
                form.prix.data = offre.prix
                if offre.id_entreprise != seller_id:
                    flash(
                        "L'entreprise active n'est pas le vendeur de cette offre. "
                        "Sélectionnez l'entreprise de l'offre avant de confirmer.",
                        "warning",
                    )

    if form.validate_on_submit():
        db.session.add(
            Transaction(
                date_transaction=form.date_transaction.data,
                quantite=form.quantite.data,
                prix=form.prix.data,
                id_ressource=form.id_ressource.data,
                id_vendeur=seller_id,
                id_acheteur=form.id_acheteur.data,
            )
        )
        error = commit_session()
        if error:
            flash(error, "danger")
        else:
            flash("Propriétaire mis à jour", "success")
            return redirect(url_for("ressources.passport", id_ressource=form.id_ressource.data))
    return render_template("transactions/form.html", form=form, title="Nouvelle transaction")


@bp.route("/<int:id_transaction>")
def detail(id_transaction: int):
    tx = db.session.execute(
        select(Transaction)
        .options(
            joinedload(Transaction.ressource),
            joinedload(Transaction.vendeur),
            joinedload(Transaction.acheteur),
        )
        .where(Transaction.id_transaction == id_transaction)
    ).scalar_one_or_none()
    if tx is None:
        return render_template("errors/404.html"), 404
    return render_template("transactions/detail.html", tx=tx)
