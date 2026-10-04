SELECT format('CREATE ROLE test_user LOGIN PASSWORD %L', :'test_user_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'test_user')
\gexec

ALTER ROLE test_user WITH LOGIN PASSWORD :'test_user_password';

SELECT 'CREATE DATABASE test_db1 OWNER test_user'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'test_db1')
\gexec

ALTER DATABASE test_db1 OWNER TO test_user;

GRANT ALL PRIVILEGES ON DATABASE test_db1 TO test_user;
