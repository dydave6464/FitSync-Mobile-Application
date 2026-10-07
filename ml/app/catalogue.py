"""The candidate query: which live exercises may this user be offered?

Three filters, all of which must pass:

  equipment -- the exercise's own implement is owned, AND every extra
               requirement (bench, pull-up bar, machines) is owned too
  injury    -- the exercise is not contraindicated for any reported region,
               and does not target a muscle group that region rules out
  category  -- the exercise is strength training, not a stretch, a mobility
               drill or a skill hold. An exercise with no category row counts
               as strength: a missing row must never silently remove an
               exercise. See the design, section 7.

The equipment tree is why the primary check walks parent_equipment_id:
`user_equipment` holds curated rows ('machines'), while `exercises` points at
raw catalogue tags ('cable', 'smith machine') which are children of them.
Comparing raw tag against curated id directly would make every machine
exercise invisible to every user. See the design, sections 3 and 5.
"""
from typing import List, NamedTuple, Optional, Sequence, Tuple, Dict

from sqlalchemy import bindparam, text
from sqlalchemy.engine import Engine


class Candidate(NamedTuple):
    exercise_id: int
    name: str
    muscle_group: str


_BASE = """
SELECT x.exercise_id, x.name, x.muscle_group
  FROM exercises x
  JOIN equipment eq ON eq.equipment_id = x.equipment_id
  LEFT JOIN equipment peq ON peq.equipment_id = eq.parent_equipment_id
  LEFT JOIN exercise_categories cat ON cat.exercise_id = x.exercise_id
 WHERE x.status = 'live'
   AND COALESCE(cat.category, 'strength') = 'strength'
   AND COALESCE(eq.parent_equipment_id, eq.equipment_id) IN :owned
   AND NOT EXISTS (
         SELECT 1 FROM exercise_equipment_requirements r
          WHERE r.exercise_id = x.exercise_id
            AND r.equipment_id NOT IN :owned
       )
"""

_INJURY = """
   AND NOT EXISTS (
         SELECT 1 FROM exercise_contraindications c
          WHERE c.exercise_id = x.exercise_id
            AND c.injury_id IN :injury_ids
       )
"""

_MUSCLE = """
   AND x.muscle_group NOT IN :excluded_muscle_groups
"""

# Body weight is unioned into `owned` unconditionally (see main.py), so
# body-weight exercises are eligible for every user -- and they cluster at low
# exercise_ids, so ordering by id alone hands a dumbbell owner a plan of
# push-ups. Their onboarding answer then has almost no effect on the plan.
#
# This tiers what the user actually SELECTED above what was merely unioned in
# for them. It changes only the ORDER, never which rows are eligible, so a user
# whose owned equipment covers a muscle group still falls back to body weight
# when nothing they own trains it.
#
# The COALESCE walks parent_equipment_id exactly as the eligibility filter
# does, so selecting the curated 'machines' chip also prefers its children
# ('cable', 'smith machine').
#
# Ordering, not ranking: fetch_candidates supplies the default order and a
# loaded model may reorder afterwards -- select() honours its caller's order.
# Tiering inside select() would silently override any future ranker.
_SELECTED_TIER = """
            CASE
              WHEN COALESCE(eq.parent_equipment_id, eq.equipment_id) IN :selected
              THEN 0 ELSE 1
            END"""

# Where the user trains decides which version of a movement comes first, once
# what they ticked has been honoured: machines and barbells at a gym, dumbbells,
# bands and body weight at home, kit-free work somewhere else. Matched on the
# curated name -- the parent's when there is one, as the eligibility filter
# walks it -- so 'cable' counts as 'machines'.
#
# ORDER only, never WHERE: a location can reshuffle a muscle group's options
# but never empty one, so it cannot produce a day the user cannot train.
# 'both' and an unanswered location express no preference.
LOCATION_FIRST: Dict[str, Tuple[str, ...]] = {
    "commercial_gym": ("machines", "barbell"),
    "home_gym": ("dumbbell", "band", "body weight", "kettlebell"),
    "other": ("body weight", "band", "pull-up bar"),
}

_LOCATION_TIER = """
            CASE
              WHEN COALESCE(peq.name, eq.name) IN :location_first
              THEN 0 ELSE 1
            END"""


def fetch_candidates(
    engine: Engine,
    owned_equipment_ids: Sequence[int],
    injury_ids: Sequence[int],
    excluded_muscle_groups: Sequence[str],
    selected_equipment_ids: Sequence[int] = (),
    training_location: Optional[str] = None,
) -> List[Candidate]:
    # An empty ownership list means the user owns nothing, not that no filter
    # applies. Returning [] is the safe reading; the caller substitutes body
    # weight when that is what it means.
    if not owned_equipment_ids:
        return []

    sql = _BASE
    params = {"owned": tuple(owned_equipment_ids)}

    if injury_ids:
        sql += _INJURY
        params["injury_ids"] = tuple(injury_ids)
    if excluded_muscle_groups:
        sql += _MUSCLE
        params["excluded_muscle_groups"] = tuple(excluded_muscle_groups)

    order = []
    if selected_equipment_ids:
        order.append(_SELECTED_TIER)
        params["selected"] = tuple(selected_equipment_ids)
    location_first = LOCATION_FIRST.get(training_location or "")
    if location_first:
        order.append(_LOCATION_TIER)
        params["location_first"] = location_first
    # exercise_id last, always: the tiers above only ever group rows, and a
    # stable final key is what keeps a plan identical across repeat requests.
    order.append("\n            x.exercise_id ASC")
    sql += "\n ORDER BY" + ",".join(order) + "\n"

    # expanding=True is what turns a Python tuple into a safely-parameterised
    # IN (...) list. Without it the tuple is bound as a single opaque value and
    # every query silently matches nothing.
    statement = text(sql).bindparams(
        *[bindparam(key, expanding=True) for key in params]
    )
    with engine.connect() as conn:
        rows = conn.execute(statement, params).fetchall()
    return [Candidate(r[0], r[1], r[2]) for r in rows]
