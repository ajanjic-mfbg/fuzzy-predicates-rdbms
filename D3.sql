-- D3: direct calculation of two-dimensional predicate memberships
--
-- This script creates the tables, helper view and membership functions used by
-- design D3. It does not create a table or view containing predicate satisfaction
-- degrees. Queries obtain the required predicate parameters and call the
-- two-dimensional membership function directly.
--
-- The helper view pred_detailed_v contains only predicate and domain definitions;
-- it does not contain membership degrees.
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
-- Two-dimensional membership function
-- -----------------------------------------------------------------------------

-- Calculates a two-dimensional membership as the product of the two one-dimensional memberships.
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
        pos_x,
        domain_min_x,
        domain_max_x,
        segment_min_x,
        segment_max_x,
        alpha_x,
        beta_x
    );

    SET memb_y = membership_1d(
        pos_y,
        domain_min_y,
        domain_max_y,
        segment_min_y,
        segment_max_y,
        alpha_y,
        beta_y
    );

    RETURN memb_x * memb_y;
END//

DELIMITER ;
