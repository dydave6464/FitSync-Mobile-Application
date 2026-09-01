"""How the ML suite reacts to a test database it cannot use.

The Node suite drops every table in its test database
(`server/tests/helpers/test-db.js`), and both suites used to point at
`fitsync_test`. So `npm test` removed the tables these tests need, the fixtures
answered a missing table with `pytest.skip`, and pytest exited 0. Twenty tests
stopped running and the suite still reported success -- the failure mode where
absence of coverage is indistinguishable from passing.

Two guards, because they close different halves:

- `resolve_db_name` gives the ML suite a database the Node suite never touches,
  so the collision cannot happen.
- `unavailable` turns the skip into a failure when FITSYNC_TEST_REQUIRE_DB is
  set. Separation alone would not catch a database nobody ever migrated; that
  still skips, and still exits 0.
"""
import pytest

DEFAULT_TEST_DB = "fitsync_ml_test"
# What server/tests/helpers/test-db.js drops. Named here so the test asserting
# we do not share it reads as the deliberate check it is.
NODE_TEST_DB = "fitsync_test"
TRUTHY = frozenset({"1", "true", "yes", "on"})


def require_db(env):
    """True when an unusable database must fail the run rather than skip it."""
    return env.get("FITSYNC_TEST_REQUIRE_DB", "").strip().lower() in TRUTHY


def resolve_db_name(env):
    """The database the ML tests read and write."""
    return (env.get("FITSYNC_TEST_DB_NAME") or "").strip() or DEFAULT_TEST_DB


def is_disposable(name):
    """True when `name` is a test database the fixtures may write to.

    The catalogue fixture INSERTs and DELETEs. Pointed at `fitsync` it would
    write fixture exercises into the live catalogue, so anything not ending in
    `_test` is refused.
    """
    return bool(name) and name.endswith("_test")


def unavailable(reason, env):
    """Skip, or fail when the caller demanded a usable database."""
    if require_db(env):
        pytest.fail(reason, pytrace=False)
    pytest.skip(reason)
