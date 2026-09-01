"""The wire contract, in code.

Every field here is one Node already sends or savePlan already consumes. The
request model is permissive on purpose: a profile can be almost empty during
onboarding, and rejecting it would block a user rather than give them a plan.
See the design, section 4.
"""
from typing import Any, Dict, List, Optional, Tuple

from pydantic import BaseModel, Field


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


class ProfileRequest(BaseModel):
    sex: Optional[str] = None
    dateOfBirth: Optional[Any] = None
    heightCm: Optional[float] = None
    weightKg: Optional[float] = None
    goalWeightKg: Optional[float] = None
    mainGoal: Optional[str] = None
    fitnessLevel: Optional[str] = None
    activityLevel: Optional[str] = None
    trainingLocation: Optional[str] = None
    equipment: List[EquipmentRef] = Field(default_factory=list)
    injuries: List[InjuryRef] = Field(default_factory=list)


class PlanExercise(BaseModel):
    name: str
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
    load: float = 0.0
    injuryHistory: List[Dict[str, Any]] = Field(default_factory=list)


class InjuryRiskResponse(BaseModel):
    riskLevel: str
    trainingLoadScore: float


# Target exclusion: the muscle groups a reported region rules out directly.
# This is the first of the two injury mechanisms; the second is the
# contraindication table, applied in SQL. See the design, section 6.5(a).
INJURY_MUSCLE_GROUPS: Dict[str, Tuple[str, ...]] = {
    "upper_body": ("delts", "pectorals", "triceps", "biceps", "forearms",
                   "lats", "upper back", "traps"),
    "back_core": ("spine", "abs", "upper back", "traps", "levator scapulae"),
    "lower_body": ("quads", "hamstrings", "glutes", "calves",
                   "adductors", "abductors"),
}

GOAL_LABELS = {
    "gain_strength": "Gain Strength",
    "build_muscle": "Build Muscle",
    "lose_weight": "Lose Weight",
    "general_fitness": "General Fitness",
}
