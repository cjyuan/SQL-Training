-- Setting precision to 60 because test data contains number with 40+ digits.
-- Setting 0 decimal places so that (num, den) is output as a pair of integers.
CREATE TYPE rational AS (
   num NUMERIC(60, 0),
   den NUMERIC(60, 0)
);

-- Returns the positive GCD of a and b
CREATE OR REPLACE FUNCTION rational_gcd(a NUMERIC, b NUMERIC)
RETURNS NUMERIC 
LANGUAGE plpgsql IMMUTABLE STRICT AS $$
BEGIN
    a := abs(a);
    b := abs(b);
    WHILE b <> 0 LOOP
        a := mod(a, b);
        a := a + b;
        b := a - b;
        a := a - b;
    END LOOP;
    RETURN a;
END;
$$;



-- Returns a normalised and simplified rational number  
CREATE OR REPLACE FUNCTION rational_normalize(n NUMERIC, d NUMERIC)
RETURNS rational
LANGUAGE plpgsql IMMUTABLE STRICT AS $$
DECLARE
    g NUMERIC;
BEGIN
    -- Prevent division by zero
    IF d = 0 THEN
        RAISE EXCEPTION 'division by zero';
    END IF;

    -- Normalize zero
    IF n = 0 THEN
        RETURN (0, 1)::rational;
    END IF;

    -- Largest number of decimal places between n an d
    g := GREATEST(SCALE(n), SCALE(d));
    
    -- Ensure integer numerator and denominator
    IF g > 0 THEN
        n := n * 10^g;
        d := d * 10^g;
    END IF;
    
    -- Ensure positive denominator
    IF d < 0 THEN
        n := -n;
        d := -d;
    END IF;
  
    -- Reduce using GCD
    g := rational_gcd(n, d);
    RETURN (n / g, d / g)::rational;
END;
$$;

CREATE OR REPLACE FUNCTION rational_normalize(rational)
RETURNS rational AS $$
  SELECT rational_normalize($1.num, $1.den);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION rational(n NUMERIC, d NUMERIC)
RETURNS rational AS $$
  SELECT rational_normalize(n, d);
$$ LANGUAGE SQL IMMUTABLE STRICT;


CREATE FUNCTION rational_to_text(r rational)
RETURNS text AS $$
BEGIN
    -- Has to normlise the rational number here to overcome rational created as '(15, 5)'::rational in the test
    r = rational(r.num, r.den); 
                               
    IF r.den = 1 THEN
        RETURN r.num::text;
    END IF;
    RETURN r.num || '/' || r.den;
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE CAST (rational AS text)
WITH FUNCTION rational_to_text(rational);

CREATE CAST (rational AS varchar)
WITH FUNCTION rational_to_text(rational);

CREATE OR REPLACE FUNCTION text_to_rational(t text)
RETURNS rational AS $$
DECLARE
    n numeric;
    d numeric;
    parts text[];
BEGIN
    -- Support row syntax: "(3,4)"
    IF t ~ '^\(.*\)$' THEN
        -- Assume t is valid (not check for error)
        t := trim(both '()' from t);
        n := split_part(t, ',', 1)::numeric;
        d := split_part(t, ',', 2)::numeric;
        RETURN rational(n, d);
    END IF;

    -- Support "a/b"
    IF position('/' in t) > 0 THEN
        parts := string_to_array(t, '/');

        IF array_length(parts,1) != 2 THEN
            RAISE EXCEPTION 'Invalid rational format';
        END IF;

        n := parts[1]::NUMERIC;
        d := parts[2]::NUMERIC;

    ELSE
        -- Support integer input
        n := t::NUMERIC;
        d := 1;
    END IF;

    IF d = 0 THEN
        RAISE EXCEPTION 'Denominator cannot be zero';
    END IF;

    RETURN rational(n, d);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE CAST (text AS rational)
WITH FUNCTION text_to_rational(text)
AS IMPLICIT;

CREATE CAST (varchar AS rational)
WITH FUNCTION text_to_rational(text)
AS IMPLICIT;

------------------ to/from numbers --------------------

-- to/from NUMERIC
CREATE OR REPLACE FUNCTION numeric_to_rational(num numeric)
RETURNS rational AS $$
    SELECT rational(num, 1);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE CAST (numeric AS rational)
WITH FUNCTION numeric_to_rational(numeric)
AS ASSIGNMENT;

CREATE OR REPLACE FUNCTION rational_to_numeric(r rational)
RETURNS numeric AS $$
    SELECT ((r).num / (r).den)::numeric;
$$ LANGUAGE SQL IMMUTABLE STRICT;


CREATE CAST (rational AS numeric)
WITH FUNCTION rational_to_numeric(rational)
AS IMPLICIT;
-- Note: Works when inserting into a table column of type rational or when explicitly 
-- casting, but won't "guess" during complex math operations. This is generally safer
-- for production systems.


-- to/from INT

CREATE OR REPLACE FUNCTION int_to_rational(num int)
RETURNS rational AS $$
    SELECT rational(num, 1);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE CAST (int AS rational)
WITH FUNCTION int_to_rational(int)
AS IMPLICIT;

CREATE OR REPLACE FUNCTION rational_to_int(r rational)
RETURNS int AS $$
    SELECT TRUNC((r).num / (r).den)::INT;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE CAST (rational AS int)
WITH FUNCTION rational_to_int(rational)
AS IMPLICIT;


-- to/from BIGINT

CREATE OR REPLACE FUNCTION bigint_to_rational(num bigint)
RETURNS rational AS $$
    SELECT rational(num, 1);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE CAST (bigint AS rational)
WITH FUNCTION bigint_to_rational(bigint)
AS IMPLICIT;

CREATE OR REPLACE FUNCTION rational_to_bigint(r rational)
RETURNS bigint AS $$
    SELECT TRUNC((r).num / (r).den)::BIGINT;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE CAST (rational AS bigint)
WITH FUNCTION rational_to_bigint(rational)
AS ASSIGNMENT;

--------------------------------------------
CREATE FUNCTION rational_add(r1 rational, r2 rational)
RETURNS rational AS $$
    SELECT rational((r1).num * (r2.den) + (r1).den * (r2).num, (r1).den * (r2).den);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_sub(r1 rational, r2 rational)
RETURNS rational AS $$
    SELECT rational((r1).num * (r2.den) - (r1).den * (r2).num, (r1).den * (r2).den);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_mul(r1 rational, r2 rational)
RETURNS rational AS $$
    SELECT rational((r1).num * (r2).num, (r1).den * (r2).den);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_div(r1 rational, r2 rational)
RETURNS rational AS $$
    SELECT rational((r1).num * (r2).den, (r1).den * (r2).num);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_mod(r1 rational, r2 rational)
RETURNS rational AS $$
DECLARE
    q rational;
    q_int numeric;
BEGIN
    -- q_int = trunc(r1 / r2);
    q = r1 / r2;
    q_int = trunc(q.num / q.den);
    
    -- r1 - r2 * q_int
    return r1 - (r2 * rational(q_int,1));
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE FUNCTION rational_mod(r1 rational, r2 int)
RETURNS rational AS $$
  SELECT rational_mod(r1, rational(r2,1));
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR + (
    leftarg = rational,
    rightarg = rational,
    function = rational_add,
    commutator = +
);

CREATE OPERATOR - (
    leftarg = rational,
    rightarg = rational,
    function = rational_sub
);

CREATE OPERATOR * (
    leftarg = rational,
    rightarg = rational,
    function = rational_mul,
    commutator = *
);

CREATE OPERATOR / (
    leftarg = rational,
    rightarg = rational,
    function = rational_div
);

CREATE OPERATOR % (
    leftarg = rational,
    rightarg = rational,
    function = rational_mod
);

CREATE OPERATOR % (
    leftarg = rational,
    rightarg = int,
    function = rational_mod
);


CREATE FUNCTION rational_neg(r rational)
RETURNS rational AS $$
    SELECT rational(-(r).num, (r).den);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR - (
    rightarg = rational,
    function = rational_neg
);


--------------------------------------------
CREATE FUNCTION rational_cmp_normalized(rational, rational)
RETURNS integer AS $$
    SELECT CASE 
        WHEN ($1.num * $2.den) < ($2.num * $1.den) THEN -1
        WHEN ($1.num * $2.den) > ($2.num * $1.den) THEN 1
        ELSE 0
    END;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_cmp(rational, rational)
RETURNS integer AS $$
    SELECT rational_cmp_normalized(rational_normalize($1), rational_normalize($2));
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_eq(rational, rational) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) = 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR = (
    leftarg = rational, rightarg = rational,
    function = rational_eq,
    commutator = =, negator = <>
);

CREATE FUNCTION rational_ne(rational, rational) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) <> 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR <> (
    leftarg = rational, rightarg = rational,
    function = rational_ne,
    commutator = <>, negator = =
);

CREATE FUNCTION rational_lt(rational, rational) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) < 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR < (
    leftarg = rational, rightarg = rational,
    function = rational_lt,
    commutator = >, negator = >=
);

CREATE FUNCTION rational_gt(rational, rational) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) > 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR > (
    leftarg = rational, rightarg = rational,
    function = rational_gt,
    commutator = <, negator = <=
);

CREATE FUNCTION rational_lt_or_equal(rational, rational) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) <= 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR <= (
    leftarg = rational, rightarg = rational,
    function = rational_lt_or_equal,
    commutator = >=, negator = >
);

CREATE FUNCTION rational_gt_or_equal(rational, rational) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) >= 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR >= (
    leftarg = rational, rightarg = rational,
    function = rational_gt_or_equal,
    commutator = <=, negator = <
);

------------
CREATE FUNCTION rational_cmp(rational, int)
RETURNS integer AS $$
    SELECT rational_cmp_normalized(rational_normalize($1), rational($2, 1));
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_eq(rational, int) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) = 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR = (
    leftarg = rational, rightarg = int,
    function = rational_eq,
    commutator = =, negator = <>
);

CREATE FUNCTION rational_ne(rational, int) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) <> 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR <> (
    leftarg = rational, rightarg = int,
    function = rational_ne,
    commutator = <>, negator = =
);

CREATE FUNCTION rational_lt(rational, int) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) < 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR < (
    leftarg = rational, rightarg = int,
    function = rational_lt,
    commutator = >, negator = >=
);

CREATE FUNCTION rational_gt(rational, int) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) > 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR > (
    leftarg = rational, rightarg = int,
    function = rational_gt,
    commutator = <, negator = <=
);

CREATE FUNCTION rational_lt_or_equal(rational, int) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) <= 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR <= (
    leftarg = rational, rightarg = int,
    function = rational_lt_or_equal,
    commutator = >=, negator = >
);

CREATE FUNCTION rational_gt_or_equal(rational, int) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) >= 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR >= (
    leftarg = rational, rightarg = int,
    function = rational_gt_or_equal,
    commutator = <=, negator = <
);

CREATE FUNCTION numerator(rational)
RETURNS numeric AS $$
    SELECT (rational_normalize($1)).num;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION denominator(rational)
RETURNS numeric AS $$
    SELECT (rational_normalize($1)).den;
$$ LANGUAGE SQL IMMUTABLE STRICT;


CREATE FUNCTION numerator(int)
RETURNS numeric AS $$
    SELECT $1;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION denominator(int)
RETURNS numeric AS $$
    SELECT 1;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION numerator(text)
RETURNS numeric AS $$
    SELECT ($1::rational).num;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION denominator(text)
RETURNS numeric AS $$
    SELECT ($1::rational).den;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR ?/- (
    rightarg = integer,
    function = numerator
);

CREATE OPERATOR ?/- (
    rightarg = rational,
    function = numerator
);

CREATE OPERATOR -/? (
    rightarg = integer,
    function = denominator
);

CREATE OPERATOR -/? (
    rightarg = rational,
    function = denominator
);

CREATE OPERATOR ?/- (
    rightarg = text,
    function = numerator
);

CREATE OPERATOR -/? (
    rightarg = text,
    function = denominator
);
