
SELECT format('CREATE ROLE svc_monitoring LOGIN PASSWORD %L', :'monitoring_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'svc_monitoring')
\gexec

ALTER ROLE svc_monitoring WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION
  CONNECTION LIMIT 5 PASSWORD :'monitoring_password';

GRANT pg_monitor TO svc_monitoring;

GRANT CONNECT ON DATABASE postgres TO svc_monitoring;
GRANT CONNECT ON DATABASE test_db1 TO svc_monitoring;
