'use strict';

// Delete-then-insert against the computed set, rather than a plain upsert, so
// that editing a classifier removes the rows it no longer produces. Rows with
// is_manual = 1 are a human's judgement: the DELETE skips them, and callers
// must also filter them out of `computed` so no INSERT collides with one.
//
// Deletes run before inserts. A row whose value changed therefore leaves and
// returns cleanly even when the table's primary key is a single column.
async function reconcile(pool, table, keyColumns, computed, existing) {
  const keyOf = (row) => keyColumns.map((c) => row[c]).join(' ');
  const wanted = new Map(computed.map((r) => [keyOf(r), r]));
  const have = new Map(existing.map((r) => [keyOf(r), r]));

  let removed = 0;
  for (const [key, row] of have) {
    if (wanted.has(key)) continue;
    await pool.query(
      `DELETE FROM ${table} WHERE ${keyColumns.map((c) => `${c} = ?`).join(' AND ')}
        AND is_manual = 0`,
      keyColumns.map((c) => row[c]),
    );
    removed += 1;
  }

  let inserted = 0;
  for (const [key, row] of wanted) {
    if (have.has(key)) continue;
    const columns = Object.keys(row);
    await pool.query(
      `INSERT INTO ${table} (${columns.join(', ')})
       VALUES (${columns.map(() => '?').join(', ')})`,
      columns.map((c) => row[c]),
    );
    inserted += 1;
  }

  return { inserted, removed };
}

module.exports = { reconcile };
