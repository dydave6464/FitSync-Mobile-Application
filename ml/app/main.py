"""FastAPI application for the FitSync ML service.

Node calls this service; it never calls Node. Every user field arrives in the
request body -- this process holds a read-only grant on four reference tables
and reads no user row at request time. See the design, section 3.
"""
import logging
import os

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException

from app.catalogue import fetch_candidates
from app.config import Settings
from app.db import create_engine_from
from app.ranker import Ranker
from app.risk import estimate as estimate_injury_risk
from app.rules import parameters, selection
from app.schemas import (
    GOAL_LABELS,
    INJURY_MUSCLE_GROUPS,
    InjuryRiskRequest,
    InjuryRiskResponse,
    PlanExercise,
    PlanResponse,
    ProfileRequest,
)

logger = logging.getLogger(__name__)

BODY_WEIGHT = "body weight"


def _plan_name(profile: ProfileRequest) -> str:
    goal = GOAL_LABELS.get(profile.mainGoal or "", "General Fitness")
    return "Full Body — {}".format(goal)


def create_app(settings: Settings) -> FastAPI:
    app = FastAPI(title="FitSync ML service")
    app.state.settings = settings
    app.state.engine = None
    app.state.ranker = Ranker.load(settings)

    def engine():
        # Built lazily so /health answers with MySQL down, and so a test that
        # never generates a plan never opens a connection.
        if app.state.engine is None:
            app.state.engine = create_engine_from(settings)
        return app.state.engine

    @app.get("/health")
    def health():
        ranker = app.state.ranker
        return {"status": "ok", "model": ranker.status, "mode": ranker.mode}

    @app.post("/generate-plan", response_model=PlanResponse)
    def generate_plan(profile: ProfileRequest):
        params = parameters.derive(profile.dict())

        owned = [e.equipmentId for e in profile.equipment]
        if not owned:
            # A user reaches Home with no equipment -- profile_nudge.dart calls
            # that a supported state. Body weight is the honest reading of it.
            owned = _body_weight_ids(engine())

        excluded = []
        for injury in profile.injuries:
            excluded.extend(INJURY_MUSCLE_GROUPS.get(injury.regionGroup or "", ()))

        candidates = fetch_candidates(
            engine(),
            owned,
            [i.injuryId for i in profile.injuries],
            sorted(set(excluded)),
        )
        ranked = app.state.ranker.rank(candidates)
        chosen = selection.select(ranked, params.exercise_count)

        if not chosen:
            # A plan with no exercises is not a plan. Every realistic profile has
            # candidates -- even a body-weight-only user with a back injury has 89
            # across 10 muscle groups -- so an empty session means something
            # upstream is broken, most likely an unseeded catalogue. Fail loudly:
            # complete-onboarding generates before it marks the user complete, so
            # a 503 leaves them able to retry rather than finishing onboarding
            # holding an empty plan.
            logger.error(
                "no candidates for profile (owned=%s, injuries=%s) -- is the "
                "catalogue seeded?",
                owned,
                [i.injuryId for i in profile.injuries],
            )
            raise HTTPException(
                status_code=503,
                detail=(
                    "No exercises available for this profile. "
                    "The catalogue may not be seeded."
                ),
            )

        return PlanResponse(
            name=_plan_name(profile),
            splitStyle=params.split_style,
            daysPerWeek=params.days_per_week,
            sessionLengthMin=params.session_length_min,
            weekNo=1,
            exercises=[
                PlanExercise(
                    name=candidate.name,
                    orderNo=index + 1,
                    targetSets=params.target_sets,
                    targetReps=params.target_reps,
                )
                for index, candidate in enumerate(chosen)
            ],
        )

    @app.post("/injury-risk", response_model=InjuryRiskResponse)
    def injury_risk(payload: InjuryRiskRequest):
        return estimate_injury_risk(payload)

    return app


def _body_weight_ids(engine_obj):
    from sqlalchemy import text

    with engine_obj.connect() as conn:
        rows = conn.execute(
            text("SELECT equipment_id FROM equipment WHERE name = :n"),
            {"n": BODY_WEIGHT},
        ).fetchall()
    if not rows:
        # Distinct from "no candidates": this one means seed-equipment.js has
        # not run, and says so rather than leaving an empty plan to explain.
        logger.error(
            "no '%s' row in equipment -- seed-equipment.js has not run", BODY_WEIGHT
        )
    return [row[0] for row in rows]


def build() -> FastAPI:
    """Entry point for `uvicorn app.main:build --factory`."""
    load_dotenv()
    return create_app(Settings.from_env(os.environ))
