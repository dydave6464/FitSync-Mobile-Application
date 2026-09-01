"""The two guards over the test database. See tests/dbgate.py for why."""
import pytest

from tests.dbgate import (
    NODE_TEST_DB,
    is_disposable,
    require_db,
    resolve_db_name,
    unavailable,
)


def test_an_unusable_database_skips_by_default():
    # A laptop with no MySQL should not fail the suite it cannot run.
    with pytest.raises(pytest.skip.Exception):
        unavailable("no tables", {})


def test_require_db_turns_the_skip_into_a_failure():
    # The whole point: a skip exits 0, so CI cannot tell "20 tests passed"
    # from "20 tests never ran".
    with pytest.raises(pytest.fail.Exception):
        unavailable("no tables", {"FITSYNC_TEST_REQUIRE_DB": "1"})


@pytest.mark.parametrize("value", ["1", "true", "TRUE", "yes", "on", " 1 "])
def test_require_db_accepts_the_usual_spellings_of_true(value):
    assert require_db({"FITSYNC_TEST_REQUIRE_DB": value}) is True


@pytest.mark.parametrize("value", ["", "0", "false", "no", "off", "   "])
def test_require_db_stays_off_for_anything_else(value):
    assert require_db({"FITSYNC_TEST_REQUIRE_DB": value}) is False


def test_require_db_is_off_when_unset():
    assert require_db({}) is False


def test_the_ml_suite_does_not_share_the_node_suites_database():
    # server/tests/helpers/test-db.js drops every table in NODE_TEST_DB.
    # Sharing it is what silently disabled 20 tests.
    assert resolve_db_name({}) != NODE_TEST_DB


def test_an_explicit_database_name_wins():
    assert resolve_db_name({"FITSYNC_TEST_DB_NAME": "fitsync_test"}) == "fitsync_test"


def test_a_blank_database_name_falls_back_to_the_default():
    assert resolve_db_name({"FITSYNC_TEST_DB_NAME": "  "}) == resolve_db_name({})


def test_the_real_database_is_refused_as_a_test_target():
    # The catalogue fixture INSERTs and DELETEs. Aimed at `fitsync` it would
    # write fixture exercises into the live catalogue.
    assert is_disposable("fitsync") is False


def test_a_test_database_is_accepted():
    assert is_disposable(resolve_db_name({})) is True
    assert is_disposable("fitsync_test") is True
