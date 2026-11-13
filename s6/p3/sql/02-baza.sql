-- s6/p3 (2/4): baza i pravo spajanja. Ovo pg_dump -C čuva (vlasnik i ACL baze), pa restore ne treba ovu datoteku.
SET client_min_messages = warning;

SELECT 'CREATE DATABASE prodavnica OWNER vlasnik'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'prodavnica') \gexec

REVOKE ALL ON DATABASE prodavnica FROM PUBLIC;                 -- zadano: svako smije CONNECT; ukidamo
GRANT CONNECT ON DATABASE prodavnica TO app, izvjestaj, backup;
