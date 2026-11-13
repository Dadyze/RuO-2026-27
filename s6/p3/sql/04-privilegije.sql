-- s6/p3 (4/4): privilegije. Načelo najmanjih prava: svaka uloga dobija tačno ono što joj treba.
\connect prodavnica
SET client_min_messages = warning;

REVOKE ALL ON SCHEMA public FROM PUBLIC;                       -- niko ne pravi objekte u public shemi
GRANT USAGE ON SCHEMA prodaja TO app, izvjestaj;

-- app: čita i piše, ali ne briše redove i ne mijenja strukturu (nije vlasnik)
GRANT SELECT, INSERT, UPDATE ON prodaja.kupci, prodaja.narudzbe TO app;
-- izvjestaj: samo pogled sa zbirnim podacima
GRANT SELECT ON prodaja.v_promet_po_danu TO izvjestaj;

-- tabele koje vlasnik napravi ubuduće automatski dobijaju ista prava za app
ALTER DEFAULT PRIVILEGES FOR ROLE vlasnik IN SCHEMA prodaja GRANT SELECT, INSERT, UPDATE ON TABLES TO app;
