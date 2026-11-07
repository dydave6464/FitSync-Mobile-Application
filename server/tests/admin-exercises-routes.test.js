'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const { migrate } = require('../src/db/migrate');
const { createPool } = require('../src/db/pool');
const { buildTestApp } = require('./helpers/test-app');
const { testDbConfig, dropAllTables } = require('./helpers/test-db');
const { createTestAdmin, TEST_JWT } = require('./helpers/admin');
const { signToken } = require('../src/lib/tokens');
const { REGIONS, classifyContraindications } = require('../src/db/classify-contraindications');
const { classifyCategory } = require('../src/db/classify-categories');
const { classifyRequirements } = require('../src/db/classify-requirements');

const ROW_KEYS = [
  'animationUrl', 'equipment', 'id', 'muscleGroup', 'name', 'pendingReason', 'status', 'thumbnailUrl',
];

// Stands in for the storage driver: the database keeps keys, callers get URLs.
const storage = { url: (key) => `https://cdn.test/${key}` };

test('admin exercises endpoints', async (t) => {
  const pool = createPool(testDbConfig());
  await dropAllTables(pool);
  await migrate(testDbConfig());
  const app = buildTestApp({ pool, storage });
  t.after(async () => { await dropAllTables(pool); await pool.end(); });

  const { auth, adminId } = await createTestAdmin(pool);
  const get = (path) => request(app).get(`/api/v1/admin${path}`).set(auth);
  const post = (path) => request(app).post(`/api/v1/admin${path}`).set(auth);
  const list = async (query) => (await get(`/exercises${query}`).expect(200)).body.data;

  // The curated equipment the classifiers name, plus the catalogue tags used
  // below ('stationary bike' is in NICHE_EQUIPMENT).
  const equipmentIds = {};
  for (const name of ['bench', 'pull-up bar', 'machines', 'barbell', 'body weight', 'stationary bike']) {
    const [r] = await pool.query('INSERT INTO equipment (name) VALUES (?)', [name]);
    equipmentIds[name] = r.insertId;
  }
  // The 16 injury regions, as seed-injuries.js creates them.
  const injuryIds = {};
  for (const name of REGIONS) {
    const [r] = await pool.query(
      "INSERT INTO injuries (name, is_lateral, region_group) VALUES (?, 0, 'back_core')", [name],
    );
    injuryIds[name] = r.insertId;
  }

  let sourceNo = 0;
  const addExercise = async (name, muscleGroup, bodyPart, equipment, status) => {
    sourceNo += 1;
    const sourceId = String(sourceNo).padStart(4, '0');
    const [r] = await pool.query(
      `INSERT INTO exercises (source_id, name, muscle_group, body_part, equipment_id, animation_url, thumbnail_url, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      [sourceId, name, muscleGroup, bodyPart, equipmentIds[equipment], `exercises/${sourceId}/animation.gif`,
        `exercises/${sourceId}/thumb.jpg`, status],
    );
    return { id: r.insertId, sourceId };
  };

  const jumpingJack = await addExercise('jumping jack', 'cardiovascular system', 'cardio', 'body weight', 'pending');
  const bike = await addExercise('stationary bike walk', 'quads', 'upper legs', 'stationary bike', 'pending');
  const incline = await addExercise('incline bench press', 'pectorals', 'chest', 'barbell', 'pending');
  const curl = await addExercise('barbell curl', 'biceps', 'upper arms', 'barbell', 'live');
  const pushUp = await addExercise('push-up', 'pectorals', 'chest', 'body weight', 'live');

  const [trainee] = await pool.query(
    "INSERT INTO users (email, password_hash, full_name) VALUES ('t@example.com', 'x', 'T')",
  );
  const traineeId = trainee.insertId;
  const traineeAuth = { Authorization: `Bearer ${signToken(traineeId, TEST_JWT)}` };

  await t.test('a trainee token is refused', async () => {
    const res = await request(app).get('/api/v1/admin/exercises?status=pending')
      .set(traineeAuth).expect(401);
    assert.equal(res.body.error.code, 'UNAUTHENTICATED');
  });

  await t.test('status=pending lists only pending exercises, by name, with both counts', async () => {
    const data = await list('?status=pending');
    assert.deepEqual(data.exercises.map((e) => e.id), [incline.id, jumpingJack.id, bike.id]);
    assert.deepEqual(data.counts, { pending: 3, live: 2 });
    assert.deepEqual([data.page, data.limit, data.total], [1, 30, 3]);
  });

  await t.test('status=live lists only live exercises; counts stay the same', async () => {
    const data = await list('?status=live');
    assert.deepEqual(data.exercises.map((e) => e.id), [curl.id, pushUp.id]);
    assert.deepEqual(data.counts, { pending: 3, live: 2 });
    assert.equal(data.total, 2);
  });

  await t.test('a row carries URLs from storage, never keys', async () => {
    const [row] = (await list('?status=live&q=curl')).exercises;
    assert.deepEqual(Object.keys(row).sort(), ROW_KEYS);
    assert.deepEqual(row, {
      id: curl.id,
      name: 'barbell curl',
      muscleGroup: 'biceps',
      equipment: 'barbell',
      thumbnailUrl: `https://cdn.test/exercises/${curl.sourceId}/thumb.jpg`,
      animationUrl: `https://cdn.test/exercises/${curl.sourceId}/animation.gif`,
      status: 'live',
      pendingReason: null,
    });
  });

  await t.test('pendingReason says why a pending exercise was held back', async () => {
    const reasons = Object.fromEntries((await list('?status=pending')).exercises.map((e) => [e.id, e.pendingReason]));
    assert.deepEqual(reasons, { [jumpingJack.id]: 'cardio', [bike.id]: 'rare_equipment', [incline.id]: null });
  });

  await t.test('q matches the name, ignoring case; total follows it', async () => {
    const data = await list('?status=pending&q=BENCH');
    assert.deepEqual(data.exercises.map((e) => e.id), [incline.id]);
    assert.equal(data.total, 1);
    assert.deepEqual(data.counts, { pending: 3, live: 2 });
    assert.deepEqual((await list('?status=pending&q=%25')).exercises, []);
  });

  await t.test('page and limit pick a slice', async () => {
    const data = await list('?status=pending&page=2&limit=2');
    assert.deepEqual(data.exercises.map((e) => e.id), [bike.id]);
    assert.deepEqual([data.page, data.limit, data.total], [2, 2, 3]);
    assert.equal((await get('/exercises?status=pending&limit=51').expect(400)).body.error.code, 'INVALID_QUERY_PARAM');
  });

  await t.test('a missing or unknown status is 400 INVALID_ADMIN_FIELD', async () => {
    for (const query of ['', '?status=', '?status=all', '?status=live&status=pending']) {
      const res = await get(`/exercises${query}`).expect(400);
      assert.equal(res.body.error.code, 'INVALID_ADMIN_FIELD', query);
      assert.deepEqual(res.body.error.details, [{ field: 'status' }], query);
    }
  });

  // Everything publishing may have written for [id], in a comparable form.
  const safetyRows = async (id) => {
    const [categories] = await pool.query(
      'SELECT category, is_manual FROM exercise_categories WHERE exercise_id = ?', [id],
    );
    const [requirements] = await pool.query(
      `SELECT LOWER(e.name) AS name, r.is_manual FROM exercise_equipment_requirements r
         JOIN equipment e ON e.equipment_id = r.equipment_id WHERE r.exercise_id = ? ORDER BY name`, [id],
    );
    const [contraindications] = await pool.query(
      `SELECT LOWER(i.name) AS region, c.pattern, c.is_manual FROM exercise_contraindications c
         JOIN injuries i ON i.injury_id = c.injury_id WHERE c.exercise_id = ? ORDER BY region`, [id],
    );
    return {
      categories: categories.map((r) => [r.category, r.is_manual]),
      requirements: requirements.map((r) => [r.name, r.is_manual]),
      contraindications: contraindications.map((r) => [r.region, r.pattern, r.is_manual]),
    };
  };
  // What the seed scripts would write for an exercise row, from the same
  // classifiers, all is_manual = 0.
  const classified = (exercise) => ({
    categories: [[classifyCategory(exercise), 0]],
    requirements: classifyRequirements(exercise).map((name) => [name.toLowerCase(), 0]).sort(),
    contraindications: classifyContraindications(exercise)
      .map((row) => [row.region.toLowerCase(), row.pattern, 0])
      .sort((a, b) => a[0].localeCompare(b[0])),
  });
  const exerciseRow = async (id) => {
    const [[row]] = await pool.query('SELECT status, reviewed_by FROM exercises WHERE exercise_id = ?', [id]);
    return row;
  };

  await t.test('Unit 17: publishing a pending exercise sets it live, reviewed by the admin', async () => {
    const res = await post(`/exercises/${incline.id}/publish`).expect(200);
    const { exercise } = res.body.data;
    assert.deepEqual(Object.keys(exercise).sort(), ROW_KEYS);
    assert.equal(exercise.id, incline.id);
    assert.equal(exercise.status, 'live');
    assert.equal(exercise.pendingReason, null);
    assert.equal(exercise.thumbnailUrl, `https://cdn.test/exercises/${incline.sourceId}/thumb.jpg`);
    assert.deepEqual(await exerciseRow(incline.id), { status: 'live', reviewed_by: adminId });
  });

  await t.test('publishing writes the rows the seed scripts would, from the same classifiers', async () => {
    const want = classified({
      name: 'incline bench press', muscle_group: 'pectorals', body_part: 'chest', equipment: 'barbell',
    });
    // Not vacuous: a bench press needs a bench and is contraindicated somewhere.
    assert.deepEqual(want.requirements, [['bench', 0]]);
    assert.ok(want.contraindications.length > 0);
    assert.deepEqual(await safetyRows(incline.id), want);

    await post(`/exercises/${jumpingJack.id}/publish`).expect(200);
    const cardio = classified({
      name: 'jumping jack', muscle_group: 'cardiovascular system', body_part: 'cardio', equipment: 'body weight',
    });
    assert.ok(cardio.contraindications.length > 0);
    assert.deepEqual(await safetyRows(jumpingJack.id), cardio);
    assert.equal((await exerciseRow(jumpingJack.id)).status, 'live');
  });

  await t.test("a human's rows are kept as they are and never duplicated", async () => {
    const decline = await addExercise('decline bench press', 'pectorals', 'chest', 'barbell', 'pending');
    await pool.query("INSERT INTO exercise_categories (exercise_id, category, is_manual) VALUES (?, 'other', 1)", [decline.id]);
    await pool.query(
      'INSERT INTO exercise_equipment_requirements (exercise_id, equipment_id, is_manual) VALUES (?, ?, 1)',
      [decline.id, equipmentIds.bench],
    );
    await pool.query(
      "INSERT INTO exercise_contraindications (exercise_id, injury_id, pattern, is_manual) VALUES (?, ?, 'by_hand', 1)",
      [decline.id, injuryIds.Shoulder],
    );
    // A machine-written category the classifier no longer agrees with is
    // brought up to date.
    const stale = await addExercise('wide bench press', 'pectorals', 'chest', 'barbell', 'pending');
    await pool.query("INSERT INTO exercise_categories (exercise_id, category, is_manual) VALUES (?, 'other', 0)", [stale.id]);

    await post(`/exercises/${decline.id}/publish`).expect(200);
    await post(`/exercises/${stale.id}/publish`).expect(200);

    const rows = await safetyRows(decline.id);
    assert.deepEqual(rows.categories, [['other', 1]]);
    assert.deepEqual(rows.requirements, [['bench', 1]]);
    const shoulder = rows.contraindications.filter(([region]) => region === 'shoulder');
    assert.deepEqual(shoulder, [['shoulder', 'by_hand', 1]]);
    // The classifier's other rows are still written beside the manual one.
    const want = classified({ name: 'decline bench press', muscle_group: 'pectorals', body_part: 'chest', equipment: 'barbell' });
    assert.ok(want.contraindications.some(([region]) => region === 'shoulder'));
    assert.equal(rows.contraindications.length, want.contraindications.length);
    assert.deepEqual((await safetyRows(stale.id)).categories, [['strength', 0]]);
  });

  await t.test('an injury region missing from the database refuses publishing and changes nothing', async () => {
    // 'walk' is a spine risk, so the classifier names Lower back and Core.
    assert.ok(classifyContraindications({ name: 'stationary bike walk', muscle_group: 'quads', body_part: 'upper legs' })
      .some((row) => row.region === 'Core'));
    await pool.query("DELETE FROM injuries WHERE name = 'Core'");
    try {
      const res = await post(`/exercises/${bike.id}/publish`).expect(409);
      assert.equal(res.body.error.code, 'EXERCISE_UNCLASSIFIABLE');
      assert.equal(
        res.body.error.message, "This exercise's safety rules couldn't be worked out, so it can't be published.",
      );
      assert.deepEqual(await exerciseRow(bike.id), { status: 'pending', reviewed_by: null });
      assert.deepEqual(await safetyRows(bike.id), { categories: [], requirements: [], contraindications: [] });
    } finally {
      const [r] = await pool.query("INSERT INTO injuries (name, is_lateral, region_group) VALUES ('Core', 0, 'back_core')");
      injuryIds.Core = r.insertId;
    }
  });

  await t.test('an equipment option missing from the database refuses publishing too', async () => {
    const hanging = await addExercise('hanging leg raise', 'abs', 'waist', 'body weight', 'pending');
    assert.deepEqual(classifyRequirements({ name: 'hanging leg raise', equipment: 'body weight' }), ['pull-up bar']);
    await pool.query("DELETE FROM equipment WHERE name = 'pull-up bar'");
    try {
      const res = await post(`/exercises/${hanging.id}/publish`).expect(409);
      assert.equal(res.body.error.code, 'EXERCISE_UNCLASSIFIABLE');
      assert.deepEqual(await exerciseRow(hanging.id), { status: 'pending', reviewed_by: null });
      assert.deepEqual(await safetyRows(hanging.id), { categories: [], requirements: [], contraindications: [] });
    } finally {
      const [r] = await pool.query("INSERT INTO equipment (name) VALUES ('pull-up bar')");
      equipmentIds['pull-up bar'] = r.insertId;
    }
  });

  await t.test('publishing a live exercise answers it unchanged', async () => {
    const res = await post(`/exercises/${curl.id}/publish`).expect(200);
    assert.equal(res.body.data.exercise.status, 'live');
    assert.deepEqual(await exerciseRow(curl.id), { status: 'live', reviewed_by: null });
    assert.deepEqual(await safetyRows(curl.id), { categories: [], requirements: [], contraindications: [] });
  });

  await t.test('an unknown exercise is 404 EXERCISE_NOT_FOUND', async () => {
    for (const id of ['999999', 'abc', '0']) {
      const res = await post(`/exercises/${id}/publish`).expect(404);
      assert.equal(res.body.error.code, 'EXERCISE_NOT_FOUND', id);
      assert.equal(res.body.error.message, 'No such exercise.');
    }
  });

  await t.test('IT-09: a published exercise appears in the trainee exercise library', async () => {
    const press = await addExercise('landmine floor press', 'pectorals', 'chest', 'barbell', 'pending');
    const search = async () => (await request(app).get('/api/v1/exercises?search=landmine')
      .set(traineeAuth).expect(200)).body.data.exercises.map((e) => e.exerciseId);
    assert.deepEqual(await search(), []);
    await post(`/exercises/${press.id}/publish`).expect(200);
    assert.deepEqual(await search(), [press.id]);
  });
});
