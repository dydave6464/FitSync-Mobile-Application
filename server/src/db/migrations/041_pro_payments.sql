-- Buying Pro (spec 2026-10-26-pro-payments-design): one row per payment
-- attempt through PayMongo's hosted checkout (test mode). A paid row points
-- at the subscriptions row (migration 001) for the period it bought; an
-- attempt never paid -- failed or abandoned on PayMongo's page -- simply
-- stays pending. No card or wallet detail is stored: PayMongo keeps those.
-- New table only (MIGRATIONS.md: no ALTER).
CREATE TABLE IF NOT EXISTS pro_payments (
  payment_id          INT AUTO_INCREMENT PRIMARY KEY,
  user_id             INT NOT NULL,
  plan                ENUM('monthly','annual') NOT NULL,
  amount_php          DECIMAL(10,2) NOT NULL,
  checkout_session_id VARCHAR(64) NULL,
  status              ENUM('pending','paid') NOT NULL DEFAULT 'pending',
  method              VARCHAR(20) NULL,
  subscription_id     INT NULL,
  created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  paid_at             TIMESTAMP NULL DEFAULT NULL,
  CONSTRAINT fk_pro_payments_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_pro_payments_subscription FOREIGN KEY (subscription_id) REFERENCES subscriptions(subscription_id) ON DELETE SET NULL,
  UNIQUE KEY uq_pro_payments_session (checkout_session_id),
  INDEX idx_pro_payments_user (user_id),
  INDEX idx_pro_payments_subscription (subscription_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
