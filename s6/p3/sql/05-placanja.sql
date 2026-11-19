-- s6/p3 (5/5): nova migracija - evidencija placanja (Sedmica 6, zadatak 4)
-- Objekte kreira uloga vlasnik; zbog ALTER DEFAULT PRIVILEGES iz 04-privilegije.sql,
-- uloga app automatski dobija SELECT, INSERT i UPDATE privilegije bez izmjene 04-privilegije.sql.
\connect prodavnica
SET client_min_messages = warning;
SET ROLE vlasnik;

CREATE TABLE IF NOT EXISTS prodaja.placanja (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  narudzba_id bigint NOT NULL REFERENCES prodaja.narudzbe(id),
  iznos       numeric(10,2) NOT NULL CHECK (iznos > 0),
  metoda      text NOT NULL,
  vrijeme     timestamptz NOT NULL DEFAULT now()
);

RESET ROLE;
