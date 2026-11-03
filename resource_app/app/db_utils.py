"""Helpers for views, stored procedures and database error messages."""

from __future__ import annotations

from datetime import date, datetime
from decimal import Decimal
from typing import Any, Mapping, Sequence

from sqlalchemy import text
from sqlalchemy.exc import DBAPIError, IntegrityError, SQLAlchemyError

from app.extensions import db


def _plain(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(value, date):
        return value.isoformat()
    return value


def run_view(sql: str, params: Mapping[str, Any] | None = None) -> list[dict[str, Any]]:
    """Execute a parameterized SELECT (typically against a view) and return dict rows."""
    result = db.session.execute(text(sql), params or {})
    return [{key: _plain(val) for key, val in dict(row).items()} for row in result.mappings().all()]


def call_procedure(name: str, params: Sequence[Any] = ()) -> list[dict[str, Any]]:
    """Call a stored procedure through the raw PyMySQL cursor.

    Procedures that return a result set (e.g. sp_ressources_inutilisees) are
    fetched with fetchall(). Procedures without a result set return [].
    """
    connection = db.session.connection()
    cursor = connection.connection.cursor()
    try:
        cursor.callproc(name, list(params))
        rows = cursor.fetchall()
        description = cursor.description
        if description is None:
            try:
                if cursor.nextset():
                    rows = cursor.fetchall()
                    description = cursor.description
            except Exception:
                description = None
        if not description:
            db.session.commit()
            return []
        columns = [col[0] for col in description]
        db.session.commit()
        return [
            {col: _plain(val) for col, val in zip(columns, row)}
            for row in rows
        ]
    except Exception:
        db.session.rollback()
        raise
    finally:
        cursor.close()


def friendly_db_error(exc: BaseException) -> str:
    """Translate MySQL / SQLAlchemy errors into short French messages."""
    orig = getattr(exc, "orig", None)
    if orig is not None:
        args = getattr(orig, "args", ())
        code = args[0] if args else None
        message = args[1] if len(args) > 1 else (str(orig) if orig else "")
        # SIGNAL SQLSTATE '45000' (triggers) -> MySQL error 1644
        if code == 1644 and message:
            return str(message)
        if message and code in {1644, 45000}:
            return str(message)
        if code == 1062:
            return "Cette valeur existe déjà dans la base de données."
        if code == 1451:
            return (
                "Impossible de supprimer cet enregistrement : "
                "il est encore référencé par d'autres données."
            )
        if code == 1452:
            return "Référence invalide : l'élément lié n'existe pas."
        if code == 3819:
            return "Les données ne respectent pas une contrainte de validation."
        if code == 1048:
            return "Un champ obligatoire est vide."
        if message:
            # Trigger messages are already in French.
            return str(message)

    if isinstance(exc, IntegrityError):
        text_err = str(exc).lower()
        if "duplicate" in text_err:
            return "Cette valeur existe déjà dans la base de données."
        if "foreign key" in text_err:
            return (
                "Impossible d'enregistrer : une contrainte de clé étrangère "
                "n'est pas respectée."
            )
        if "check" in text_err:
            return "Les données ne respectent pas une contrainte de validation."
        return "Les données violent une contrainte d'intégrité."

    if isinstance(exc, (DBAPIError, SQLAlchemyError)):
        return "Une erreur de base de données s'est produite. Vérifiez les données saisies."

    return "Une erreur inattendue s'est produite."


def commit_session() -> str | None:
    """Commit the current transaction. Return a French error message on failure."""
    try:
        db.session.commit()
        return None
    except Exception as exc:  # noqa: BLE001 — we always convert to a flash message
        db.session.rollback()
        return friendly_db_error(exc)
