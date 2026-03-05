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
CREATE OR REPLACE FUNCTION rational(n NUMERIC, d NUMERIC)
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

CREATE FUNCTION rational_to_text(r rational)
RETURNS text AS $$
BEGIN
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


