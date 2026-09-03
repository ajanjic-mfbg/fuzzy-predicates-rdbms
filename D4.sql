-- D4: stored one-dimensional memberships with a two-dimensional view
--
-- This script creates the tables, membership functions and triggers used by
-- design D4. The nonzero one-dimensional memberships are stored separately for
-- the x- and y-coordinates. The predicate_sat view combines these stored values
-- to calculate the two-dimensional memberships when they are needed.
--
-- Predicate definitions should normally be inserted before the points. If a
-- predicate segment is changed later, the stored one-dimensional memberships
-- have to be recalculated.
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

-- Contains the nonzero memberships of x-coordinates in x-axis predicate segments.
CREATE TABLE point_memb_x (
    pid INT NOT NULL,
    psid INT NOT NULL,
    mu FLOAT NOT NULL,
    PRIMARY KEY (pid, psid),
    INDEX idx_point_memb_x_segment (psid, pid),
    CONSTRAINT fk_point_memb_x_point
        FOREIGN KEY (pid) REFERENCES point (pid)
        ON DELETE CASCADE,
    CONSTRAINT fk_point_memb_x_segment
        FOREIGN KEY (psid) REFERENCES pred_segment (psid),
    CONSTRAINT chk_point_memb_x_mu
        CHECK (mu > 0 AND mu <= 1)
) ENGINE = InnoDB;

-- Contains the nonzero memberships of y-coordinates in y-axis predicate segments.
CREATE TABLE point_memb_y (
    pid INT NOT NULL,
    psid INT NOT NULL,
    mu FLOAT NOT NULL,
    PRIMARY KEY (pid, psid),
    INDEX idx_point_memb_y_segment (psid, pid),
    CONSTRAINT fk_point_memb_y_point
        FOREIGN KEY (pid) REFERENCES point (pid)
        ON DELETE CASCADE,
    CONSTRAINT fk_point_memb_y_segment
        FOREIGN KEY (psid) REFERENCES pred_segment (psid),
    CONSTRAINT chk_point_memb_y_mu
        CHECK (mu > 0 AND mu <= 1)
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

DELIMITER ;

-- -----------------------------------------------------------------------------
-- View with two-dimensional predicate memberships
-- -----------------------------------------------------------------------------

-- Combines the stored x- and y-memberships and calculates their product.
-- Since only positive one-dimensional memberships are stored, all rows returned
-- by this join also have a positive two-dimensional membership.
CREATE VIEW predicate_sat AS
SELECT
    mx.pid,
    p.pred_x,
    p.pred_y,
    mx.mu * my.mu AS mu
FROM predicate_2d AS p
JOIN point_memb_x AS mx
    ON mx.psid = p.pred_x
JOIN point_memb_y AS my
    ON my.pid = mx.pid
   AND my.psid = p.pred_y;

-- -----------------------------------------------------------------------------
-- Triggers for the one-dimensional membership tables
-- -----------------------------------------------------------------------------

DELIMITER //

-- Calculates and stores the nonzero one-dimensional memberships of a newly
-- inserted point. The same trigger updates both membership tables.
CREATE TRIGGER after_point_insert
AFTER INSERT ON point
FOR EACH ROW
BEGIN
    INSERT INTO point_memb_x (pid, psid, mu)
    SELECT
        NEW.pid,
        membership_values.psid,
        membership_values.mu
    FROM (
        SELECT
            pd.psid,
            membership_1d(
                NEW.position_x,
                pd.domain_min,
                pd.domain_max,
                pd.segment_min,
                pd.segment_max,
                pd.alpha,
                pd.beta
            ) AS mu
        FROM pred_detailed_v AS pd
        WHERE EXISTS (
            SELECT 1
            FROM predicate_2d AS p
            WHERE p.pred_x = pd.psid
        )
          AND NEW.position_x BETWEEN pd.domain_min AND pd.domain_max
          AND NEW.position_x >
              (pd.segment_min + pd.segment_max) / 2
              - pd.beta * (pd.segment_max - pd.segment_min) / 2
          AND NEW.position_x <
              (pd.segment_min + pd.segment_max) / 2
              + pd.beta * (pd.segment_max - pd.segment_min) / 2
    ) AS membership_values
    WHERE membership_values.mu > 0;

    INSERT INTO point_memb_y (pid, psid, mu)
    SELECT
        NEW.pid,
        membership_values.psid,
        membership_values.mu
    FROM (
        SELECT
            pd.psid,
            membership_1d(
                NEW.position_y,
                pd.domain_min,
                pd.domain_max,
                pd.segment_min,
                pd.segment_max,
                pd.alpha,
                pd.beta
            ) AS mu
        FROM pred_detailed_v AS pd
        WHERE EXISTS (
            SELECT 1
            FROM predicate_2d AS p
            WHERE p.pred_y = pd.psid
        )
          AND NEW.position_y BETWEEN pd.domain_min AND pd.domain_max
          AND NEW.position_y >
              (pd.segment_min + pd.segment_max) / 2
              - pd.beta * (pd.segment_max - pd.segment_min) / 2
          AND NEW.position_y <
              (pd.segment_min + pd.segment_max) / 2
              + pd.beta * (pd.segment_max - pd.segment_min) / 2
    ) AS membership_values
    WHERE membership_values.mu > 0;
END//

-- Recalculates the one-dimensional memberships affected by a coordinate change.
-- If only one coordinate changes, only the corresponding table is rebuilt.
CREATE TRIGGER after_point_update
AFTER UPDATE ON point
FOR EACH ROW
BEGIN
    IF NOT (NEW.position_x <=> OLD.position_x) THEN
        DELETE FROM point_memb_x
        WHERE pid = OLD.pid;

        INSERT INTO point_memb_x (pid, psid, mu)
        SELECT
            NEW.pid,
            membership_values.psid,
            membership_values.mu
        FROM (
            SELECT
                pd.psid,
                membership_1d(
                    NEW.position_x,
                    pd.domain_min,
                    pd.domain_max,
                    pd.segment_min,
                    pd.segment_max,
                    pd.alpha,
                    pd.beta
                ) AS mu
            FROM pred_detailed_v AS pd
            WHERE EXISTS (
                SELECT 1
                FROM predicate_2d AS p
                WHERE p.pred_x = pd.psid
            )
              AND NEW.position_x BETWEEN pd.domain_min AND pd.domain_max
              AND NEW.position_x >
                  (pd.segment_min + pd.segment_max) / 2
                  - pd.beta * (pd.segment_max - pd.segment_min) / 2
              AND NEW.position_x <
                  (pd.segment_min + pd.segment_max) / 2
                  + pd.beta * (pd.segment_max - pd.segment_min) / 2
        ) AS membership_values
        WHERE membership_values.mu > 0;
    END IF;

    IF NOT (NEW.position_y <=> OLD.position_y) THEN
        DELETE FROM point_memb_y
        WHERE pid = OLD.pid;

        INSERT INTO point_memb_y (pid, psid, mu)
        SELECT
            NEW.pid,
            membership_values.psid,
            membership_values.mu
        FROM (
            SELECT
                pd.psid,
                membership_1d(
                    NEW.position_y,
                    pd.domain_min,
                    pd.domain_max,
                    pd.segment_min,
                    pd.segment_max,
                    pd.alpha,
                    pd.beta
                ) AS mu
            FROM pred_detailed_v AS pd
            WHERE EXISTS (
                SELECT 1
                FROM predicate_2d AS p
                WHERE p.pred_y = pd.psid
            )
              AND NEW.position_y BETWEEN pd.domain_min AND pd.domain_max
              AND NEW.position_y >
                  (pd.segment_min + pd.segment_max) / 2
                  - pd.beta * (pd.segment_max - pd.segment_min) / 2
              AND NEW.position_y <
                  (pd.segment_min + pd.segment_max) / 2
                  + pd.beta * (pd.segment_max - pd.segment_min) / 2
        ) AS membership_values
        WHERE membership_values.mu > 0;
    END IF;
END//

DELIMITER ;
