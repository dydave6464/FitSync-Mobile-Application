"""The wire contract, in code.

Node sends a subset of these request fields: only what the rules read, built
from an allowed list in server/src/services/ml/profile-payload.js. The other
optional profile fields (sex, dateOfBirth, body measurements, activityLevel,
reference names, injury side) are accepted but never arrive. The request
model is permissive on purpose: a profile can be almost empty during
onboarding, and rejecting it would block a user rather than give them a plan.
See the design, section 4.

trainingLocation arrives and orders the candidates (catalogue.LOCATION_FIRST).
"""
import math
from typing import Any, Dict, List, Optional, Union

from pydantic import BaseModel, Field, field_validator


class EquipmentRef(BaseModel):
    equipmentId: int
    name: Optional[str] = None


class InjuryRef(BaseModel):
    injuryId: int
    name: Optional[str] = None
    isLateral: Optional[bool] = None
    regionGroup: Optional[str] = None
    # Accepted, stored by Node, and deliberately unused here: the catalogue does
    # not record laterality per exercise, so a left and a right knee injury
    # exclude the same set. Recorded so the limit is explicit -- section 6.5.
    side: Optional[str] = None


class PlanOverrides(BaseModel):
    """What the generator screen lets someone choose.

    Every field optional and unvalidated here on purpose: the request model is
    permissive (see this module's docstring), and app.rules.parameters.derive
    is where an out-of-range day count is clamped and an unknown split style
    falls back to full body. Rejecting here would block a user from getting a
    plan at all.
    """
    splitStyle: Optional[str] = None
    daysPerWeek: Optional[int] = None
    sessionLengthMin: Optional[int] = None


class ProfileRequest(BaseModel):
    sex: Optional[str] = None
    dateOfBirth: Optional[Any] = None
    heightCm: Optional[float] = None
    weightKg: Optional[float] = None
    goalWeightKg: Optional[float] = None
    mainGoal: Optional[str] = None
    goals: List[str] = Field(default_factory=list)
    fitnessLevel: Optional[str] = None
    activityLevel: Optional[str] = None
    trainingLocation: Optional[str] = None
    equipment: List[EquipmentRef] = Field(default_factory=list)
    injuries: List[InjuryRef] = Field(default_factory=list)
    overrides: Optional[PlanOverrides] = None
    # True when the user's stored health check reports a condition or a
    # warning sign. The answers themselves never leave Node; this flag is all
    # the generator is told.
    healthCaution: bool = False


class PlanExercise(BaseModel):
    # The catalogue row this exercise was chosen from. The server saves the
    # plan by it; the name stays for reading, since two rows can share one.
    exerciseId: int
    name: str
    # Which rotation day this exercise belongs to, 1-based. Always 1 for a
    # full-body plan, which is every plan onboarding produces.
    dayNo: int = 1
    orderNo: int
    targetSets: int
    targetReps: str


class PlanResponse(BaseModel):
    name: str
    splitStyle: str
    daysPerWeek: int
    sessionLengthMin: int
    weekNo: int = 1
    exercises: List[PlanExercise]


class InjuryRiskRequest(BaseModel):
    checkins: List[Dict[str, Any]] = Field(default_factory=list)
    # allow_inf_nan=False so NaN and Infinity are a 422 rather than reaching the
    # clamp. NaN defeats min/max entirely -- every comparison with it is False --
    # and would otherwise produce a NaN score that crashes JSON serialisation.
    load: float = Field(0.0, allow_inf_nan=False)
    # The user's reported injuries from their profile, in the same InjuryRef
    # shape the plan payload uses. Only the count is read: the estimate asks
    # whether someone has been hurt before, not where. Kept as plain dicts so a
    # half-filled entry never costs the user an estimate.
    injuryHistory: List[Dict[str, Any]] = Field(default_factory=list)
    # The worst pain reported in session_outcomes over the last 14 days
    # (none|mild|moderate|severe). Null or absent means no reports, and an
    # unrecognised value is read the same way, like an unknown check-in answer.
    recentPain: Optional[str] = None

    @field_validator("load", mode="before")
    @classmethod
    def _sanitise_non_finite_load(cls, v):
        # allow_inf_nan=False alone rejects NaN/Infinity, but pydantic's
        # ValidationError echoes the raw rejected value back as `input`, and
        # Starlette's JSONResponse always serialises with allow_nan=False --
        # so a raw NaN/Infinity surviving into the 422 body would crash the
        # *error* response too, turning a clean 422 into an unhandled 500.
        # Swap it for None before the finite check runs, so whichever error
        # fires carries a JSON-safe `input` instead.
        if isinstance(v, float) and not math.isfinite(v):
            return None
        return v


class RiskDriver(BaseModel):
    """One input that raised the estimate, for the app's "Why this level".

    `value` keeps its wire type: a percentage for load, a count for
    injury_history, and the worst answer as a string for the rest. int comes
    first in the Union so pydantic's smart mode leaves a count as an int.
    """
    key: str
    value: Union[int, float, str]


class InjuryRiskResponse(BaseModel):
    riskLevel: str
    # The final 0-100 score, higher is riskier: max(model score, rules score).
    trainingLoadScore: float
    # "model" when the model's score decided it, "rules" when the rules' did or
    # no model is loaded.
    source: str = "rules"
    # Null when no model is loaded (or it failed on this request).
    modelVersion: Optional[str] = None
    # The training-load index as received: percent above the usual week.
    loadPct: Optional[float] = None
    # Up to three, most influential first; empty when nothing stood out.
    drivers: List[RiskDriver] = Field(default_factory=list)


# Worded as the app's goal screen words them, so a plan reads the way the
# user chose it. gain_strength is a legacy key the database can no longer
# store; kept so an old request still names its plan.
GOAL_LABELS = {
    "gain_strength": "Gain Strength",
    "build_muscle": "Build Muscle",
    "lose_weight": "Lose Fat",
    "improve_endurance": "Improve Endurance",
    "general_fitness": "General Health",
}
