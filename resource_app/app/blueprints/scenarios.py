"""Second-life scenarios and comparison from v_comparaison_scenarios."""

from __future__ import annotations

from flask import Blueprint, flash, redirect, render_template, request, url_for
from sqlalchemy import select
from sqlalchemy.orm import joinedload

from app.db_utils import commit_session, run_view
from app.extensions import db
from app.forms import ScenarioForm
from app.helpers import passport_code
from app.models import Ressource, Scenario

bp = Blueprint("scenarios", __name__, url_prefix="/scenarios")


@bp.route("/")
def list_scenarios():
    page = request.args.get("page", 1, type=int)
    id_ressource = request.args.get("ressource", type=int)
    query = select(Scenario).options(joinedload(Scenario.ressource)).order_by(Scenario.id_scenario.desc())
    if id_ressource:
        query = query.where(Scenario.id_ressource == id_ressource)
    pagination = db.paginate(query, page=page, per_page=10, error_out=False)
    ressources = db.session.execute(select(Ressource).order_by(Ressource.id_ressource)).scalars().all()
    return render_template(
        "scenarios/list.html",
        pagination=pagination,
        ressources=ressources,
        id_ressource=id_ressource,
    )


@bp.route("/nouveau", methods=["GET", "POST"])
def create():
    form = ScenarioForm()
    form.id_ressource.choices = [
        (r.id_ressource, f"#{r.id_ressource} — {r.quantite} {r.unite}")
        for r in db.session.execute(select(Ressource).order_by(Ressource.id_ressource)).scalars()
    ]
    prefill = request.args.get("ressource", type=int)
    if request.method == "GET" and prefill:
        form.id_ressource.data = prefill
    if form.validate_on_submit():
        db.session.add(
            Scenario(
                type=form.type.data,
                cout_estime=form.cout_estime.data,
                valeur_estimee=form.valeur_estimee.data,
                distance_km=form.distance_km.data,
                impact_environnemental=form.impact_environnemental.data,
                id_ressource=form.id_ressource.data,
            )
        )
        error = commit_session()
        if error:
            flash(error, "danger")
        else:
            flash("Scénario enregistré.", "success")
            return redirect(url_for("scenarios.compare", id_ressource=form.id_ressource.data))
    return render_template("scenarios/form.html", form=form, title="Nouveau scénario")


@bp.route("/ressource/<int:id_ressource>")
def compare(id_ressource: int):
    ressource = db.session.get(Ressource, id_ressource)
    if ressource is None:
        return render_template("errors/404.html"), 404
    rows = run_view(
        """
        SELECT * FROM v_comparaison_scenarios
        WHERE id_ressource = :id
        ORDER BY rang
        """,
        {"id": id_ressource},
    )
    return render_template(
        "scenarios/compare.html",
        ressource=ressource,
        code=passport_code(ressource),
        rows=rows,
    )
