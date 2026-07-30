-- D1: materialized two-dimensional predicate memberships
--
-- This script creates the schema, membership functions, and insert/update
-- triggers for design D1. Example data are provided separately in
-- example_data.sql.
--
-- Run this script inside an empty MariaDB database.

CREATE TABLE dim_domain (
    did INT NOT NULL,
    domain_name VARCHAR(25) NOT NULL,
    domain_min FLOAT NOT NULL,
    domain_max FLOAT NOT NULL,
    PRIMARY KEY (did),
    UNIQUE (domain_name),
    CONSTRAINT chk_dim_domain_bounds CHECK (domain_min < domain_max)
) ENGINE = InnoDB;

CREATE TABLE pred_segment (
    psid INT NOT NULL,
    did INT NOT NULL,
    segment_name VARCHAR(25) NOT NULL,
    segment_min FLOAT NOT NULL,
    segment_max FLOAT NOT NULL,
    alpha FLOAT NOT NULL,
    beta FLOAT NOT NULL,
    PRIMARY KEY (psid),
    UNIQUE (did, segment_name),
    CONSTRAINT fk_pred_segment_domain FOREIGN KEY (did) REFERENCES dim_domain (did),
    CONSTRAINT chk_pred_segment_bounds CHECK (segment_min < segment_max),
    CONSTRAINT chk_pred_segment_alpha CHECK (alpha > 0 AND alpha <= 1),
    CONSTRAINT chk_pred_segment_beta CHECK (beta >= 1)
) ENGINE = InnoDB;

CREATE TABLE point (
    pid INT NOT NULL,
    point_name VARCHAR(25) NOT NULL,
    position_x FLOAT NOT NULL,
    position_y FLOAT NOT NULL,
    PRIMARY KEY (pid),
    UNIQUE (point_name)
) ENGINE = InnoDB;

CREATE TABLE predicate_2d (
    pred_x INT NOT NULL,
    pred_y INT NOT NULL,
    pred_name VARCHAR(25) NOT NULL,
    PRIMARY KEY (pred_x, pred_y),
    UNIQUE (pred_name),
    CONSTRAINT fk_predicate_2d_x FOREIGN KEY (pred_x) REFERENCES pred_segment (psid),
    CONSTRAINT fk_predicate_2d_y FOREIGN KEY (pred_y) REFERENCES pred_segment (psid)
) ENGINE = InnoDB;

CREATE TABLE predicate_sat (
    pid INT NOT NULL,
    pred_x INT NOT NULL,
    pred_y INT NOT NULL,
    mu FLOAT NOT NULL,
    PRIMARY KEY (pid, pred_x, pred_y),
    CONSTRAINT fk_predicate_sat_point
        FOREIGN KEY (pid) REFERENCES point (pid) ON DELETE CASCADE,
    CONSTRAINT fk_predicate_sat_predicate
        FOREIGN KEY (pred_x, pred_y) REFERENCES predicate_2d (pred_x, pred_y),
    CONSTRAINT chk_predicate_sat_mu CHECK (mu > 0 AND mu <= 1)
) ENGINE = InnoDB;

CREATE VIEW pred_detailed_v AS
SELECT
    ps.psid,
    dd.domain_min,
    dd.domain_max,
    ps.segment_min,
    ps.segment_max,
    ps.alpha,
    ps.beta
FROM dim_domain AS dd
JOIN pred_segment AS ps
    ON dd.did = ps.did;

DELIMITER //

CREATE FUNCTION membmid (
    x FLOAT,
    seg_left FLOAT,
    seg_right FLOAT,
    alpha FLOAT,
    beta FLOAT
)
RETURNS FLOAT
DETERMINISTIC
NO SQL
BEGIN
    DECLARE rd FLOAT;

    SET rd = ABS(2 * x - seg_right - seg_left)
             / (seg_right - seg_left);

    IF rd <= alpha THEN
        RETURN 1.0;
    ELSEIF rd <= beta THEN
        RETURN (beta - rd) / (beta - alpha);
    ELSE
        RETURN 0.0;
    END IF;
END//

CREATE FUNCTION membleft (
    x FLOAT,
    seg_left FLOAT,
    seg_right FLOAT,
    alpha FLOAT,
    beta FLOAT
)
RETURNS FLOAT
DETERMINISTIC
NO SQL
BEGIN
    DECLARE rd FLOAT;

    SET rd = (2 * x - seg_right - seg_left)
             / (seg_right - seg_left);

    IF rd <= -beta THEN
        RETURN 0.0;
    ELSEIF rd <= alpha THEN
        RETURN 1.0;
    ELSEIF rd <= beta THEN
        RETURN (beta - rd) / (beta - alpha);
    ELSE
        RETURN 0.0;
    END IF;
END//

CREATE FUNCTION membright (
    x FLOAT,
    seg_left FLOAT,
    seg_right FLOAT,
    alpha FLOAT,
    beta FLOAT
)
RETURNS FLOAT
DETERMINISTIC
NO SQL
BEGIN
    DECLARE midpoint FLOAT;
    DECLARE interval_length FLOAT;
    DECLARE alpha_boundary_left FLOAT;
    DECLARE beta_boundary_left FLOAT;

    SET midpoint = (seg_right + seg_left) / 2;
    SET interval_length = seg_right - seg_left;
    SET alpha_boundary_left = midpoint - (alpha * interval_length) / 2;
    SET beta_boundary_left = midpoint - (beta * interval_length) / 2;

    IF x >= alpha_boundary_left THEN
        RETURN 1.0;
    ELSEIF x >= beta_boundary_left THEN
        RETURN (
            2 * x - 2 * midpoint + beta * interval_length
        ) / (
            (beta - alpha) * interval_length
        );
    ELSE
        RETURN 0.0;
    END IF;
END//

CREATE FUNCTION membership_1d (
    x FLOAT,
    domain_min FLOAT,
    domain_max FLOAT,
    segment_min FLOAT,
    segment_max FLOAT,
    alpha FLOAT,
    beta FLOAT
)
RETURNS FLOAT
DETERMINISTIC
NO SQL
BEGIN
    IF x < domain_min OR x > domain_max THEN
        RETURN 0.0;
    END IF;

    IF segment_min = domain_min THEN
        RETURN membleft(x, segment_min, segment_max, alpha, beta);
    ELSEIF segment_max = domain_max THEN
        RETURN membright(x, segment_min, segment_max, alpha, beta);
    ELSE
        RETURN membmid(x, segment_min, segment_max, alpha, beta);
    END IF;
END//

CREATE FUNCTION predicate_sat (
    pos_x FLOAT,
    pos_y FLOAT,
    domain_min_x FLOAT,
    domain_max_x FLOAT,
    domain_min_y FLOAT,
    domain_max_y FLOAT,
    segment_min_x FLOAT,
    segment_max_x FLOAT,
    segment_min_y FLOAT,
    segment_max_y FLOAT,
    alpha_x FLOAT,
    beta_x FLOAT,
    alpha_y FLOAT,
    beta_y FLOAT
)
RETURNS FLOAT
DETERMINISTIC
NO SQL
BEGIN
    DECLARE memb_x FLOAT;
    DECLARE memb_y FLOAT;

    SET memb_x = membership_1d(
        pos_x, domain_min_x, domain_max_x,
        segment_min_x, segment_max_x, alpha_x, beta_x
    );

    SET memb_y = membership_1d(
        pos_y, domain_min_y, domain_max_y,
        segment_min_y, segment_max_y, alpha_y, beta_y
    );

    RETURN memb_x * memb_y;
END//

CREATE TRIGGER after_point_insert
AFTER INSERT ON point
FOR EACH ROW
BEGIN
    INSERT INTO predicate_sat (pid, pred_x, pred_y, mu)
    SELECT
        NEW.pid,
        membership_values.pred_x,
        membership_values.pred_y,
        membership_values.mu
    FROM (
        SELECT
            p.pred_x,
            p.pred_y,
            predicate_sat(
                NEW.position_x,
                NEW.position_y,
                pdx.domain_min,
                pdx.domain_max,
                pdy.domain_min,
                pdy.domain_max,
                pdx.segment_min,
                pdx.segment_max,
                pdy.segment_min,
                pdy.segment_max,
                pdx.alpha,
                pdx.beta,
                pdy.alpha,
                pdy.beta
            ) AS mu
        FROM predicate_2d AS p
        JOIN pred_detailed_v AS pdx
            ON p.pred_x = pdx.psid
        JOIN pred_detailed_v AS pdy
            ON p.pred_y = pdy.psid
        WHERE NEW.position_x BETWEEN pdx.domain_min AND pdx.domain_max
          AND NEW.position_y BETWEEN pdy.domain_min AND pdy.domain_max
    ) AS membership_values
    WHERE membership_values.mu > 0;
END//

CREATE TRIGGER after_point_update
AFTER UPDATE ON point
FOR EACH ROW
BEGIN
    IF NOT (NEW.position_x <=> OLD.position_x)
       OR NOT (NEW.position_y <=> OLD.position_y) THEN

        DELETE FROM predicate_sat
        WHERE pid = OLD.pid;

        INSERT INTO predicate_sat (pid, pred_x, pred_y, mu)
        SELECT
            NEW.pid,
            membership_values.pred_x,
            membership_values.pred_y,
            membership_values.mu
        FROM (
            SELECT
                p.pred_x,
                p.pred_y,
                predicate_sat(
                    NEW.position_x,
                    NEW.position_y,
                    pdx.domain_min,
                    pdx.domain_max,
                    pdy.domain_min,
                    pdy.domain_max,
                    pdx.segment_min,
                    pdx.segment_max,
                    pdy.segment_min,
                    pdy.segment_max,
                    pdx.alpha,
                    pdx.beta,
                    pdy.alpha,
                    pdy.beta
                ) AS mu
            FROM predicate_2d AS p
            JOIN pred_detailed_v AS pdx
                ON p.pred_x = pdx.psid
            JOIN pred_detailed_v AS pdy
                ON p.pred_y = pdy.psid
            WHERE NEW.position_x BETWEEN pdx.domain_min AND pdx.domain_max
              AND NEW.position_y BETWEEN pdy.domain_min AND pdy.domain_max
        ) AS membership_values
        WHERE membership_values.mu > 0;
    END IF;
END//

DELIMITER ;
