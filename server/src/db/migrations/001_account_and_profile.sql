CREATE TABLE IF NOT EXISTS users (
  user_id           INT AUTO_INCREMENT PRIMARY KEY,
  email             VARCHAR(255) NOT NULL,
  password_hash     VARCHAR(255) NOT NULL,
  full_name         VARCHAR(255) NOT NULL,
  sex               ENUM('male','female','prefer_not_to_say') NULL,
  date_of_birth     DATE NULL,
  height_cm         DECIMAL(6,2) NULL,
  weight_kg         DECIMAL(6,2) NULL,
  goal_weight_kg    DECIMAL(6,2) NULL,
  main_goal         ENUM('lose_weight','build_muscle','gain_strength','general_fitness') NULL,
  fitness_level     ENUM('beginner','intermediate') NULL,
  activity_level    ENUM('sedentary','light','moderate','active','very_active') NULL,
  training_location ENUM('home_gym','commercial_gym','both','other') NULL,
  city              VARCHAR(255) NULL,
  is_premium        BOOLEAN NOT NULL DEFAULT FALSE,
  created_at        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS admins (
  admin_id      INT AUTO_INCREMENT PRIMARY KEY,
  email         VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  full_name     VARCHAR(255) NOT NULL,
  created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_admins_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS goals (
  goal_id       INT AUTO_INCREMENT PRIMARY KEY,
  user_id       INT NOT NULL,
  title         VARCHAR(255) NOT NULL,
  target_value  DECIMAL(6,2) NULL,
  current_value DECIMAL(6,2) NOT NULL DEFAULT 0,
  is_completed  BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT fk_goals_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  INDEX idx_goals_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS equipment (
  equipment_id INT AUTO_INCREMENT PRIMARY KEY,
  name         VARCHAR(255) NOT NULL,
  UNIQUE KEY uq_equipment_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS user_equipment (
  user_equipment_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id           INT NOT NULL,
  equipment_id      INT NOT NULL,
  CONSTRAINT fk_user_equipment_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_user_equipment_equipment FOREIGN KEY (equipment_id) REFERENCES equipment(equipment_id) ON DELETE RESTRICT,
  UNIQUE KEY uq_user_equipment (user_id, equipment_id),
  INDEX idx_user_equipment_equipment (equipment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS injuries (
  injury_id INT AUTO_INCREMENT PRIMARY KEY,
  name      VARCHAR(255) NOT NULL,
  UNIQUE KEY uq_injuries_name (name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS user_injuries (
  user_injury_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id        INT NOT NULL,
  injury_id      INT NOT NULL,
  noted_at       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_user_injuries_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_user_injuries_injury FOREIGN KEY (injury_id) REFERENCES injuries(injury_id) ON DELETE RESTRICT,
  UNIQUE KEY uq_user_injury (user_id, injury_id),
  INDEX idx_user_injuries_injury (injury_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS subscriptions (
  subscription_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id         INT NOT NULL,
  plan            ENUM('monthly','annual') NOT NULL,
  price_php       DECIMAL(10,2) NOT NULL,
  status          ENUM('active','expired','cancelled') NOT NULL DEFAULT 'active',
  started_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at      TIMESTAMP NULL,
  CONSTRAINT fk_subscriptions_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  INDEX idx_subscriptions_user (user_id),
  INDEX idx_subscriptions_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
