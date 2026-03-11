CREATE TYPE rational AS (
  n numeric,
  d numeric
);

CREATE FUNCTION rational(n numeric, d numeric = 1) RETURNS rational LANGUAGE plpgsql AS $$
DECLARE 
  g numeric;
  s numeric;
BEGIN
  s := 10::numeric ^ greatest(0, scale(n), scale(d));
  n := trim_scale(n * s * sign(d));
  d := trim_scale(d * s * sign(d));
  g := gcd(@n, @d);
  RETURN (DIV(n, g), DIV(d, g))::rational;
END; $$;

CREATE FUNCTION to_rational(n numeric) RETURNS rational LANGUAGE sql AS 'SELECT rational(n)';
CREATE FUNCTION to_rational(n bigint ) RETURNS rational LANGUAGE sql AS 'SELECT (n, 1)::rational';
CREATE FUNCTION to_rational(n int    ) RETURNS rational LANGUAGE sql AS 'SELECT (n, 1)::rational';
CREATE FUNCTION to_rational(s text   ) RETURNS rational LANGUAGE sql AS $$
  SELECT rational(split_part(s,'/', 1)::numeric, split_part(s||'/1', '/', 2)::numeric) $$;

CREATE FUNCTION to_string(r rational) RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  r := rational(r.n, r.d);
  IF r.d = 1 THEN 
    RETURN r.n::text;
  END IF;
  RETURN r.n||'/'||r.d;
END; $$;

CREATE FUNCTION to_bigint (r rational) RETURNS bigint  LANGUAGE sql AS 'SELECT div(r.n, r.d)';
CREATE FUNCTION to_int    (r rational) RETURNS int     LANGUAGE sql AS 'SELECT div(r.n, r.d)';
CREATE FUNCTION to_numeric(r rational) RETURNS numeric LANGUAGE sql AS 'SELECT r.n / r.d'    ;

CREATE CAST (text     AS rational) WITH FUNCTION to_rational(text   ) AS IMPLICIT;
CREATE CAST (numeric  AS rational) WITH FUNCTION to_rational(numeric) AS IMPLICIT;
CREATE CAST (bigint   AS rational) WITH FUNCTION to_rational(bigint ) AS IMPLICIT;
CREATE CAST (int      AS rational) WITH FUNCTION to_rational(int    ) AS IMPLICIT;
CREATE CAST (varchar  AS rational) WITH FUNCTION to_rational(text   ) AS IMPLICIT;
CREATE CAST (rational AS text    ) WITH FUNCTION to_string;
CREATE CAST (rational AS varchar ) WITH FUNCTION to_string;
CREATE CAST (rational AS bigint  ) WITH FUNCTION to_bigint;
CREATE CAST (rational AS int     ) WITH FUNCTION to_int;
CREATE CAST (rational AS numeric ) WITH FUNCTION to_numeric;  

CREATE FUNCTION add(a rational, b rational) RETURNS rational LANGUAGE sql AS 'SELECT rational(a.n * b.d + b.n * a.d, a.d * b.d)'  ;
CREATE FUNCTION sub(a rational, b rational) RETURNS rational LANGUAGE sql AS 'SELECT rational(a.n * b.d - b.n * a.d, a.d * b.d)'  ;
CREATE FUNCTION neg(a rational            ) RETURNS rational LANGUAGE sql AS 'SELECT rational(-a.n, a.d)'                         ;
CREATE FUNCTION mul(a rational, b rational) RETURNS rational LANGUAGE sql AS 'SELECT rational(a.n * b.n, a.d * b.d)'              ;
CREATE FUNCTION div(a rational, b rational) RETURNS rational LANGUAGE sql AS 'SELECT rational(a.n * b.d, a.d * b.n)'              ;
CREATE FUNCTION mod(a rational, b rational) RETURNS rational LANGUAGE sql AS 'SELECT rational(a.n * b.d % (b.n * a.d), a.d * b.d)';

CREATE OPERATOR + (LEFTARG = rational, RIGHTARG = rational, FUNCTION = add, COMMUTATOR = +);
CREATE OPERATOR - (LEFTARG = rational, RIGHTARG = rational, FUNCTION = sub                );
CREATE OPERATOR - (                    RIGHTARG = rational, FUNCTION = neg                );
CREATE OPERATOR * (LEFTARG = rational, RIGHTARG = rational, FUNCTION = mul, COMMUTATOR = *);
CREATE OPERATOR / (LEFTARG = rational, RIGHTARG = rational, FUNCTION = div                );
CREATE OPERATOR % (LEFTARG = rational, RIGHTARG = rational, FUNCTION = mod                );

CREATE FUNCTION eq (a rational, b rational) RETURNS bool LANGUAGE sql AS 'SELECT a.n * b.d = a.d * b.n'                          ;
CREATE FUNCTION ne (a rational, b rational) RETURNS bool LANGUAGE sql AS 'SELECT a.n * b.d <> a.d * b.n'                         ;
CREATE FUNCTION lt (a rational, b rational) RETURNS bool LANGUAGE sql AS 'SELECT a.n * sign(a.d) * @b.d < b.n * sign(b.d) * @a.d';
CREATE FUNCTION gt (a rational, b rational) RETURNS bool LANGUAGE sql AS 'SELECT a.n * sign(a.d) * @b.d > b.n * sign(b.d) * @a.d';
CREATE FUNCTION lte(a rational, b rational) RETURNS bool LANGUAGE sql AS 'SELECT a = b or a < b'                                 ;
CREATE FUNCTION gte(a rational, b rational) RETURNS bool LANGUAGE sql AS 'SELECT a = b or a > b'                                 ;

CREATE OPERATOR =  (LEFTARG = rational, RIGHTARG = rational, FUNCTION = eq , COMMUTATOR = = , NEGATOR = <>);
CREATE OPERATOR <> (LEFTARG = rational, RIGHTARG = rational, FUNCTION = ne , COMMUTATOR = <>, NEGATOR = = );
CREATE OPERATOR <  (LEFTARG = rational, RIGHTARG = rational, FUNCTION = lt , COMMUTATOR = > , NEGATOR = >=);
CREATE OPERATOR >  (LEFTARG = rational, RIGHTARG = rational, FUNCTION = gt , COMMUTATOR = < , NEGATOR = <=);
CREATE OPERATOR <= (LEFTARG = rational, RIGHTARG = rational, FUNCTION = lte, COMMUTATOR = >=, NEGATOR = > );
CREATE OPERATOR >= (LEFTARG = rational, RIGHTARG = rational, FUNCTION = gte, COMMUTATOR = <=, NEGATOR = < );

CREATE FUNCTION numerator  (a rational) RETURNS numeric LANGUAGE sql AS 'SELECT (rational(a.n, a.d)).n';
CREATE FUNCTION denominator(a rational) RETURNS numeric LANGUAGE sql AS 'SELECT (rational(a.n, a.d)).d';

CREATE OPERATOR ?/- (RIGHTARG = rational, FUNCTION = numerator  );
CREATE OPERATOR -/? (RIGHTARG = rational, FUNCTION = denominator);
