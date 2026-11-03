"""Resources, composition, digital passport and manual events."""

from __future__ import annotations

from datetime import datetime
from decimal import Decimal, InvalidOperation

from flask import Blueprint, flash, redirect, render_template, request, url_for
from sqlalchemy import select, text
from sqlalchemy.orm import joinedload

from app.db_utils import commit_session, run_view
from app.extensions import db
from app.forms import EvenementForm, RessourceForm
from app.helpers import (
    acting_entreprise_id,
    city_choices,
    entreprise_choices,
    missing_distance_pairs,
    passport_code,
    require_acting_entreprise,
)
from app.models import Composer, Entreprise, Evenement, Materiau, Ressource, STATUT_RESSOURCE

bp = Blueprint("ressources", __name__, url_prefix="/ressources")


def _parse_composition(form_data) -> tuple[list[tuple[int, Decimal]], str | None]:
    """Read dynamic composition rows. Return (pairs, error)."""
    ids = form_data.getlist("comp_materiau")
    pcts = form_data.getlist("comp_pct")
    pairs: list[tuple[int, Decimal]] = []
    seen: set[int] = set()
    total = Decimal("0")
    for raw_id, raw_pct in zip(ids, pcts):
        if not raw_id or not raw_pct:
            continue
        try:
            mid = int(raw_id)
            pct = Decimal(str(raw_pct))
        except (ValueError, InvalidOperation):
            return [], "Pourcentage ou matériau invalide dans la composition."
        if pct <= 0 or pct > 100:
            return [], "Chaque pourcentage doit être strictement positif et au plus 100."
        if mid in seen:
            return [], "Un matériau ne peut apparaître qu'une seule fois."
        seen.add(mid)
        pairs.append((mid, pct))
        total += pct
    if not pairs:
        return [], "Indiquez au moins un matériau dans la composition."
    if abs(total - Decimal("100")) > Decimal("0.01"):
        return [], "La composition doit totaliser 100 % (côté serveur)."
    return pairs, None


def _fill_ressource_choices(form: RessourceForm) -> None:
    cities = city_choices()
    form.localisation_actuelle.choices = [(c, c) for c in cities]
    form.id_producteur.choices = entreprise_choices()


def _apply_composition(ressource: Ressource, pairs: list[tuple[int, Decimal]]) -> None:
    for existing in list(ressource.composers):
        db.session.delete(existing)
    db.session.flush()
    for mid, pct in pairs:
        db.session.add(
            Composer(id_ressource=ressource.id_ressource, id_materiau=mid, pourcentage=pct)
        )


@bp.route("/")
def list_ressources():
    page = request.args.get("page", 1, type=int)
    statut = request.args.get("statut", "")
    materiau_id = request.args.get("materiau", type=int)
    owner_id = request.args.get("owner", type=int)
    ville = request.args.get("ville", "")
    qmin = request.args.get("qmin", type=float)
    qmax = request.args.get("qmax", type=float)

    query = (
        select(Ressource)
        .options(
            joinedload(Ressource.composers).joinedload(Composer.materiau),
            joinedload(Ressource.proprietaire),
            joinedload(Ressource.producteur),
        )
        .order_by(Ressource.id_ressource.desc())
    )
    if statut:
        query = query.where(Ressource.statut == statut)
    if owner_id:
        query = query.where(Ressource.id_proprietaire == owner_id)
    if ville:
        query = query.where(Ressource.localisation_actuelle == ville)
    if qmin is not None:
        query = query.where(Ressource.qualite >= qmin)
    if qmax is not None:
        query = query.where(Ressource.qualite <= qmax)
    if materiau_id:
        query = query.where(
            Ressource.id_ressource.in_(
                select(Composer.id_ressource).where(Composer.id_materiau == materiau_id)
            )
        )

    pagination = db.paginate(query, page=page, per_page=10, error_out=False)
    codes = {r.id_ressource: passport_code(r) for r in pagination.items}
    materiaux = db.session.execute(select(Materiau).order_by(Materiau.nom)).scalars().all()
    entreprises = db.session.execute(select(Entreprise).order_by(Entreprise.nom)).scalars().all()
    return render_template(
        "ressources/list.html",
        pagination=pagination,
        codes=codes,
        materiaux=materiaux,
        entreprises=entreprises,
        cities=city_choices(),
        statuts=STATUT_RESSOURCE,
        filters={
            "statut": statut,
            "materiau": materiau_id,
            "owner": owner_id,
            "ville": ville,
            "qmin": qmin,
            "qmax": qmax,
        },
    )


@bp.route("/nouvelle", methods=["GET", "POST"])
def create():
    blocked = require_acting_entreprise()
    if blocked:
        return blocked
    form = RessourceForm()
    _fill_ressource_choices(form)
    if request.method == "GET":
        form.id_producteur.data = acting_entreprise_id()
        form.statut.data = "disponible"
    materiaux = db.session.execute(select(Materiau).order_by(Materiau.nom)).scalars().all()
    if form.validate_on_submit():
        pairs, comp_error = _parse_composition(request.form)
        if not form.id_producteur.data:
            flash("Le producteur est obligatoire.", "danger")
        elif comp_error:
            flash(comp_error, "danger")
        else:
            producer_id = form.id_producteur.data
            ressource = Ressource(
                quantite=form.quantite.data,
                unite=form.unite.data.strip(),
                qualite=form.qualite.data,
                statut=form.statut.data,
                localisation_actuelle=form.localisation_actuelle.data,
                date_disponibilite=form.date_disponibilite.data,
                id_producteur=producer_id,
                id_proprietaire=producer_id,
            )
            db.session.add(ressource)
            db.session.flush()
            _apply_composition(ressource, pairs)
            error = commit_session()
            if error:
                flash(error, "danger")
            else:
                flash("Ressource créée. L'événement de production a été enregistré automatiquement.", "success")
                return redirect(url_for("ressources.passport", id_ressource=ressource.id_ressource))
    return render_template(
        "ressources/form.html",
        form=form,
        title="Nouvelle ressource",
        materiaux=materiaux,
        missing_pairs=missing_distance_pairs(),
        composition=[],
        edit_mode=False,
    )


@bp.route("/<int:id_ressource>/modifier", methods=["GET", "POST"])
def edit(id_ressource: int):
    ressource = db.session.execute(
        select(Ressource)
        .options(joinedload(Ressource.composers), joinedload(Ressource.producteur), joinedload(Ressource.proprietaire))
        .where(Ressource.id_ressource == id_ressource)
    ).unique().scalar_one_or_none()
    if ressource is None:
        return render_template("errors/404.html"), 404
    form = RessourceForm(obj=ressource)
    _fill_ressource_choices(form)
    materiaux = db.session.execute(select(Materiau).order_by(Materiau.nom)).scalars().all()
    if form.validate_on_submit():
        pairs, comp_error = _parse_composition(request.form)
        if comp_error:
            flash(comp_error, "danger")
        else:
            ressource.quantite = form.quantite.data
            ressource.unite = form.unite.data.strip()
            ressource.qualite = form.qualite.data
            ressource.statut = form.statut.data
            ressource.localisation_actuelle = form.localisation_actuelle.data
            ressource.date_disponibilite = form.date_disponibilite.data
            _apply_composition(ressource, pairs)
            error = commit_session()
            if error:
                flash(error, "danger")
            else:
                flash("Ressource mise à jour.", "success")
                return redirect(url_for("ressources.passport", id_ressource=id_ressource))
    return render_template(
        "ressources/form.html",
        form=form,
        title="Modifier la ressource",
        materiaux=materiaux,
        missing_pairs=missing_distance_pairs(),
        composition=ressource.composers,
        edit_mode=True,
        ressource=ressource,
    )


@bp.route("/<int:id_ressource>")
def passport(id_ressource: int):
    ressource = db.session.execute(
        select(Ressource)
        .options(
            joinedload(Ressource.composers).joinedload(Composer.materiau),
            joinedload(Ressource.producteur),
            joinedload(Ressource.proprietaire),
            joinedload(Ressource.offres),
            joinedload(Ressource.transactions),
        )
        .where(Ressource.id_ressource == id_ressource)
    ).unique().scalar_one_or_none()
    if ressource is None:
        return render_template("errors/404.html"), 404

    historique = run_view(
        """
        SELECT date_heure, type, description, acteur
        FROM v_historique_ressource
        WHERE id_ressource = :id
        ORDER BY date_heure
        """,
        {"id": id_ressource},
    )
    scenarios = run_view(
        """
        SELECT id_scenario, type, cout_estime, valeur_estimee, gain_net,
               distance_km, impact_environnemental, rang
        FROM v_comparaison_scenarios
        WHERE id_ressource = :id
        ORDER BY rang
        """,
        {"id": id_ressource},
    )
    matches = run_view(
        """
        SELECT * FROM v_matching WHERE id_ressource = :id
        ORDER BY score_compatibilite DESC
        """,
        {"id": id_ressource},
    )
    event_form = EvenementForm()
    return render_template(
        "ressources/passport.html",
        ressource=ressource,
        code=passport_code(ressource),
        historique=historique,
        scenarios=scenarios,
        matches=matches,
        event_form=event_form,
    )


@bp.route("/<int:id_ressource>/evenements", methods=["POST"])
def add_event(id_ressource: int):
    blocked = require_acting_entreprise()
    if blocked:
        return blocked
    ressource = db.session.get(Ressource, id_ressource)
    if ressource is None:
        return render_template("errors/404.html"), 404
    form = EvenementForm()
    if form.validate_on_submit():
        when = form.date_heure.data or datetime.now()
        db.session.add(
            Evenement(
                type=form.type.data,
                date_heure=when,
                description=form.description.data,
                id_ressource=id_ressource,
                id_entreprise=acting_entreprise_id(),
            )
        )
        error = commit_session()
        if error:
            flash(error, "danger")
        else:
            flash("Événement ajouté à l'historique.", "success")
    else:
        flash("Formulaire d'événement invalide.", "danger")
    return redirect(url_for("ressources.passport", id_ressource=id_ressource) + "#historique")
