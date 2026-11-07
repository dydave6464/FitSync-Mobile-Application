-- Admin dashboard (spec 2026-11-07, §6): an anonymous copy of each paid Pro
-- payment -- plan, amount, method and the Manila day only; no user, no
-- PayMongo reference -- so revenue totals survive account deletion.
-- payment_id is a plain column on purpose: no foreign key, so the copy
-- outlives the pro_payments row ON DELETE CASCADE removes with the user.
-- POLICY EXCEPTION (MIGRATIONS.md): the INSERT backfills payments already
-- paid. INSERT IGNORE on the primary key makes a replay add nothing, and
-- the SET makes DATE() the Manila day whatever zone the runner's
-- connection has.
CREATE TABLE IF NOT EXISTS revenue_payments (
  payment_id INT NOT NULL PRIMARY KEY,
  plan       ENUM('monthly','annual') NOT NULL,
  amount_php DECIMAL(10,2) NOT NULL,
  method     VARCHAR(20) NULL,
  paid_on    DATE NOT NULL,
  INDEX idx_revenue_payments_paid_on (paid_on)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET time_zone = '+08:00';

INSERT IGNORE INTO revenue_payments (payment_id, plan, amount_php, method, paid_on)
SELECT payment_id, plan, amount_php, method, DATE(paid_at)
  FROM pro_payments
 WHERE status = 'paid' AND paid_at IS NOT NULL;
