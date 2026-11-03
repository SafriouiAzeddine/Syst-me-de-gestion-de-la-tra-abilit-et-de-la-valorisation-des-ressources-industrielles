"""Small helpers shared by blueprints (passport code, pagination, acting company)."""

from __future__ import annotations

from datetime import date
from math import ceil
from typing import Any, Iterable

from flask import flash, redirect, session, url_for
from sqlalchemy import func, select

from app.extensions import db
from app.models import DistanceVille, Entreprise, Materiau


STATUT_LABELS = {
    "disponible": "Disponible",
    "reservee": "Réservée",
    "en_transformation": "En transformation",
    "transformee": "Transformée",
    "recyclee": "Recyclée",
    "ouverte": "Ouverte",
    "cloturee": "Clôturée",
    "annulee": "Annulée",
    "satisfaite": "Satisfaite",
}
STATUT_BADGE = {
    "disponible": "success",
    "reservee": "warning",
    "en_transformation": "primary",
    "transformee": "secondary",
    "recyclee": "secondary",
    "ouverte": "success",
    "cloturee": "secondary",
    "annulee": "danger",
    "satisfaite": "info",
}
TYPE_EVENEMENT_LABELS = {
    "production": "Production",
    "decoupe": "Découpe",
    "stockage": "Stockage",
    "transport": "Transport",
    "controle": "Contrôle",
    "transformation": "Transformation",
    "vente": "Vente",
    "changement_localisation": "Changement de localisation",
}
TYPE_SCENARIO_LABELS = {
    "reutilisation": "Réutilisation",
    "transformation": "Transformation",
    "recyclage": "Recyclage",
    "autre": "Autre",
}
EVENT_ICONS = {
    "production": "bi-plus-circle",
    "decoupe": "bi-scissors",
    "stockage": "bi-box-seam",
    "transport": "bi-truck",
    "controle": "bi-clipboard-check",
    "transformation": "bi-gear",
    "vente": "bi-currency-exchange",
    "changement_localisation": "bi-geo-alt",
}


class Page:
    """Minimal pagination object compatible with the list templates."""

    def __init__(self, items: list[Any], page: int, per_page: int, total: int) -> None:
        self.items = items
        self.page = page
        self.per_page = per_page
        self.total = total
        self.pages = max(1, ceil(total / per_page)) if per_page else 1
        self.has_prev = page > 1
        self.has_next = page < self.pages
        self.prev_num = page - 1
        self.next_num = page + 1

    def iter_pages(self) -> Iterable[int | None]:
        for p in range(1, self.pages + 1):
            yield p


def paginate_rows(rows: list[Any], page: int, per_page: int = 10) -> Page:
    page = max(1, page)
    total = len(rows)
    start = (page - 1) * per_page
    return Page(rows[start : start + per_page], page, per_page, total)


def acting_entreprise_id() -> int | None:
    return session.get("entreprise_id")


def require_acting_entreprise():
    """Return a redirect response if no acting company is selected, else None."""
    if not session.get("entreprise_id"):
        flash("Sélectionnez une entreprise active dans la barre de navigation.", "warning")
        return redirect(url_for("dashboard.index"))
    return None


def passport_code(ressource: Ressource) -> str:
    """Display-only digital passport code, e.g. RS-ALU-00042."""
    main = None
    if ressource.composers:
        main = max(ressource.composers, key=lambda c: float(c.pourcentage or 0))
    letters = "XXX"
    if main and main.materiau and main.materiau.nom:
        alpha = "".join(ch for ch in main.materiau.nom.upper() if ch.isalpha())
        letters = (alpha[:3] + "XXX")[:3]
    return f"RS-{letters}-{ressource.id_ressource:05d}"


def city_choices() -> list[str]:
    """Cities known from companies or the distance table."""
    cities: set[str] = set()
    for (ville,) in db.session.execute(select(Entreprise.ville)).all():
        if ville:
            cities.add(ville)
    for ville_a, ville_b in db.session.execute(
        select(DistanceVille.ville_a, DistanceVille.ville_b)
    ).all():
        if ville_a:
            cities.add(ville_a)
        if ville_b:
            cities.add(ville_b)
    return sorted(cities)


def materiau_choices() -> list[tuple[int, str]]:
    return [
        (m.id_materiau, m.nom)
        for m in db.session.execute(select(Materiau).order_by(Materiau.nom)).scalars()
    ]


def entreprise_choices() -> list[tuple[int, str]]:
    return [
        (e.id_entreprise, f"{e.nom} ({e.ville})")
        for e in db.session.execute(select(Entreprise).order_by(Entreprise.nom)).scalars()
    ]


def missing_distance_pairs() -> list[tuple[str, str]]:
    """Pairs (resource city, company city) with no known distance."""
    sql = """
        SELECT DISTINCT r.localisation_actuelle AS v1, e.ville AS v2
        FROM RESSOURCE r
        CROSS JOIN ENTREPRISE e
        WHERE r.localisation_actuelle <> e.ville
          AND fn_distance(r.localisation_actuelle, e.ville) IS NULL
        ORDER BY v1, v2
    """
    from sqlalchemy import text

    try:
        rows = db.session.execute(text(sql)).all()
    except Exception:  # noqa: BLE001
        db.session.rollback()
        return []
    return [(r[0], r[1]) for r in rows]


def today() -> date:
    return date.today()


def count_star(model) -> int:
    return db.session.execute(select(func.count()).select_from(model)).scalar_one()
