'use strict';
const { createAdminAccount } = require('../../src/db/admins');
const { signAdminToken } = require('../../src/lib/admin-tokens');

// The JWT config buildTestApp (helpers/test-app.js) runs with by default.
const TEST_JWT = { secret: 'test-secret-value-at-least-32-chars', expiresIn: '30d' };

/// Creates an admin the way `npm run admin:create` does and signs them an
/// admin token the test app accepts. `auth` goes straight into `.set(auth)`.
async function createTestAdmin(pool, {
  email = 'admin@fitsync.test', fullName = 'Ada Admin', password = 'admin-pass-123',
} = {}) {
  const { adminId } = await createAdminAccount(pool, { email, fullName, password });
  const token = signAdminToken(adminId, TEST_JWT);
  return { adminId, token, auth: { Authorization: `Bearer ${token}` } };
}

module.exports = { createTestAdmin, TEST_JWT };
