CREATE TABLE IF NOT EXISTS fixture_widgets (
  widget_id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(255) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fixture_gadgets (
  gadget_id INT AUTO_INCREMENT PRIMARY KEY,
  widget_id INT NOT NULL,
  CONSTRAINT fk_fixture_gadget_widget FOREIGN KEY (widget_id)
    REFERENCES fixture_widgets(widget_id) ON DELETE CASCADE,
  INDEX idx_fixture_gadget_widget (widget_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
