-- s6/p3 (1/4): uloge (korisnici) kao kod. Idempotentno: uloga se pravi samo ako ne postoji (\gexec),
-- a lozinka se postavlja svaki put iz varijabli koje baza.sh čita iz s6/.lab/pg/lozinke.env (nisu u Gitu).
-- Uloge su globalne za cijelu instancu i NISU dio pg_dump-a: zato su u Gitu i primjenjuju se i prije restore-a.
SET client_min_messages = warning;

SELECT 'CREATE ROLE vlasnik NOLOGIN'          WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'vlasnik')   \gexec
SELECT 'CREATE ROLE app LOGIN'                WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app')       \gexec
SELECT 'CREATE ROLE izvjestaj LOGIN'          WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'izvjestaj') \gexec
SELECT 'CREATE ROLE repl LOGIN REPLICATION'   WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'repl')      \gexec
SELECT 'CREATE ROLE backup LOGIN'             WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'backup')    \gexec

-- vlasnik: posjeduje shemu i tabele, ali se ne može prijaviti (NOLOGIN); migracije rade SET ROLE vlasnik
ALTER ROLE app       PASSWORD :'app_lozinka'       CONNECTION LIMIT 20;   -- aplikacija: čita i piše
ALTER ROLE izvjestaj PASSWORD :'izvjestaj_lozinka' CONNECTION LIMIT 5;    -- izvještaji: samo čita zbirne podatke
ALTER ROLE repl      PASSWORD :'repl_lozinka';                            -- samo replikacija, nema pristup tabelama
ALTER ROLE backup    PASSWORD :'backup_lozinka';
GRANT pg_read_all_data TO backup;                                         -- ugrađena uloga: čita sve, ne piše ništa
