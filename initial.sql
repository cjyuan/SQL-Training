-- Setting precision to 60 because test data contains number with 40+ digits.
-- Setting 0 decimal places so that (num, den) is output as a pair of integers.
CREATE TYPE rational AS ( num NUMERIC(60), den NUMERIC(60) );

-- Returns the positive GCD of a and b
CREATE OR REPLACE FUNCTION rational_gcd(a NUMERIC, b NUMERIC) 
RETURNS numeric
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
CREATE OR REPLACE FUNCTION rational_normalize(n numeric, d numeric)
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

CREATE OR REPLACE FUNCTION rational(rational)
RETURNS rational AS $$
  SELECT rational_normalize($1.num, $1.den);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION rational(numeric, numeric)
RETURNS rational AS $$
  SELECT rational_normalize($1, $2);
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

CREATE CAST (rational AS text) WITH FUNCTION rational_to_text(rational);
CREATE CAST (rational AS varchar) WITH FUNCTION rational_to_text(rational);

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

CREATE CAST (text AS rational) WITH FUNCTION text_to_rational(text) AS IMPLICIT;
CREATE CAST (varchar AS rational) WITH FUNCTION text_to_rational(text) AS IMPLICIT;

---- to/from numeric, int, bigint ----
CREATE OR REPLACE FUNCTION numeric_to_rational(numeric) RETURNS rational AS $$
    SELECT rational($1, 1);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION rational_to_numeric(rational) RETURNS numeric AS $$
    SELECT ($1.num / $1.den)::numeric;
$$ LANGUAGE SQL IMMUTABLE STRICT;


CREATE OR REPLACE FUNCTION int_to_rational(int) RETURNS rational AS $$
    SELECT rational($1, 1);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION rational_to_int(rational) RETURNS int AS $$
    SELECT TRUNC($1.num / $1.den)::int;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION bigint_to_rational(bigint) RETURNS rational AS $$
    SELECT rational($1, 1);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OR REPLACE FUNCTION rational_to_bigint(rational) RETURNS bigint AS $$
    SELECT TRUNC($1.num / $1.den)::bigint;
$$ LANGUAGE SQL IMMUTABLE STRICT;

-- Note: Casting from smaller type to rational can be made implicit so that in expressions such as
--         2 + rational(2, 3) or rational(2, 3) + 2
--       2 is casted to rational type first. This way, we don't have to explicily overload 
--       the binary operators for every combination of number type and rational type.

--       Casting from rational to smaller types should be explicit.

CREATE CAST (numeric AS rational) WITH FUNCTION numeric_to_rational(numeric) AS IMPLICIT;
CREATE CAST (rational AS numeric) WITH FUNCTION rational_to_numeric(rational);

CREATE CAST (int AS rational) WITH FUNCTION int_to_rational(int) AS IMPLICIT;
CREATE CAST (rational AS int) WITH FUNCTION rational_to_int(rational);

CREATE CAST (bigint AS rational) WITH FUNCTION bigint_to_rational(bigint) AS IMPLICIT;
CREATE CAST (rational AS bigint) WITH FUNCTION rational_to_bigint(rational);


---- OVERLOAD operators +, - (subtraction and negation), *, /, % 
CREATE FUNCTION rational_add(rational, rational) RETURNS rational AS $$
    SELECT rational($1.num * $2.den + $1.den * $2.num, $1.den * $2.den);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_sub(rational, rational) RETURNS rational AS $$
    SELECT rational($1.num * $2.den - $1.den * $2.num, $1.den * $2.den);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_mul(rational, rational) RETURNS rational AS $$
    SELECT rational($1.num * $2.num, $1.den * $2.den);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_div(rational, rational) RETURNS rational AS $$
    SELECT rational($1.num * $2.den, $1.den * $2.num);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR + ( leftarg = rational, rightarg = rational, function = rational_add, commutator = + );
CREATE OPERATOR - ( leftarg = rational, rightarg = rational, function = rational_sub );
CREATE OPERATOR * ( leftarg = rational, rightarg = rational, function = rational_mul, commutator = * );
CREATE OPERATOR / ( leftarg = rational, rightarg = rational, function = rational_div );


CREATE FUNCTION rational_mod(rational, rational) RETURNS rational AS $$
    -- Compute the remainder as $1 - $2 * quotient of ($1/$2)
    SELECT $1 - $2 * rational(trunc(($1 / $2)::numeric), 1);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR % ( leftarg = rational, rightarg = rational, function = rational_mod(rational, rational) );

CREATE FUNCTION rational_neg(rational) RETURNS rational AS $$
    SELECT rational(-$1.num, $1.den);
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR - ( rightarg = rational, function = rational_neg );

---- Relational operators ----
CREATE FUNCTION rational_normalized_cmp(rational, rational) RETURNS int AS $$
    SELECT CASE 
        WHEN ($1.num * $2.den) < ($2.num * $1.den) THEN -1
        WHEN ($1.num * $2.den) > ($2.num * $1.den) THEN 1
        ELSE 0
    END;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_cmp(rational, rational) RETURNS int AS $$
    SELECT rational_normalized_cmp(rational($1), rational($2));
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_eq(rational, rational) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) = 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_ne(rational, rational) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) <> 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_lt(rational, rational) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) < 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_gt(rational, rational) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) > 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_lt_or_equal(rational, rational) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) <= 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION rational_gt_or_equal(rational, rational) RETURNS boolean AS $$
    SELECT rational_cmp($1, $2) >= 0;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR = (
    leftarg = rational, rightarg = rational, 
    function = rational_eq, commutator = =, negator = <> 
);
CREATE OPERATOR <> ( 
    leftarg = rational, rightarg = rational, 
    function = rational_ne, commutator = <>, negator = = 
);
CREATE OPERATOR < (
    leftarg = rational, rightarg = rational,
    function = rational_lt, commutator = >, negator = >=
);
CREATE OPERATOR > (
    leftarg = rational, rightarg = rational,
    function = rational_gt, commutator = <, negator = <=
);
CREATE OPERATOR <= (
    leftarg = rational, rightarg = rational,
    function = rational_lt_or_equal, commutator = >=, negator = >
);
CREATE OPERATOR >= (
    leftarg = rational, rightarg = rational,
    function = rational_gt_or_equal, commutator = <=, negator = <
);

---- numerator() and denominator() and their corresponding custom operators
CREATE FUNCTION numerator(rational) RETURNS numeric AS $$
    SELECT (rational($1)).num;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION denominator(rational) RETURNS numeric AS $$
    SELECT (rational($1)).den;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION numerator(text) RETURNS numeric AS $$
    SELECT ($1::rational).num;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE FUNCTION denominator(text) RETURNS numeric AS $$
    SELECT ($1::rational).den;
$$ LANGUAGE SQL IMMUTABLE STRICT;

CREATE OPERATOR ?/- ( rightarg = rational, function = numerator(rational) );
CREATE OPERATOR -/? ( rightarg = rational, function = denominator(rational) );
CREATE OPERATOR ?/- ( rightarg = text, function = numerator(text) );
CREATE OPERATOR -/? ( rightarg = text, function = denominator(text) );

