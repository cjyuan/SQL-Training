CREATE TYPE rational AS (
   num   NUMERIC,
   den   NUMERIC
);

CREATE FUNCTION rational_to_text(r rational)
RETURNS text AS $$
BEGIN
    IF r.den = 1 THEN
        RETURN trunc(r.num)::text;
    END IF;
    RETURN trunc(r.num) || '/' || trunc(r.den);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE CAST (rational AS text)
WITH FUNCTION rational_to_text(rational);


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

CREATE OR REPLACE FUNCTION text_to_rational(t text)
RETURNS rational AS $$
DECLARE
    n numeric;
    d numeric;
    parts text[];
BEGIN
    -- Support row syntax: "(3,4)"
    IF t ~ '^\(.*\)$' THEN
        RETURN t::rational;
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

    RETURN rational(n,d);
END;
$$ LANGUAGE plpgsql IMMUTABLE STRICT;

CREATE CAST (text AS rational)
WITH FUNCTION text_to_rational(text)
AS IMPLICIT;

CREATE CAST (varchar AS rational)
WITH FUNCTION text_to_rational(text)
AS IMPLICIT;


CREATE OR REPLACE FUNCTION rational(n NUMERIC, d NUMERIC)
RETURNS rational
LANGUAGE plpgsql
IMMUTABLE
STRICT
AS $$
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
