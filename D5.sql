-- D5: function-based view for two-dimensional predicate memberships
--
-- This script creates the tables, membership functions and the predicate_sat
-- view used by design D5. No membership degrees are stored and no triggers are
-- used. The function compute_memb_1d obtains the definition of a predicate
-- segment from the database, while compute_memb_2d calls it for both dimensions
-- and combines the returned values. The predicate_sat view calls
-- compute_memb_2d for the point--predicate pairs.
--
-- The example data are stored in example_data.sql. Run this script first and
-- then execute example_data.sql in the same MariaDB database.

-- -----------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------

-- Contains the numerical domains used by predicate dimensions.
CREATE TABLE dim_domain (
    did INT NOT NULL,
    domain_name VARCHAR(25) NOT NULL,
    domain_min FLOAT NOT NULL,
    domain_max FLOAT NOT NULL,
    PRIMARY KEY (did),
    UNIQUE (domain_name),
    CONSTRAINT chk_dim_domain_bounds
        CHECK (domain_min < domain_max)
) ENGINE = InnoDB;

-- Contains one-dimensional predicate segments and their membership-function parameters.
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
    CONSTRAINT fk_pred_segment_domain
        FOREIGN KEY (did) REFERENCES dim_domain (did),
    CONSTRAINT chk_pred_segment_bounds
        CHECK (segment_min < segment_max),
    CONSTRAINT chk_pred_segment_alpha
        CHECK (alpha > 0 AND alpha <= 1),
    CONSTRAINT chk_pred_segment_beta
        CHECK (beta >= 1)
) ENGINE = InnoDB;

-- Contains the points evaluated by the predicates.
CREATE TABLE point (
    pid INT NOT NULL,
    point_name VARCHAR(25) NOT NULL,
    position_x FLOAT NOT NULL,
    position_y FLOAT NOT NULL,
    PRIMARY KEY (pid),
    UNIQUE (point_name)
) ENGINE = InnoDB;

-- Defines each two-dimensional predicate as a pair of one-dimensional predicate segments.
CREATE TABLE predicate_2d (
    pred_x INT NOT NULL,
    pred_y INT NOT NULL,
    pred_name VARCHAR(25) NOT NULL,
    PRIMARY KEY (pred_x, pred_y),
    UNIQUE (pred_name),
    CONSTRAINT fk_predicate_2d_x
        FOREIGN KEY (pred_x) REFERENCES pred_segment (psid),
    CONSTRAINT fk_predicate_2d_y
        FOREIGN KEY (pred_y) REFERENCES pred_segment (psid)
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------
-- View with segment and domain details
-- -----------------------------------------------------------------------------

-- Combines each predicate segment with the bounds of its dimension domain.
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

-- -----------------------------------------------------------------------------
-- One-dimensional membership functions
-- -----------------------------------------------------------------------------

DELIMITER //

-- Calculates membership in an interior predicate segment.
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

-- Calculates membership in a segment at the left boundary of a domain.
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

-- Calculates membership in a segment at the right boundary of a domain.
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

-- Calls the appropriate one-dimensional membership function for the given segment.
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
    -- Membership is zero outside the declared domain.
    IF x < domain_min OR x > domain_max THEN
        RETURN 0.0;
    END IF;

    IF segment_min = domain_min THEN
        RETURN membleft(
            x,
            segment_min,
            segment_max,
            alpha,
            beta
        );
    ELSEIF segment_max = domain_max THEN
        RETURN membright(
            x,
            segment_min,
            segment_max,
            alpha,
            beta
        );
    ELSE
        RETURN membmid(
            x,
            segment_min,
            segment_max,
            alpha,
            beta
        );
    END IF;
END//

-- -----------------------------------------------------------------------------
-- Membership functions that read predicate definitions from the database
-- -----------------------------------------------------------------------------

-- Obtains the definition of a predicate segment and calculates the membership
-- of the supplied coordinate. If the coordinate is outside the domain or the
-- segment support, the SELECT returns no row and the function returns zero.
CREATE FUNCTION compute_memb_1d (
    p_position FLOAT,
    p_pred_segment_id INT
)
RETURNS FLOAT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_domain_min FLOAT DEFAULT NULL;
    DECLARE v_domain_max FLOAT DEFAULT NULL;
    DECLARE v_segment_min FLOAT DEFAULT NULL;
    DECLARE v_segment_max FLOAT DEFAULT NULL;
    DECLARE v_alpha FLOAT DEFAULT NULL;
    DECLARE v_beta FLOAT DEFAULT NULL;
    DECLARE v_found BOOLEAN DEFAULT TRUE;

    DECLARE CONTINUE HANDLER FOR NOT FOUND
        SET v_found = FALSE;

    SELECT
        pd.domain_min,
        pd.domain_max,
        pd.segment_min,
        pd.segment_max,
        pd.alpha,
        pd.beta
    INTO
        v_domain_min,
        v_domain_max,
        v_segment_min,
        v_segment_max,
        v_alpha,
        v_beta
    FROM pred_detailed_v AS pd
    WHERE pd.psid = p_pred_segment_id

      -- The coordinate must lie inside the declared dimension domain.
      AND p_position BETWEEN pd.domain_min AND pd.domain_max

      -- The coordinate must lie inside the support of the predicate segment.
      AND p_position >
          (pd.segment_min + pd.segment_max) / 2
          - pd.beta * (pd.segment_max - pd.segment_min) / 2
      AND p_position <
          (pd.segment_min + pd.segment_max) / 2
          + pd.beta * (pd.segment_max - pd.segment_min) / 2;

    IF NOT v_found THEN
        RETURN 0.0;
    END IF;

    RETURN membership_1d(
        p_position,
        v_domain_min,
        v_domain_max,
        v_segment_min,
        v_segment_max,
        v_alpha,
        v_beta
    );
END//

-- Calls compute_memb_1d for both dimensions and multiplies the returned values.
CREATE FUNCTION compute_memb_2d (
    p_pos_x FLOAT,
    p_pos_y FLOAT,
    p_pred_x INT,
    p_pred_y INT
)
RETURNS FLOAT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_memb_x FLOAT DEFAULT 0.0;
    DECLARE v_memb_y FLOAT DEFAULT 0.0;

    SET v_memb_x = compute_memb_1d(
        p_pos_x,
        p_pred_x
    );

    SET v_memb_y = compute_memb_1d(
        p_pos_y,
        p_pred_y
    );

    RETURN v_memb_x * v_memb_y;
END//

DELIMITER ;

-- -----------------------------------------------------------------------------
-- View with two-dimensional predicate memberships
-- -----------------------------------------------------------------------------

-- Calls compute_memb_2d for every point--predicate pair and removes the rows
-- whose membership is zero.
CREATE VIEW predicate_sat AS
WITH memb_2d AS (
    SELECT
        pt.pid,
        p.pred_x,
        p.pred_y,
        compute_memb_2d(
            pt.position_x,
            pt.position_y,
            p.pred_x,
            p.pred_y
        ) AS mu
    FROM point AS pt
    CROSS JOIN predicate_2d AS p
)
SELECT
    pid,
    pred_x,
    pred_y,
    mu
FROM memb_2d
WHERE mu > 0;
