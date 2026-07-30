-- Geographic-coordinate example data
--
-- Shared by D1.sql and D5.sql.
-- Run one of the design scripts first, then execute this file in the same
-- MariaDB database.

INSERT INTO dim_domain (
    did,
    domain_name,
    domain_min,
    domain_max
)
VALUES
    (11, 'ukmap_long_-2_0', -2, 0),
    (12, 'ukmap_lat_51_53', 51, 53);

INSERT INTO pred_segment (
    psid,
    did,
    segment_name,
    segment_min,
    segment_max,
    alpha,
    beta
)
VALUES
    (1, 11, 'long_west',   -2,       -4.0 / 3.0,      1.0 / 2.0, 3.0 / 2.0),
    (2, 11, 'long_middle', -4.0/3.0, -2.0 / 3.0,      1.0 / 2.0, 3.0 / 2.0),
    (3, 11, 'long_east',   -2.0/3.0,  0,              1.0 / 2.0, 3.0 / 2.0),
    (4, 12, 'lat_south',    51,       51 + 2.0 / 3.0, 1.0 / 2.0, 3.0 / 2.0),
    (5, 12, 'lat_middle',   51 + 2.0 / 3.0, 52 + 1.0 / 3.0, 1.0 / 2.0, 3.0 / 2.0),
    (6, 12, 'lat_north',    52 + 1.0 / 3.0, 53,       1.0 / 2.0, 3.0 / 2.0);

INSERT INTO predicate_2d (
    pred_x,
    pred_y,
    pred_name
)
VALUES
    (1, 4, 'south-west'),
    (1, 5, 'west'),
    (1, 6, 'north-west'),
    (2, 4, 'south'),
    (2, 5, 'center'),
    (2, 6, 'north'),
    (3, 4, 'south-east'),
    (3, 5, 'east'),
    (3, 6, 'north-east');

INSERT INTO point (
    pid,
    point_name,
    position_x,
    position_y
)
VALUES
    (1,  'Peterborough',     -0.2508, 52.5739),
    (2,  'Solihull',         -1.7782, 52.4128),
    (3,  'Oxford',           -1.2577, 51.7520),
    (4,  'London',           -0.1181, 51.5099),
    (5,  'Swindon',          -1.7722, 51.5685),
    (6,  'Northampton',      -0.9027, 52.24055),
    (7,  'Rugby',            -1.2650, 52.3709),
    (8,  'Sutton Coldfield', -1.8240, 52.5704),
    (9,  'Salisbury',        -1.7945, 51.0688),
    (10, 'Bedford',          -0.4607, 52.1364),
    (11, 'Frankton',         -1.3776, 52.3284),
    (12, 'Coventry',         -1.5197, 52.4068),
    (13, 'Slough',           -0.5950, 51.5105),
    (14, 'Esher',            -0.3659, 51.3695),
    (15, 'Epsom',            -0.2674, 51.3360),
    (16, 'Borehamwood',      -0.2723, 51.6577),
    (17, 'Crawley',          -0.1872, 51.1091),
    (18, 'St. Neots',        -0.2651, 52.2301),
    (19, 'Meriden',          -1.6478, 52.4387),
    (20, 'Nottingham',       -1.1581, 52.9548),
    (21, 'Derby',            -1.4746, 52.9225),
    (22, 'Reading',          -0.9781, 51.4543),
    (23, 'Berkshire',        -1.1854, 51.4670);
