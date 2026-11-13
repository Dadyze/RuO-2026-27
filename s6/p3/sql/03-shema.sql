-- s6/p3 (3/4): shema kao kod (u pravom projektu: alat za migracije, npr. Flyway, Liquibase, Alembic).
-- Objekte pravi i posjeduje uloga vlasnik, ne aplikacija: app ih ne može obrisati ni izmijeniti strukturu.
\connect prodavnica
SET client_min_messages = warning;
SET ROLE vlasnik;

CREATE SCHEMA IF NOT EXISTS prodaja;

CREATE TABLE IF NOT EXISTS prodaja.kupci (
  id      bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  ime     text NOT NULL,
  email   text NOT NULL UNIQUE                     -- lični podatak: izvještaji ga ne smiju vidjeti
);

CREATE TABLE IF NOT EXISTS prodaja.narudzbe (
  id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  kupac_id bigint NOT NULL REFERENCES prodaja.kupci,
  iznos    numeric(10,2) NOT NULL CHECK (iznos > 0),
  vrijeme  timestamptz NOT NULL DEFAULT now()
);

-- izvještaji vide samo zbirne brojke, bez kupaca
CREATE OR REPLACE VIEW prodaja.v_promet_po_danu AS
  SELECT vrijeme::date AS dan, count(*) AS narudzbi, sum(iznos) AS promet
  FROM prodaja.narudzbe GROUP BY 1;

INSERT INTO prodaja.kupci (ime, email) VALUES
  ('Amra', 'amra@ruo.lab'), ('Bojan', 'bojan@ruo.lab'), ('Cvijeta', 'cvijeta@ruo.lab')
ON CONFLICT (email) DO NOTHING;

RESET ROLE;
