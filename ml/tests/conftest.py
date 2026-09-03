import os
from pathlib import Path

import pytest
from dotenv import load_dotenv
from sqlalchemy import text

from app.config import Settings
from app.db import create_engine_from
from tests.dbgate import is_disposable, resolve_db_name, unavailable

# Load ml/.env (gitignored) so the test password is set once in a file rather
# than typed on every pytest run -- a command-line environment variable lands in
# shell history and in any transcript of the run.
load_dotenv(Path(__file__).resolve().parents[1] / ".env")

TEST_ENV = {
    "FITSYNC_DB_HOST": os.environ.get("FITSYNC_DB_HOST", "127.0.0.1"),
    "FITSYNC_DB_PORT": os.environ.get("FITSYNC_DB_PORT", "3306"),
    "FITSYNC_DB_USER": os.environ.get("FITSYNC_DB_USER", "fitsync"),
    "FITSYNC_DB_PASSWORD": os.environ.get("FITSYNC_DB_PASSWORD", ""),
    # Deliberately NOT FITSYNC_DB_NAME. That variable aims the service at a
    # database; these fixtures INSERT and DELETE, so the one they write to is
    # configured separately and can never be inherited from a service pointed
    # at the live catalogue. See tests/dbgate.py.
    "FITSYNC_DB_NAME": resolve_db_name(os.environ),
}

REQUIRED_TABLES = (
    "exercises",
    "equipment",
    "exercise_equipment_requirements",
    "exercise_contraindications",
    "exercise_categories",
)


@pytest.fixture(scope="session")
def settings():
    return Settings.from_env(TEST_ENV)


@pytest.fixture(scope="session")
def engine(settings):
    # Not conditional on FITSYNC_TEST_REQUIRE_DB: a suite aimed at a database
    # it may not write to is a misconfiguration, never something to skip past.
    if not is_disposable(settings.db_name):
        raise RuntimeError(
            "refusing to run destructive fixtures against {!r}: the ML test "
            "database name must end in `_test`. Set FITSYNC_TEST_DB_NAME."
            .format(settings.db_name)
        )

    try:
        eng = create_engine_from(settings)
        with eng.connect() as conn:
            present = {
                row[0]
                for row in conn.execute(
                    text(
                        "SELECT table_name FROM information_schema.tables "
                        "WHERE table_schema = :schema"
                    ),
                    {"schema": settings.db_name},
                )
            }
    except Exception as err:  # pragma: no cover - environment problem, not a bug
        unavailable(
            "cannot reach {}: {}".format(settings.db_name, err), os.environ
        )

    missing = [t for t in REQUIRED_TABLES if t not in present]
    if missing:
        unavailable(
            "missing tables {} in {} -- run `DB_NAME={} npm run migrate` from "
            "server/ first (create the database first if it does not exist; "
            "see ml/README.md)".format(missing, settings.db_name, settings.db_name),
            os.environ,
        )
    return eng


@pytest.fixture
def catalogue(engine):
    """Insert a small, fully-controlled reference catalogue and remove it after.

    Deliberately not the real seed: these tests assert the SQL's behaviour, and a
    fixture we own end to end makes an assertion failure mean the query is wrong
    rather than that the catalogue changed under us.
    """
    equipment = {
        "body weight": None,
        "dumbbell": None,
        "machines": None,
        "cable": "machines",     # child: owning 'machines' must reach it
        "bench": None,
        "pull-up bar": None,
    }
    exercises = [
        # (name, muscle_group, body_part, equipment tag)
        ("fixture push-up", "pectorals", "chest", "body weight"),
        ("fixture pull-up", "lats", "back", "body weight"),
        ("fixture dumbbell curl", "biceps", "upper arms", "dumbbell"),
        ("fixture dumbbell bench press", "pectorals", "chest", "dumbbell"),
        ("fixture cable row", "upper back", "back", "cable"),
        ("fixture squat", "quads", "upper legs", "body weight"),
        ("fixture quad stretch", "quads", "upper legs", "body weight"),
        # Pectorals deliberately has BOTH a body-weight option (fixture push-up,
        # a lower exercise_id) and a dumbbell one. Listed last so it sorts last
        # by id: without the selected-equipment preference push-up wins the
        # bucket, with it the dumbbell fly does. That is what makes the
        # preference tests discriminating rather than decorative.
        ("fixture dumbbell fly", "pectorals", "chest", "dumbbell"),
    ]
    # (exercise name, required curated equipment name)
    requirements = [
        ("fixture pull-up", "pull-up bar"),
        ("fixture dumbbell bench press", "bench"),
    ]
    # (exercise name, injury region name)
    contraindications = [("fixture squat", "Knee")]

    # (exercise name, category). `fixture push-up` is deliberately absent: it
    # is the uncategorised row that proves the COALESCE path still offers an
    # exercise with no category. Do NOT categorise `fixture pull-up` here --
    # it requires a pull-up bar, so an owned=[body weight] test would exclude
    # it on equipment and prove nothing about categories.
    categories = [
        ("fixture dumbbell curl", "strength"),
        ("fixture quad stretch", "stretch"),
    ]

    ids = {"equipment": {}, "exercises": {}, "injuries": {}}
    # Equipment names are globally unique (uq_equipment_name), and the test
    # database may already hold real ones if someone seeded it. Reuse a row that
    # exists and remember only the ones we created, so cleanup never deletes
    # somebody else's data.
    created_equipment = set()
    with engine.begin() as conn:
        for name in equipment:
            existing = conn.execute(
                text("SELECT equipment_id FROM equipment WHERE name = :n"),
                {"n": name},
            ).fetchone()
            if existing:
                ids["equipment"][name] = existing[0]
                continue
            res = conn.execute(
                text("INSERT INTO equipment (name) VALUES (:n)"), {"n": name}
            )
            ids["equipment"][name] = res.lastrowid
            created_equipment.add(name)
        for name, parent in equipment.items():
            if parent and name in created_equipment:
                conn.execute(
                    text(
                        "UPDATE equipment SET parent_equipment_id = :p "
                        "WHERE equipment_id = :id"
                    ),
                    {"p": ids["equipment"][parent], "id": ids["equipment"][name]},
                )
        for name, mg, bp, tag in exercises:
            res = conn.execute(
                text(
                    "INSERT INTO exercises (name, muscle_group, body_part, "
                    "equipment_id, status) VALUES (:n, :mg, :bp, :eq, 'live')"
                ),
                {"n": name, "mg": mg, "bp": bp, "eq": ids["equipment"][tag]},
            )
            ids["exercises"][name] = res.lastrowid
        for region in ("Knee", "Lower back"):
            res = conn.execute(
                text(
                    "INSERT INTO injuries (name, is_lateral, region_group) "
                    "VALUES (:n, 0, 'lower_body')"
                ),
                {"n": "fixture " + region},
            )
            ids["injuries"][region] = res.lastrowid
        for ex_name, eq_name in requirements:
            conn.execute(
                text(
                    "INSERT INTO exercise_equipment_requirements "
                    "(exercise_id, equipment_id) VALUES (:x, :e)"
                ),
                {"x": ids["exercises"][ex_name], "e": ids["equipment"][eq_name]},
            )
        for ex_name, region in contraindications:
            conn.execute(
                text(
                    "INSERT INTO exercise_contraindications "
                    "(exercise_id, injury_id, pattern) VALUES (:x, :i, 'fixture')"
                ),
                {"x": ids["exercises"][ex_name], "i": ids["injuries"][region]},
            )
        for ex_name, category in categories:
            conn.execute(
                text(
                    "INSERT INTO exercise_categories (exercise_id, category) "
                    "VALUES (:x, :c)"
                ),
                {"x": ids["exercises"][ex_name], "c": category},
            )

    yield ids

    with engine.begin() as conn:
        for exercise_id in ids["exercises"].values():
            conn.execute(
                text("DELETE FROM exercises WHERE exercise_id = :id"),
                {"id": exercise_id},
            )
        for injury_id in ids["injuries"].values():
            conn.execute(
                text("DELETE FROM injuries WHERE injury_id = :id"), {"id": injury_id}
            )
        for name in created_equipment:
            conn.execute(
                text("DELETE FROM equipment WHERE equipment_id = :id"),
                {"id": ids["equipment"][name]},
            )
