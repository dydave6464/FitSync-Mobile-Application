-- What decided each injury-risk estimate, kept beside the estimate itself so
-- the Recovery tab can say why a level was given rather than only which one.
--
-- source: 'model' when the scikit-learn model's score decided the estimate,
-- 'rules' when the rules' safety floor did or no model was loaded. The model
-- is trained on simulated data built from published injury risk factors, not
-- on real outcomes, so the column records which path answered, not how sure
-- anyone should be of it.
--
-- model_version: the model's version string, NULL when the rules answered
-- without a model.
--
-- load_pct: the training-load index the estimate saw (percent above the
-- usual week, 0-130), so the explanation quotes the number that was scored
-- rather than one recomputed later from a week that has since moved on.
--
-- drivers: up to three {key, value} pairs, most influential first. An empty
-- array means nothing stood out. NULL means the estimate predates this
-- migration (every column here is NULL then) or came from a service that
-- sent a source but no drivers; GET reads both as [] and `source` tells the
-- two apart.
ALTER TABLE injury_risk_estimates
  ADD COLUMN source ENUM('model','rules') NULL AFTER training_load_score,
  ADD COLUMN model_version VARCHAR(40) NULL AFTER source,
  ADD COLUMN load_pct DECIMAL(5,2) NULL AFTER model_version,
  ADD COLUMN drivers JSON NULL AFTER load_pct;
