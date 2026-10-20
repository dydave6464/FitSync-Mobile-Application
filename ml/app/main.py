"""FastAPI application for the FitSync ML service.

Node calls this service; it never calls Node. Every user field arrives in the
request body -- this process holds a read-only grant on the reference tables
it reads (server/MIGRATIONS.md) and reads no user row at request time. See
the design, section 3.
"""
import logging
import os
from typing import List

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException

from app.catalogue import fetch_candidates
from app.config import Settings
from app.db import create_engine_from
from app.ranker import Ranker
from app.risk_model import RiskModel, estimate as estimate_injury_risk
from app.rules import parameters, selection
from app.rules.splits import Split, label as split_label, resolve as resolve_split
from app.schemas import (
    GOAL_LABELS,
    InjuryRiskRequest,
    InjuryRiskResponse,
    PlanExercise,
    PlanResponse,
    ProfileRequest,
)

logger = logging.getLogger(__name__)

BODY_WEIGHT = "body weight"


def _plan_name(profile: ProfileRequest, split: Split) -> str:
    """The plan's name: the split, an em dash, then the goal.

    "Push / Pull / Legs — Build Muscle", say.

    The split half was hardcoded to "Full Body" while every plan was one,
    which outlived that: a push/pull/legs plan was literally named "Full
    Body — Build Muscle" on a card that also carried a "Push Pull Legs"
    label and a "Push" day eyebrow. splits.label derives it from the day
    names the plan is actually built from, and leaves full_body reading
    exactly as it always has.
    """
    focus = profile.mainGoal or ""
    label = GOAL_LABELS.get(focus, "General Health")
    # The other goals, in the order they arrived, known ones only, once each.
    # Only the focus sets the volume; the rest are named so the plan reads
    # the way the user chose it.
    others = []
    for goal in profile.goals:
        if goal != focus and goal in GOAL_LABELS and goal not in others:
            others.append(goal)
    if len(others) == 1:
        label = "{} + {}".format(label, GOAL_LABELS[others[0]])
    elif len(others) > 1:
        label = "{} + {} more".format(label, len(others))
    return "{} — {}".format(split_label(split), label)


def _candidates(engine, owned, selected, injury_ids, excluded, training_location=None,
                beginner_only=False):
    """Candidates with body weight confined to groups the user cannot train.

    `owned` is what is ELIGIBLE and already includes the implicit body weight;
    `selected` is only what the user ticked. Preferring `selected` inside a
    group was not enough. select() round-robins and comes back for a second
    exercise from the same group, so a dumbbell owner's second pectorals slot
    went to a push-up -- and a list whose top is dumbbells and whose tail is
    body weight still reads as the app ignoring the answer.

    So: ask for the user's own equipment first, and let body weight in only for
    the groups that returned nothing. Five real catalogue groups -- lats,
    abductors, adductors, spine, levator scapulae -- have no dumbbell exercise
    at all, and dropping them outright would quietly shrink the plan rather
    than fill those slots honestly.

    `beginner_only` reaches both queries, so the body-weight fill is
    beginner-friendly too: a group with no beginner-friendly exercise is left
    out rather than filled with one the team ruled out for a beginner.
    """
    everything = fetch_candidates(
        engine, owned, injury_ids, excluded, selected, training_location,
        beginner_only,
    )
    if not selected:
        return everything

    strict = fetch_candidates(
        engine, selected, injury_ids, excluded, selected, training_location,
        beginner_only,
    )
    covered = {c.muscle_group for c in strict}
    return strict + [c for c in everything if c.muscle_group not in covered]


def create_app(settings: Settings) -> FastAPI:
    logging.basicConfig(
        level=getattr(logging, settings.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    app = FastAPI(title="FitSync ML service")
    app.state.settings = settings
    app.state.engine = None
    app.state.ranker = Ranker.load(settings)
    # Loaded (or trained from the seeded simulation) once at startup. There is
    # no auto-reload: a new model file is picked up only on restart.
    app.state.risk_model = RiskModel.load(settings)

    def engine():
        # Built lazily so /health answers with MySQL down, and so a test that
        # never generates a plan never opens a connection.
        if app.state.engine is None:
            app.state.engine = create_engine_from(settings)
        return app.state.engine

    @app.get("/health")
    def health():
        ranker = app.state.ranker
        risk_model = app.state.risk_model
        return {
            "status": "ok",
            "model": ranker.status,
            "mode": ranker.mode,
            "riskModel": {"status": risk_model.status, "version": risk_model.version},
        }

    @app.post("/generate-plan", response_model=PlanResponse)
    def generate_plan(profile: ProfileRequest):
        overrides = profile.overrides.model_dump() if profile.overrides else None
        params = parameters.derive(profile.model_dump(), overrides)
        _, split = resolve_split(params.split_style)

        # Body weight is unioned in unconditionally, never only when the user
        # selected nothing: spec section 5's predicate is "(primary equipment
        # owned OR the exercise is body weight) AND every requirement owned".
        # Without this a user who ticks only Bench -- a curated chip with zero
        # exercises tagged to it -- gets no candidates at all and can never
        # finish onboarding, and a dumbbell owner loses every push-up.
        # Kept separate from `owned` on purpose. `owned` decides ELIGIBILITY and
        # includes the implicit body weight above; `selected` is only what the
        # user actually ticked, and decides ORDER. Collapsing the two is what
        # made a dumbbell owner's plan five-sixths push-ups: body weight passes
        # every equipment filter and sorts early by exercise_id.
        selected = sorted({e.equipmentId for e in profile.equipment})
        owned = list(set(selected) | set(_body_weight_ids(engine())))

        injury_ids = [i.injuryId for i in profile.injuries]
        if injury_ids and not _safety_data_loaded(engine()):
            # An empty table reads identically to "nothing is contraindicated"
            # -- every exercise would look safe for every injury, which is the
            # one failure mode this service must never return 200 for. Refuse
            # rather than silently generate an unsafe plan.
            logger.error(
                "generate-plan called with injuries %s but "
                "exercise_contraindications has no rows -- has seed:safety run?",
                injury_ids,
            )
            raise HTTPException(
                status_code=503,
                detail=(
                    "Injury safety data is not loaded: run "
                    "`npm run seed:safety` in server/ before generating "
                    "plans for injured users."
                ),
            )
        # An injury removes only the exercises the contraindication table rules
        # out for it (catalogue._INJURY). It used to remove every muscle group
        # of its body area too, which emptied whole split days: a knee took
        # every Legs exercise. The exercises it keeps now carry AI cues written
        # for the injury (server/src/db/cue-gate.js), so the area is coached,
        # not dropped.
        #
        # The same beginner rule derive() used for the volume: a beginner, or
        # anyone a health check asked to take it gently, is offered only the
        # exercises the team marked beginner-friendly.
        beginner_only = parameters.is_beginner_plan(profile.model_dump())
        candidates = _candidates(
            engine(), owned, selected, injury_ids, [], profile.trainingLocation,
            beginner_only,
        )

        ranked = app.state.ranker.rank(candidates)

        # One session per rotation day, each from that day's muscle pool. The
        # pools within a rotation are disjoint (see app/rules/splits), so an
        # exercise cannot land on two days and no de-duplication is needed.
        # select() itself is untouched: its priority walk and arm reservation
        # are exactly what each day needs, and a group with nothing in it is
        # already skipped rather than padded -- which is what lets a Legs day
        # tolerate having no arms to reserve.
        exercises: List[PlanExercise] = []
        unfillable: List[str] = []
        for day_index, day in enumerate(split.days, start=1):
            pool = ranked if not day.muscle_groups else [
                c for c in ranked if c.muscle_group in day.muscle_groups
            ]
            chosen = selection.select(pool, params.exercise_count)
            if not chosen:
                logger.warning(
                    "split %s day %d (%s) came back empty -- no eligible "
                    "candidates in its muscle pool",
                    params.split_style, day_index, day.name,
                )
                unfillable.append("day {} ({})".format(day_index, day.name))
            exercises.extend(
                PlanExercise(
                    exerciseId=candidate.exercise_id,
                    name=candidate.name,
                    dayNo=day_index,
                    # Restarts at 1 on each day: order_no is position WITHIN a
                    # day now, not within the plan.
                    orderNo=index + 1,
                    targetSets=params.target_sets,
                    targetReps=params.target_reps,
                )
                for index, candidate in enumerate(chosen)
            )

        if unfillable:
            # ONE empty day is enough to refuse, not just all of them. A plan
            # with a hole in it cannot be trained: nothing downstream handles
            # a rotation day with no exercises, and POST /sessions has already
            # created the session row by the time the logger finds out. The
            # honest alternatives are both worse -- filling a "Push" day from
            # the legs pool would label the rows something they are not, and
            # dropping the day would hand back a rotation whose length no
            # longer matches the split the caller asked for.
            #
            # This subsumes the older every-day-empty case: every split has at
            # least one day, so a plan with no exercises at all always has an
            # empty day 1 and lands here. Every realistic profile has
            # candidates; an empty day now means the contraindications for
            # several injuries cleared a pool, or something upstream is
            # broken, most likely an unseeded catalogue.
            #
            # Fail loudly: complete-onboarding generates before it marks the
            # user complete, so a 503 leaves them able to retry rather than
            # finishing onboarding holding an unusable plan. Naming the day is
            # what makes it actionable -- "nothing suitable" leaves a user with
            # no move, while "nothing for the Push day of this split" tells
            # them to choose a split their injuries leave room for.
            logger.error(
                "%s could not be filled (owned=%s, injuries=%s, split=%s) -- "
                "is the catalogue seeded?",
                ", ".join(unfillable),
                owned,
                [i.injuryId for i in profile.injuries],
                params.split_style,
            )
            raise HTTPException(
                status_code=503,
                detail=(
                    "No exercises could be selected for {} of the {} split. "
                    "If the catalogue is seeded, the reported injuries and "
                    "available equipment leave nothing suitable for it."
                ).format(" and ".join(unfillable), params.split_style),
            )

        return PlanResponse(
            name=_plan_name(profile, split),
            splitStyle=params.split_style,
            daysPerWeek=params.days_per_week,
            sessionLengthMin=params.session_length_min,
            weekNo=1,
            exercises=exercises,
        )

    @app.post("/injury-risk", response_model=InjuryRiskResponse)
    def injury_risk(payload: InjuryRiskRequest):
        # max(model score, rules score); the rules alone when no model loaded
        # or the model fails on this request. See app/risk_model.py.
        return estimate_injury_risk(payload, app.state.risk_model)

    return app


def _safety_data_loaded(engine_obj) -> bool:
    """Whether `exercise_contraindications` has been seeded at all.

    One cheap existence check, not a per-injury lookup: the guard this backs
    only needs to know the table is not simply empty (seed:safety never run),
    which would otherwise let every exercise look safe for every injury.
    """
    from sqlalchemy import text

    with engine_obj.connect() as conn:
        row = conn.execute(
            text("SELECT 1 FROM exercise_contraindications LIMIT 1")
        ).fetchone()
    return row is not None


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
