"""Application factory for RE:SOURCE."""

from __future__ import annotations

from flask import Flask, flash, redirect, render_template, request, session, url_for
from sqlalchemy import select, text

from app.config import Config
from app.extensions import csrf, db


def create_app(config_class: type = Config) -> Flask:
    app = Flask(__name__)
    app.config.from_object(config_class)

    db.init_app(app)
    csrf.init_app(app)
    from app.helpers import (
    EVENT_ICONS,
    STATUT_BADGE,
    STATUT_LABELS,
    TYPE_EVENEMENT_LABELS,
    TYPE_SCENARIO_LABELS,
    passport_code,
    )

    from app.blueprints.dashboard import bp as dashboard_bp
    from app.blueprints.demandes import bp as demandes_bp
    from app.blueprints.distances import bp as distances_bp
    from app.blueprints.entreprises import bp as entreprises_bp
    from app.blueprints.matching import bp as matching_bp
    from app.blueprints.materiaux import bp as materiaux_bp
    from app.blueprints.materiaux import roles_bp
    from app.blueprints.offres import bp as offres_bp
    from app.blueprints.rapports import bp as rapports_bp
    from app.blueprints.ressources import bp as ressources_bp
    from app.blueprints.scenarios import bp as scenarios_bp
    from app.blueprints.transactions import bp as transactions_bp
    from .helpers import STATUT_BADGE

    app.register_blueprint(dashboard_bp)
    app.register_blueprint(entreprises_bp)
    app.register_blueprint(materiaux_bp)
    app.register_blueprint(roles_bp)
    app.register_blueprint(ressources_bp)
    app.register_blueprint(offres_bp)
    app.register_blueprint(demandes_bp)
    app.register_blueprint(matching_bp)
    app.register_blueprint(scenarios_bp)
    app.register_blueprint(transactions_bp)
    app.register_blueprint(rapports_bp)
    app.register_blueprint(distances_bp)
    app.jinja_env.globals["STATUT_BADGE"] = STATUT_BADGE
    app.jinja_env.globals.update(
    STATUT_BADGE=STATUT_BADGE,
    STATUT_LABELS=STATUT_LABELS,
    TYPE_EVENEMENT_LABELS=TYPE_EVENEMENT_LABELS,
    TYPE_SCENARIO_LABELS=TYPE_SCENARIO_LABELS,
    EVENT_ICONS=EVENT_ICONS,
    passport_code=passport_code,
    )

    _register_context(app)
    _register_session_routes(app)
    _register_error_handlers(app)
    _register_cli(app)
    return app


def _register_context(app: Flask) -> None:
    @app.context_processor
    def inject_globals():
        from app.helpers import (
            EVENT_ICONS,
            STATUT_BADGE,
            STATUT_LABELS,
            TYPE_EVENEMENT_LABELS,
            TYPE_SCENARIO_LABELS,
            acting_entreprise_id,
        )
        from app.models import Entreprise

        try:
            entreprises = (
                db.session.execute(select(Entreprise).order_by(Entreprise.nom)).scalars().all()
            )
        except Exception:  # noqa: BLE001
            db.session.rollback()
            entreprises = []
        eid = acting_entreprise_id()
        acting = next((e for e in entreprises if e.id_entreprise == eid), None)
        return {
            "all_entreprises": entreprises,
            "acting_entreprise": acting,
            "STATUT_LABELS": STATUT_LABELS,
            "STATUT_BADGE": STATUT_BADGE,
            "TYPE_EVENEMENT_LABELS": TYPE_EVENEMENT_LABELS,
            "TYPE_SCENARIO_LABELS": TYPE_SCENARIO_LABELS,
            "EVENT_ICONS": EVENT_ICONS,
        }


def _register_session_routes(app: Flask) -> None:
    @app.route("/entreprise-active", methods=["POST"])
    def set_entreprise():
        eid = request.form.get("entreprise_id", type=int)
        if eid:
            session["entreprise_id"] = eid
            flash("Entreprise active mise à jour.", "success")
        else:
            session.pop("entreprise_id", None)
            flash("Aucune entreprise active.", "info")
        return redirect(request.referrer or url_for("dashboard.index"))


def _register_error_handlers(app: Flask) -> None:
    @app.errorhandler(404)
    def not_found(_e):
        return render_template("errors/404.html"), 404

    @app.errorhandler(500)
    def server_error(_e):
        return render_template("errors/500.html"), 500


def _register_cli(app: Flask) -> None:
    @app.cli.command("check-db")
    def check_db():
        """Verify the MySQL connection and that resource_db is reachable."""
        db.session.execute(text("SELECT 1"))
        print("Database connection OK.")
